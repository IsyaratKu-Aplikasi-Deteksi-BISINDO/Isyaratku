
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';

import '../services/api_service.dart';
import '../services/tts_service.dart';
import '../widgets/detection_info_panel.dart';
import '../models/detection_data.dart';
import '../services/detection_service.dart';

// =====================================================
// HOME PAGE
// =====================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const MethodChannel _holisticChannel =
      MethodChannel('bisindo/holistic');

  final DetectionService _detectionService = DetectionService();
  final ApiService _apiService = ApiService();
  final TtsService _ttsService = TtsService();

  PredictionResult? _predictionResult;

  bool _isPredicting = false;
  bool _ttsReady = false;

  static const int sequenceLength = 30;
  static const int rawDimension = 108;
  static const int modelDimension = 66;
  static const int frameIntervalMs = 250;

  CameraController? _cameraController;

  // CAMERA SWITCH
  List<CameraDescription> _availableCameras = [];
  int _currentCameraIndex = 0;

  bool isDetecting = false;
  bool isLoading = false;
  bool isHolisticInitialized = false;
  bool _isProcessingFrame = false;
  bool _isExportingJson = false;

  bool leftHandDetected = false;
  bool rightHandDetected = false;

  int frameCount = 0;

  int poseLandmarkCount = 0;
  int leftHandLandmarkCount = 0;
  int rightHandLandmarkCount = 0;

  List<double> bodyCoordinates = [];
  List<double> leftHandCoordinates = [];
  List<double> rightHandCoordinates = [];

  final List<List<double>> _rawSequence = [];

  List<List<double>> _lastRawSequence = [];
  List<List<double>> _lastNormalizedSequence = [];
  List<List<double>> _lastSelectedFeatures = [];

  List<double> normalizedCoordinates = [];
  List<double> modelInput = [];

  int completedSequences = 0;

  DateTime _lastFrameUpdate = DateTime.now();

  String cameraStatus = 'Kamera belum diaktifkan';
  String? errorMessage;

  // =====================================================
  // INITIALIZE TTS
  // =====================================================

  @override
  void initState() {
    super.initState();
    _initializeTts();
  }

  Future<void> _initializeTts() async {
    try {
      await _ttsService.initialize();

      if (!mounted) return;

      setState(() {
        _ttsReady = true;
      });

      debugPrint('TEXT TO SPEECH BERHASIL DIINISIALISASI');
    } catch (e) {
      debugPrint('ERROR INITIALIZE TTS: $e');
    }
  }

  // =====================================================
  // SPEAK PREDICTION
  // =====================================================

  Future<void> _speakPrediction(String text) async {
    try {
      if (!_ttsReady) {
        await _initializeTts();
      }

      if (!_ttsReady) return;

      await _ttsService.speak(text);
    } catch (e) {
      debugPrint('ERROR TEXT TO SPEECH: $e');
    }
  }

  // =====================================================
  // READ COORDINATES
  // =====================================================

  List<double> _readCoordinates(dynamic value) {
    if (value == null) return [];

    return (value as List)
        .map((coordinate) => (coordinate as num).toDouble())
        .toList();
  }

  // =====================================================
  // VALIDASI BODY LANDMARK
  // =====================================================

  bool _hasValidBodyLandmarks(
    List<double> body,
    int landmarkCount,
  ) {
    if (landmarkCount <= 0) {
      return false;
    }

    if (body.length < 24) {
      return false;
    }

    // 0 = Nose, 1 = Neck, 3 = Left Eye.
    const requiredPoints = [0, 1, 3];

    for (final index in requiredPoints) {
      final x = body[index * 2];
      final y = body[index * 2 + 1];

      if (!x.isFinite || !y.isFinite) {
        return false;
      }

      if (x == 0.0 || y == 0.0) {
        return false;
      }
    }

    return true;
  }

  // =====================================================
  // CREATE RAW FRAME (108D)
  // =====================================================

  List<double> _createRawFrame(
    List<double> body,
    List<double> leftHand,
    List<double> rightHand,
  ) {
    return _detectionService.createRawFrame(
      body,
      leftHand,
      rightHand,
    );
  }

  // =====================================================
  // PROCESS COMPLETE SEQUENCE + FASTAPI PREDICTION
  // =====================================================

  Future<void> _processCompletedSequence() async {
    if (_rawSequence.length != sequenceLength) return;

    try {
      // Memproses sequence 30 frame × 108 fitur
      // menjadi 30 frame × 66 fitur.
      final result =
          _detectionService.processSequence(_rawSequence);

      setState(() {
        _lastRawSequence = result.rawSequence;

        _lastNormalizedSequence = result.normalizedSequence
            .map((frame) => List<double>.from(frame))
            .toList();

        _lastSelectedFeatures = result.selectedFeatures
            .map((frame) => List<double>.from(frame))
            .toList();

        normalizedCoordinates =
            List<double>.from(result.selectedFeatures.last);

        modelInput = result.flattenedInput;

        completedSequences++;

        _isPredicting = true;
        _predictionResult = null;
        errorMessage = null;
      });

      debugPrint('SEQUENCE BERHASIL DIPROSES');
      debugPrint('Jumlah frame: ${result.selectedFeatures.length}');
      debugPrint(
        'Jumlah fitur: ${result.selectedFeatures.first.length}',
      );

      // Mengirim sequence 30 × 66 ke FastAPI.
      final prediction = await _apiService.predict(
        result.selectedFeatures,
      );

      if (!mounted) return;

      setState(() {
        _predictionResult = prediction;
        _isPredicting = false;
        errorMessage = null;
      });

      debugPrint('PREDIKSI BERHASIL');
      debugPrint('Label: ${prediction.label}');
      debugPrint('Confidence: ${prediction.confidence}');

      // TTS TIDAK dijalankan otomatis.
      // Pengucapan hanya melalui tombol speaker.
    } catch (e, stackTrace) {
      debugPrint('ERROR PROCESS SEQUENCE / API: $e');
      debugPrint('STACK TRACE: $stackTrace');

      if (mounted) {
        setState(() {
          _isPredicting = false;
          errorMessage = 'Prediksi gagal: $e';
        });
      }
    } finally {
      _rawSequence.clear();
    }
  }

  // =====================================================
  // VALIDATION SUMMARY
  // =====================================================

  String _buildValidationSummary() {
    final raw = _lastRawSequence;
    final normalized = _lastNormalizedSequence;
    final features = _lastSelectedFeatures;

    int rawRightHandNonZero = 0;
    int rawRightHandZero = 0;

    int normalizedRightHandNonZero = 0;
    int normalizedRightHandZero = 0;

    int modelNonFinite = 0;
    int modelZero = 0;
    int modelNonZero = 0;

    int rawNonFinite = 0;
    int normalizedNonFinite = 0;

    for (final frame in raw) {
      for (int i = 66; i < 108; i++) {
        final value = frame[i];

        if (!value.isFinite) {
          continue;
        } else if (value == 0.0) {
          rawRightHandZero++;
        } else {
          rawRightHandNonZero++;
        }
      }
    }

    for (final frame in normalized) {
      for (int i = 66; i < 108; i++) {
        final value = frame[i];

        if (value.isFinite) {
          if (value == 0.0) {
            normalizedRightHandZero++;
          } else {
            normalizedRightHandNonZero++;
          }
        }
      }
    }

    for (final frame in features) {
      for (final value in frame) {
        if (!value.isFinite) {
          modelNonFinite++;
        } else if (value == 0.0) {
          modelZero++;
        } else {
          modelNonZero++;
        }
      }
    }

    for (final frame in raw) {
      for (final value in frame) {
        if (!value.isFinite) {
          rawNonFinite++;
        }
      }
    }

    for (final frame in normalized) {
      for (final value in frame) {
        if (!value.isFinite) {
          normalizedNonFinite++;
        }
      }
    }

    final firstFrame =
        features.isNotEmpty ? features.first : <double>[];

    final lastFrame =
        features.isNotEmpty ? features.last : <double>[];

    final firstSample = firstFrame.take(8).toList();
    final lastSample = lastFrame.take(8).toList();

    final rightHandSample = raw.isNotEmpty
        ? raw.first.sublist(66, 74)
        : <double>[];

    final summary = StringBuffer();

    summary.writeln('=== BISINDO VALIDATION SUMMARY ===');
    summary.writeln('');

    summary.writeln('SEQUENCE DIMENSIONS');
    summary.writeln('Raw sequence: ${raw.length} x $rawDimension');
    summary.writeln(
      'Normalized sequence: ${normalized.length} x $rawDimension',
    );
    summary.writeln(
      'Model features: ${features.length} x $modelDimension',
    );
    summary.writeln('Flattened input: ${modelInput.length}');
    summary.writeln('');

    summary.writeln('RAW RIGHT HAND');
    summary.writeln('Non-zero values: $rawRightHandNonZero');
    summary.writeln('Zero values: $rawRightHandZero');
    summary.writeln('Total expected: ${sequenceLength * 42}');
    summary.writeln('First frame sample: $rightHandSample');
    summary.writeln('');

    summary.writeln('NORMALIZED RIGHT HAND');
    summary.writeln(
      'Non-zero values: $normalizedRightHandNonZero',
    );
    summary.writeln(
      'Zero values: $normalizedRightHandZero',
    );
    summary.writeln('Total expected: ${sequenceLength * 42}');
    summary.writeln('');

    summary.writeln('MODEL INPUT');
    summary.writeln('Non-zero values: $modelNonZero');
    summary.writeln('Zero values: $modelZero');
    summary.writeln('Non-finite values: $modelNonFinite');
    summary.writeln('First frame sample: $firstSample');
    summary.writeln('Last frame sample: $lastSample');
    summary.writeln('');

    summary.writeln('DATA QUALITY');
    summary.writeln('Raw non-finite values: $rawNonFinite');
    summary.writeln(
      'Normalized non-finite values: $normalizedNonFinite',
    );
    summary.writeln('');

    summary.writeln('VALIDATION STATUS');

    final dimensionsCorrect =
        raw.length == sequenceLength &&
        normalized.length == sequenceLength &&
        features.length == sequenceLength &&
        modelInput.length == sequenceLength * modelDimension;

    summary.writeln(
      'Dimensions correct: ${dimensionsCorrect ? "YES" : "NO"}',
    );
    summary.writeln(
      'Right hand detected in raw data: '
      '${rawRightHandNonZero > 0 ? "YES" : "NO"}',
    );
    summary.writeln(
      'Model input finite: ${modelNonFinite == 0 ? "YES" : "NO"}',
    );

    return summary.toString();
  }

  // =====================================================
  // COPY VALIDATION SUMMARY
  // =====================================================

  Future<void> _copyValidationData() async {
    if (_lastRawSequence.length != sequenceLength ||
        _lastNormalizedSequence.length != sequenceLength ||
        _lastSelectedFeatures.length != sequenceLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Belum ada sequence lengkap untuk divalidasi.',
          ),
        ),
      );
      return;
    }

    final summary = _buildValidationSummary();

    await Clipboard.setData(
      ClipboardData(text: summary),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Ringkasan validasi berhasil disalin!',
        ),
      ),
    );
  }

  // =====================================================
  // EXPORT VALIDATION DATA TO JSON
  // =====================================================

  Future<void> _exportValidationJson() async {
    if (_isExportingJson) return;

    final raw = _lastRawSequence;
    final normalized = _lastNormalizedSequence;
    final features = _lastSelectedFeatures;

    if (raw.length != sequenceLength ||
        normalized.length != sequenceLength ||
        features.length != sequenceLength ||
        features.any(
          (frame) => frame.length != modelDimension,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Belum ada sequence lengkap untuk diekspor.',
          ),
        ),
      );
      return;
    }

    final flattened = features.expand((frame) => frame).toList();

    if (flattened.length != sequenceLength * modelDimension) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dimensi model input tidak sesuai.'),
        ),
      );
      return;
    }

    setState(() {
      _isExportingJson = true;
    });

    try {
      final exportData = {
        'metadata': {
          'project': 'BISINDO Mobile',
          'format_version': 1,
          'generated_at': DateTime.now().toIso8601String(),
          'sequence_length': sequenceLength,
          'raw_dimension': rawDimension,
          'model_dimension': modelDimension,
          'normalization': 'body_relative',
          'model_feature_selection': 'body_24D + right_hand_42D',
          'coordinate_order': {
            'raw': [
              'body_24D',
              'left_hand_42D',
              'right_hand_42D',
            ],
            'model': [
              'body_24D',
              'right_hand_42D',
            ],
          },
        },
        'dimensions': {
          'raw_sequence': [sequenceLength, rawDimension],
          'normalized_sequence': [sequenceLength, rawDimension],
          'model_features': [sequenceLength, modelDimension],
          'flattened_model_input': [
            sequenceLength * modelDimension,
          ],
        },
        'raw_sequence': raw,
        'normalized_sequence': normalized,
        'model_features': features,
        'flattened_model_input': flattened,
        'validation_summary': _buildValidationSummary(),
      };

      final jsonString =
          const JsonEncoder.withIndent('  ').convert(exportData);

      final bytes = Uint8List.fromList(
        utf8.encode(jsonString),
      );

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');

      final output = await FilePicker.saveFile(
        dialogTitle: 'Simpan Data Validasi BISINDO',
        fileName: 'bisindo_validation_$timestamp.json',
        bytes: bytes,
      );

      if (!mounted) return;

      if (output == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ekspor dibatalkan.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Data validasi JSON berhasil diekspor!',
            ),
            duration: Duration(seconds: 4),
          ),
        );

        debugPrint('JSON berhasil disimpan: $output');
        debugPrint('Ukuran JSON: ${bytes.length} bytes');
      }
    } catch (e, stackTrace) {
      debugPrint('ERROR EXPORT JSON: $e');
      debugPrint('STACK TRACE: $stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengekspor JSON: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExportingJson = false;
        });
      }
    }
  }

  // =====================================================
  // PROCESS CAMERA FRAME
  // =====================================================

  Future<void> processCameraFrame(
    CameraImage image,
    CameraController controller,
  ) async {
    if (_isProcessingFrame || !isHolisticInitialized) {
      return;
    }

    if (image.planes.length < 3) {
      return;
    }

    _isProcessingFrame = true;

    debugPrint(
      'CAMERA FRAME SIZE: ${image.width} x ${image.height}',
    );

    try {
      final result =
          await _holisticChannel.invokeMapMethod<String, dynamic>(
        'processFrame',
        {
          'width': image.width,
          'height': image.height,
          'y': image.planes[0].bytes,
          'u': image.planes[1].bytes,
          'v': image.planes[2].bytes,
          'yRowStride': image.planes[0].bytesPerRow,
          'uRowStride': image.planes[1].bytesPerRow,
          'vRowStride': image.planes[2].bytesPerRow,
          'yPixelStride': image.planes[0].bytesPerPixel ?? 1,
          'uPixelStride': image.planes[1].bytesPerPixel ?? 1,
          'vPixelStride': image.planes[2].bytesPerPixel ?? 1,
          'rotation': controller.description.sensorOrientation,
        },
      );

      if (!mounted || result == null) {
        return;
      }

      // 1. BACA HASIL MEDIAPIPE
      final newBodyCoordinates =
          _readCoordinates(result['bodyCoordinates']);

      final newLeftHandCoordinates =
          _readCoordinates(result['leftHandCoordinates']);

      final newRightHandCoordinates =
          _readCoordinates(result['rightHandCoordinates']);

      final newPoseLandmarkCount =
          result['pose'] as int? ?? 0;

      final newLeftHandLandmarkCount =
          result['leftHand'] as int? ?? 0;

      final newRightHandLandmarkCount =
          result['rightHand'] as int? ?? 0;

      final newLeftHandDetected =
          result['leftHandDetected'] as bool? ?? false;

      final newRightHandDetected =
          result['rightHandDetected'] as bool? ?? false;

      // 2. VALIDASI BODY
      final bodyValid = _hasValidBodyLandmarks(
        newBodyCoordinates,
        newPoseLandmarkCount,
      );

      // 3. SIAPKAN DATA DETEKSI
      final bodyData = bodyValid
          ? newBodyCoordinates
          : <double>[];

      final leftData = newLeftHandDetected
          ? newLeftHandCoordinates
          : <double>[];

      final rightData = newRightHandDetected
          ? newRightHandCoordinates
          : <double>[];

      final detectionData = DetectionData(
        bodyCoordinates: bodyData,
        leftHandCoordinates: leftData,
        rightHandCoordinates: rightData,
        poseLandmarkCount: newPoseLandmarkCount,
        leftHandLandmarkCount: newLeftHandLandmarkCount,
        rightHandLandmarkCount: newRightHandLandmarkCount,
        leftHandDetected: newLeftHandDetected,
        rightHandDetected: newRightHandDetected,
      );

      // 4. JIKA BODY TIDAK TERDETEKSI
      if (!bodyValid) {
        if (_rawSequence.isNotEmpty) {
          debugPrint(
            'BODY HILANG - RESET SEQUENCE '
            '(${_rawSequence.length}/$sequenceLength frame)',
          );

          _rawSequence.clear();
        }

        if (!mounted) return;

        setState(() {
          frameCount++;

          poseLandmarkCount =
              detectionData.poseLandmarkCount;

          leftHandLandmarkCount =
              detectionData.leftHandLandmarkCount;

          rightHandLandmarkCount =
              detectionData.rightHandLandmarkCount;

          leftHandDetected =
              detectionData.leftHandDetected;

          rightHandDetected =
              detectionData.rightHandDetected;

          bodyCoordinates = [];
          leftHandCoordinates =
              detectionData.leftHandCoordinates;

          rightHandCoordinates =
              detectionData.rightHandCoordinates;
        });

        debugPrint('Frame dilewati: body tidak valid.');
        return;
      }

      // 5. BUAT RAW FRAME 108D
      // Body wajib valid. Kedua tangan boleh tidak terdeteksi.
      final rawFrame = _createRawFrame(
        detectionData.bodyCoordinates,
        detectionData.leftHandCoordinates,
        detectionData.rightHandCoordinates,
      );

      if (rawFrame.length != rawDimension) {
        throw StateError(
          'Raw frame harus $rawDimension dimensi, '
          'ditemukan ${rawFrame.length}.',
        );
      }

      // 6. KUMPULKAN SEQUENCE
      _rawSequence.add(rawFrame);

      debugPrint(
        'FRAME VALID: ${_rawSequence.length}/$sequenceLength '
        '| Camera: ${image.width} x ${image.height} '
        '| Body: VALID '
        '| Right Hand: '
        '${detectionData.rightHandDetected ? "DETECTED" : "NOT DETECTED"}',
      );

      // 7. JIKA 30 FRAME TERPENUHI, TUNGGU PROSES API SELESAI.
      if (_rawSequence.length == sequenceLength) {
        await _processCompletedSequence();
      }

      // 8. UPDATE UI
      if (!mounted) return;

      setState(() {
        frameCount++;

        poseLandmarkCount =
            detectionData.poseLandmarkCount;

        leftHandLandmarkCount =
            detectionData.leftHandLandmarkCount;

        rightHandLandmarkCount =
            detectionData.rightHandLandmarkCount;

        leftHandDetected =
            detectionData.leftHandDetected;

        rightHandDetected =
            detectionData.rightHandDetected;

        bodyCoordinates =
            detectionData.bodyCoordinates;

        leftHandCoordinates =
            detectionData.leftHandCoordinates;

        rightHandCoordinates =
            detectionData.rightHandCoordinates;
      });
    } catch (e, stackTrace) {
      debugPrint('ERROR PROCESS FRAME: $e');
      debugPrint('STACK TRACE: $stackTrace');

      if (mounted) {
        setState(() {
          errorMessage = 'Pemrosesan frame gagal: $e';
          _isPredicting = false;
        });
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  // =====================================================
  // START CAMERA IMAGE STREAM
  // =====================================================

  Future<void> _startCameraImageStream(
    CameraController controller,
  ) async {
    _lastFrameUpdate = DateTime.now();

    await controller.startImageStream((CameraImage image) {
      final now = DateTime.now();

      if (!_isProcessingFrame &&
          isHolisticInitialized &&
          now.difference(_lastFrameUpdate).inMilliseconds >=
              frameIntervalMs) {
        _lastFrameUpdate = now;
        processCameraFrame(image, controller);
      }
    });
  }

  // =====================================================
  // START CAMERA
  // =====================================================

  Future<void> startCamera() async {
    CameraController? controller;

    setState(() {
      isLoading = true;
      errorMessage = null;

      frameCount = 0;

      poseLandmarkCount = 0;
      leftHandLandmarkCount = 0;
      rightHandLandmarkCount = 0;

      leftHandDetected = false;
      rightHandDetected = false;

      bodyCoordinates = [];
      leftHandCoordinates = [];
      rightHandCoordinates = [];

      _rawSequence.clear();

      _lastRawSequence = [];
      _lastNormalizedSequence = [];
      _lastSelectedFeatures = [];

      normalizedCoordinates = [];
      modelInput = [];
      completedSequences = 0;

      _predictionResult = null;
      _isPredicting = false;

      cameraStatus = 'Mengaktifkan kamera...';
    });

    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('Kamera tidak ditemukan.');
      }

      _availableCameras = cameras;

      // Prioritaskan kamera depan.
      final frontCameraIndex = cameras.indexWhere(
        (camera) =>
            camera.lensDirection == CameraLensDirection.front,
      );

      _currentCameraIndex =
          frontCameraIndex >= 0 ? frontCameraIndex : 0;

      final selectedCamera = cameras[_currentCameraIndex];

      controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      debugPrint(
        'CAMERA RESOLUTION: ${controller.value.previewSize}',
      );

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        cameraStatus = 'Memuat MediaPipe...';
      });

      await _holisticChannel.invokeMethod('initializeHolistic');

      isHolisticInitialized = true;

      if (!mounted) {
        await _holisticChannel.invokeMethod('closeHolistic');
        isHolisticInitialized = false;
        await controller.dispose();
        return;
      }

      await _startCameraImageStream(controller);

      if (!mounted) {
        await controller.stopImageStream();
        await _holisticChannel.invokeMethod('closeHolistic');
        isHolisticInitialized = false;
        await controller.dispose();
        return;
      }

      _cameraController = controller;

      setState(() {
        isDetecting = true;
        isLoading = false;
        cameraStatus = 'Kamera dan MediaPipe aktif';
      });
    } catch (e) {
      debugPrint('ERROR START CAMERA: $e');

      if (controller != null) {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }

        await controller.dispose();
      }

      if (isHolisticInitialized) {
        try {
          await _holisticChannel.invokeMethod('closeHolistic');
        } catch (_) {}
      }

      isHolisticInitialized = false;
      _cameraController = null;

      if (!mounted) return;

      setState(() {
        isLoading = false;
        isDetecting = false;
        cameraStatus = 'Gagal mengaktifkan deteksi';
        errorMessage = e.toString();
      });
    }
  }

  // =====================================================
  // SWITCH CAMERA
  // =====================================================

  Future<void> _switchCamera() async {
    if (isLoading ||
        !isDetecting ||
        _availableCameras.length < 2) {
      return;
    }

    final oldController = _cameraController;

    if (oldController == null) return;

    CameraController? newController;

    setState(() {
      isLoading = true;
      cameraStatus = 'Mengganti kamera...';
      errorMessage = null;
    });

    try {
      // 1. Hentikan stream kamera lama.
      if (oldController.value.isStreamingImages) {
        await oldController.stopImageStream();
      }

      // 2. Tunggu pemrosesan frame dan request API selesai.
      while (_isProcessingFrame) {
        await Future.delayed(
          const Duration(milliseconds: 50),
        );
      }

      // 3. Tutup MediaPipe lama.
      if (isHolisticInitialized) {
        await _holisticChannel.invokeMethod('closeHolistic');
        isHolisticInitialized = false;
      }

      // 4. Lepaskan kamera lama.
      _cameraController = null;
      await oldController.dispose();

      // 5. Cari kamera dengan arah lensa berlawanan.
      final currentDirection =
          _availableCameras[_currentCameraIndex].lensDirection;

      final oppositeDirection =
          currentDirection == CameraLensDirection.front
              ? CameraLensDirection.back
              : CameraLensDirection.front;

      int nextIndex = _availableCameras.indexWhere(
        (camera) => camera.lensDirection == oppositeDirection,
      );

      if (nextIndex < 0) {
        nextIndex =
            (_currentCameraIndex + 1) % _availableCameras.length;
      }

      final selectedCamera = _availableCameras[nextIndex];

      // 6. Inisialisasi kamera baru.
      newController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await newController.initialize();

      if (!mounted) {
        await newController.dispose();
        return;
      }

      // 7. Inisialisasi ulang MediaPipe.
      await _holisticChannel.invokeMethod('initializeHolistic');
      isHolisticInitialized = true;

      // 8. Reset data frame dan sequence.
      _rawSequence.clear();

      setState(() {
        frameCount = 0;

        poseLandmarkCount = 0;
        leftHandLandmarkCount = 0;
        rightHandLandmarkCount = 0;

        leftHandDetected = false;
        rightHandDetected = false;

        bodyCoordinates = [];
        leftHandCoordinates = [];
        rightHandCoordinates = [];

        normalizedCoordinates = [];
        modelInput = [];

        _predictionResult = null;
        _isPredicting = false;

        _currentCameraIndex = nextIndex;
      });

      // 9. Jalankan stream kamera baru.
      await _startCameraImageStream(newController);

      if (!mounted) {
        await newController.stopImageStream();
        await _holisticChannel.invokeMethod('closeHolistic');
        isHolisticInitialized = false;
        await newController.dispose();
        return;
      }

      _cameraController = newController;

      final cameraName =
          selectedCamera.lensDirection == CameraLensDirection.front
              ? 'Kamera depan'
              : selectedCamera.lensDirection == CameraLensDirection.back
                  ? 'Kamera belakang'
                  : 'Kamera eksternal';

      setState(() {
        isLoading = false;
        isDetecting = true;
        cameraStatus = '$cameraName aktif';
      });

      debugPrint('Kamera berhasil diganti: $cameraName');
    } catch (e, stackTrace) {
      debugPrint('ERROR SWITCH CAMERA: $e');
      debugPrint('STACK TRACE: $stackTrace');

      if (newController != null) {
        try {
          if (newController.value.isStreamingImages) {
            await newController.stopImageStream();
          }
        } catch (_) {}

        await newController.dispose();
      }

      if (isHolisticInitialized) {
        try {
          await _holisticChannel.invokeMethod('closeHolistic');
        } catch (_) {}

        isHolisticInitialized = false;
      }

      _cameraController = null;

      if (!mounted) return;

      setState(() {
        isLoading = false;
        isDetecting = false;
        cameraStatus = 'Gagal mengganti kamera';
        errorMessage = 'Gagal mengganti kamera: $e';
      });
    }
  }

  // =====================================================
  // STOP CAMERA
  // =====================================================

  Future<void> stopCamera() async {
    final controller = _cameraController;

    setState(() {
      isLoading = true;
      cameraStatus = 'Menghentikan deteksi...';
    });

    try {
      if (controller != null &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      // Tunggu proses frame dan request API yang sedang berjalan.
      while (_isProcessingFrame) {
        await Future.delayed(
          const Duration(milliseconds: 50),
        );
      }

      if (isHolisticInitialized) {
        await _holisticChannel.invokeMethod('closeHolistic');
      }
    } catch (e) {
      debugPrint('ERROR STOP CAMERA: $e');
      errorMessage = 'Gagal menghentikan deteksi: $e';
    }

    isHolisticInitialized = false;
    _cameraController = null;

    await controller?.dispose();

    if (!mounted) return;

    setState(() {
      isDetecting = false;
      isLoading = false;

      leftHandDetected = false;
      rightHandDetected = false;

      poseLandmarkCount = 0;
      leftHandLandmarkCount = 0;
      rightHandLandmarkCount = 0;

      bodyCoordinates = [];
      leftHandCoordinates = [];
      rightHandCoordinates = [];

      _rawSequence.clear();

      normalizedCoordinates = [];
      modelInput = [];

      _isPredicting = false;

      cameraStatus = 'Kamera tidak aktif';
    });
  }

  // =====================================================
  // TOGGLE DETECTION
  // =====================================================

  Future<void> _toggleDetection() async {
    if (isLoading) return;

    if (isDetecting) {
      await stopCamera();
    } else {
      await startCamera();
    }
  }

  // =====================================================
  // DISPOSE
  // =====================================================

  @override
  void dispose() {
    _cameraController?.dispose();
    _apiService.dispose();

    unawaited(_ttsService.stop());

    super.dispose();
  }

  // =====================================================
  // COORDINATE DISPLAY
  // =====================================================

  Widget coordinateSection(
    String title,
    List<double> coordinates,
  ) {
    final bool hasMore = coordinates.length > 8;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 4,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          14,
          0,
          14,
          14,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Color(0xFF145DA0),
          ),
        ),
        subtitle: Text(
          'Total: ${coordinates.length} nilai',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          if (coordinates.isEmpty)
            const Text(
              'Belum ada koordinat',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
            ...List.generate(
              coordinates.length > 8 ? 8 : coordinates.length,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$index : ${coordinates[index].toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
            if (hasMore)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text(
                  'Lihat Semua Koordinat',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF145DA0),
                  ),
                ),
                children: List.generate(
                  coordinates.length - 8,
                  (index) {
                    final actualIndex = index + 8;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$actualIndex : '
                          '${coordinates[actualIndex].toStringAsFixed(5)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  // =====================================================
  // BUILD UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF145DA0),
        foregroundColor: Colors.white,
        title: const Text(
          'IsyaratKu',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Penerjemah Bahasa Isyarat',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF183153),
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Terjemahkan gerakan BISINDO secara langsung.',
                style: TextStyle(color: Colors.black54),
              ),

              const SizedBox(height: 24),

              // CAMERA PREVIEW
              Container(
                width: double.infinity,
                height: 240,
                decoration: BoxDecoration(
                  color: const Color(0xFF183153),
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: controller != null &&
                        controller.value.isInitialized
                    ? CameraPreview(controller)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isLoading)
                            const CircularProgressIndicator(
                              color: Colors.white,
                            )
                          else
                            const Icon(
                              Icons.videocam_outlined,
                              size: 65,
                              color: Colors.white70,
                            ),

                          const SizedBox(height: 12),

                          Text(
                            isLoading
                                ? 'Mengaktifkan kamera'
                                : 'Preview Kamera',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            cameraStatus,
                            style: const TextStyle(
                              color: Colors.white70,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],

              const SizedBox(height: 12),

              // CAMERA SWITCH
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: isDetecting &&
                          !isLoading &&
                          _availableCameras.length > 1
                      ? _switchCamera
                      : null,
                  icon: const Icon(Icons.cameraswitch),
                  label: const Text('Balik Kamera'),
                ),
              ),

              const SizedBox(height: 20),

              // PREDICTION RESULT
              const Text(
                'Hasil Penerjemahan',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF183153),
                ),
              ),

              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Prediksi Kata',
                      style: TextStyle(color: Colors.black54),
                    ),

                    const SizedBox(height: 10),

                    if (_isPredicting) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text(
                        'Sedang memproses prediksi...',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ] else if (_predictionResult != null) ...[
                      Text(
                        _predictionResult!.label.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF145DA0),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Confidence: '
                        '${(_predictionResult!.confidence * 100).toStringAsFixed(2)}%',
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.black54,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        'Class ID: ${_predictionResult!.classId}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // TOMBOL ULANGI SUARA
                      IconButton.filled(
                        tooltip: 'Ulangi pengucapan',
                        onPressed: _ttsReady
                            ? () {
                                _speakPrediction(
                                  _predictionResult!.label,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.volume_up),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF16805D),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ] else ...[
                      const Text(
                        '—',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF145DA0),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        isDetecting
                            ? 'Menunggu sequence 30 frame...'
                            : 'Belum ada hasil prediksi',
                        style: const TextStyle(
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // DETECTION INFORMATION
              DetectionInfoPanel(
                isDetecting: isDetecting,
                cameraStatus: cameraStatus,
                frameCount: frameCount,
                poseLandmarkCount: poseLandmarkCount,
                leftHandLandmarkCount: leftHandLandmarkCount,
                rightHandLandmarkCount: rightHandLandmarkCount,
                leftHandDetected: leftHandDetected,
                rightHandDetected: rightHandDetected,
                bodyCoordinateLength: bodyCoordinates.length,
                leftHandCoordinateLength:
                    leftHandCoordinates.length,
                rightHandCoordinateLength:
                    rightHandCoordinates.length,
                collectedFrames: _rawSequence.length,
                sequenceLength: sequenceLength,
                completedSequences: completedSequences,
                modelInputLength: modelInput.length,
                modelDimension: modelDimension,
                validationAvailable:
                    _lastRawSequence.length == sequenceLength,
              ),

              const SizedBox(height: 20),

              const Text(
                'Data Koordinat Mentah MediaPipe',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Color(0xFF183153),
                ),
              ),

              coordinateSection('BODY RAW', bodyCoordinates),

              coordinateSection(
                'LEFT HAND RAW',
                leftHandCoordinates,
              ),

              coordinateSection(
                'RIGHT HAND RAW',
                rightHandCoordinates,
              ),

              const SizedBox(height: 20),

              const Text(
                'Data Koordinat Normalisasi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Color(0xFF183153),
                ),
              ),

              coordinateSection(
                'MODEL FEATURES - BODY + RIGHT HAND',
                normalizedCoordinates,
              ),

              const SizedBox(height: 16),

              // COPY VALIDATION SUMMARY BUTTON
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed:
                      _lastRawSequence.length == sequenceLength
                          ? _copyValidationData
                          : null,
                  icon: const Icon(Icons.copy),
                  label: const Text(
                    'Salin Ringkasan Validasi',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF145DA0),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // EXPORT JSON BUTTON
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed:
                      _lastRawSequence.length == sequenceLength &&
                              !_isExportingJson
                          ? _exportValidationJson
                          : null,
                  icon: _isExportingJson
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.file_download_outlined,
                        ),
                  label: Text(
                    _isExportingJson
                        ? 'Mengekspor JSON...'
                        : 'Ekspor Data Validasi JSON',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16805D),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),

      // =================================================
      // FLOATING ACTION BUTTON
      // =================================================

      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat,

      floatingActionButton: SizedBox(
        height: 56,
        child: FloatingActionButton.extended(
          heroTag: 'main_detection_button',

          onPressed: isLoading ? null : _toggleDetection,

          backgroundColor: isDetecting
              ? Colors.red.shade700
              : const Color(0xFF145DA0),

          foregroundColor: Colors.white,

          icon: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  isDetecting
                      ? Icons.stop
                      : Icons.play_arrow,
                ),

          label: Text(
            isLoading
                ? 'Memproses...'
                : isDetecting
                    ? 'Stop'
                    : 'Mulai Deteksi',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
