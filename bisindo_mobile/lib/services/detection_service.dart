
import 'dart:math' as math;

import '../models/body_bbox.dart';

// =====================================================
// HASIL PEMROSESAN SEQUENCE
// =====================================================

class DetectionSequenceResult {
  final List<List<double>> rawSequence;
  final List<List<double>> normalizedSequence;
  final List<List<double>> selectedFeatures;
  final List<double> flattenedInput;

  const DetectionSequenceResult({
    required this.rawSequence,
    required this.normalizedSequence,
    required this.selectedFeatures,
    required this.flattenedInput,
  });
}

// =====================================================
// DETECTION SERVICE
// =====================================================

class DetectionService {
  static const int sequenceLength = 30;

  static const int bodyDimension = 24;
  static const int handDimension = 42;
  static const int rawDimension = 108;
  static const int modelDimension = 66;

  // ===================================================
  // FIT DIMENSION
  // ===================================================

  List<double> fitDimension(
    List<double> coordinates,
    int dimension,
  ) {
    if (coordinates.length == dimension) {
      return List<double>.from(coordinates);
    }

    if (coordinates.length > dimension) {
      return coordinates.sublist(0, dimension);
    }

    return [
      ...coordinates,
      ...List<double>.filled(
        dimension - coordinates.length,
        0.0,
      ),
    ];
  }

  // ===================================================
  // CREATE RAW FRAME (108D)
  // ===================================================

  List<double> createRawFrame(
    List<double> body,
    List<double> leftHand,
    List<double> rightHand,
  ) {
    final bodyData = fitDimension(body, bodyDimension);
    final leftData = fitDimension(leftHand, handDimension);
    final rightData = fitDimension(rightHand, handDimension);

    return [
      ...bodyData,
      ...leftData,
      ...rightData,
    ];
  }

  // ===================================================
  // CHECK VALID LANDMARK
  // ===================================================

  bool _isValidPoint(List<double> points, int index) {
    final x = points[index * 2];
    final y = points[index * 2 + 1];

    return x != 0.0 && y != 0.0;
  }

  // ===================================================
  // GET BODY BOUNDING BOX
  // ===================================================

  BodyBBox? _getBodyBBox(
    List<double> body,
    BodyBBox? previousBBox,
  ) {
    final noseValid = _isValidPoint(body, 0);
    final neckValid = _isValidPoint(body, 1);
    final leftEyeValid = _isValidPoint(body, 3);

    if (!noseValid || !neckValid || !leftEyeValid) {
      return previousBBox;
    }

    final neckX = body[2];
    final noseX = body[0];

    final leftEyeY = body[7];

    double headMetric;

    final rightShoulderValid = _isValidPoint(body, 6);
    final leftShoulderValid = _isValidPoint(body, 7);

    if (rightShoulderValid && leftShoulderValid) {
      final rightShoulderX = body[12];
      final rightShoulderY = body[13];

      final leftShoulderX = body[14];
      final leftShoulderY = body[15];

      final dx = rightShoulderX - leftShoulderX;
      final dy = rightShoulderY - leftShoulderY;

      headMetric = math.sqrt(dx * dx + dy * dy);
    } else {
      final neckY = body[3];
      final noseY = body[1];

      final dx = neckX - noseX;
      final dy = neckY - noseY;

      headMetric = math.sqrt(dx * dx + dy * dy);
    }

    if (!headMetric.isFinite || headMetric <= 1e-8) {
      return previousBBox;
    }

    double startX = neckX - 3.0 * headMetric;
    double endX = neckX + 3.0 * headMetric;

    double startY = leftEyeY + headMetric;
    double endY = startY - 6.0 * headMetric;

    startX = math.max(0.0, startX);
    endX = math.max(0.0, endX);
    startY = math.max(0.0, startY);
    endY = math.max(0.0, endY);

    final bbox = BodyBBox(
      startX,
      endX,
      startY,
      endY,
    );

    if (bbox.width <= 1e-8 || bbox.height <= 1e-8) {
      return previousBBox;
    }

    return bbox;
  }

  // ===================================================
  // NORMALIZE BODY
  // ===================================================

  List<double> _normalizeBody(
    List<double> body,
    BodyBBox? bbox,
  ) {
    if (bbox == null) {
      return List<double>.filled(bodyDimension, 0.0);
    }

    final output = <double>[];

    for (int i = 0; i < bodyDimension; i += 2) {
      final x = body[i];
      final y = body[i + 1];

      if (x == 0.0) {
        output.add(0.0);
        output.add(0.0);
        continue;
      }

      final normalizedX = (x - bbox.startX) / bbox.width;
      final normalizedY = (y - bbox.endY) / bbox.height;

      output.add(normalizedX);
      output.add(normalizedY);
    }

    return output;
  }

  // ===================================================
  // NORMALIZE HAND BODY RELATIVE
  // ===================================================

  List<double> _normalizeHand(
    List<double> hand,
    BodyBBox? bbox,
  ) {
    if (bbox == null ||
        bbox.width <= 1e-8 ||
        bbox.height <= 1e-8) {
      return List<double>.filled(handDimension, 0.0);
    }

    final output = <double>[];

    for (int i = 0; i < handDimension; i += 2) {
      final x = hand[i];
      final y = hand[i + 1];

      if (x == 0.0 || y == 0.0) {
        output.add(0.0);
        output.add(0.0);
        continue;
      }

      final normalizedX = (x - bbox.startX) / bbox.width;
      final normalizedY = (y - bbox.endY) / bbox.height;

      output.add(normalizedX);
      output.add(normalizedY);
    }

    return output;
  }

  // ===================================================
  // NORMALIZE SEQUENCE BODY RELATIVE
  // ===================================================

  List<List<double>> normalizeSequenceBodyRelative(
    List<List<double>> sequence,
  ) {
    BodyBBox? previousBBox;

    final normalizedSequence = <List<double>>[];

    for (final frame in sequence) {
      if (frame.length != rawDimension) {
        throw ArgumentError(
          'Dimensi frame harus $rawDimension, '
          'ditemukan ${frame.length}.',
        );
      }

      final body = frame.sublist(0, 24);
      final leftHand = frame.sublist(24, 66);
      final rightHand = frame.sublist(66, 108);

      final currentBBox = _getBodyBBox(
        body,
        previousBBox,
      );

      if (currentBBox != null) {
        previousBBox = currentBBox;
      }

      final normalizedBody = _normalizeBody(
        body,
        currentBBox,
      );

      final normalizedLeftHand = _normalizeHand(
        leftHand,
        currentBBox,
      );

      final normalizedRightHand = _normalizeHand(
        rightHand,
        currentBBox,
      );

      normalizedSequence.add([
        ...normalizedBody,
        ...normalizedLeftHand,
        ...normalizedRightHand,
      ]);
    }

    return normalizedSequence;
  }

  // ===================================================
  // SELECT MODEL FEATURES
  // Body 24D + Right Hand 42D = 66D
  // ===================================================

  List<List<double>> selectModelFeatures(
    List<List<double>> normalizedSequence,
  ) {
    return normalizedSequence.map((frame) {
      if (frame.length != rawDimension) {
        throw ArgumentError(
          'Dimensi frame normalisasi harus $rawDimension.',
        );
      }

      return [
        ...frame.sublist(0, 24),
        ...frame.sublist(66, 108),
      ];
    }).toList();
  }

  // ===================================================
  // PROCESS COMPLETE SEQUENCE
  // ===================================================

  DetectionSequenceResult processSequence(
    List<List<double>> sequence,
  ) {
    if (sequence.length != sequenceLength) {
      throw ArgumentError(
        'Sequence harus berisi tepat $sequenceLength frame, '
        'ditemukan ${sequence.length}.',
      );
    }

    final rawCopy = sequence
        .map((frame) => List<double>.from(frame))
        .toList();

    final normalizedSequence =
        normalizeSequenceBodyRelative(rawCopy);

    final selectedFeatures =
        selectModelFeatures(normalizedSequence);

    final flattenedInput = selectedFeatures
        .expand((frame) => frame)
        .toList();

    if (selectedFeatures.any(
      (frame) => frame.length != modelDimension,
    )) {
      throw StateError(
        'Dimensi fitur model tidak sesuai.',
      );
    }

    if (flattenedInput.length != sequenceLength * modelDimension) {
      throw StateError(
        'Dimensi flattened input tidak sesuai.',
      );
    }

    return DetectionSequenceResult(
      rawSequence: rawCopy,
      normalizedSequence: normalizedSequence,
      selectedFeatures: selectedFeatures,
      flattenedInput: flattenedInput,
    );
  }
}
