
import 'package:flutter/material.dart';

class DetectionInfoPanel extends StatelessWidget {
  final bool isDetecting;
  final String cameraStatus;

  final int frameCount;
  final int poseLandmarkCount;
  final int leftHandLandmarkCount;
  final int rightHandLandmarkCount;

  final bool leftHandDetected;
  final bool rightHandDetected;

  final int bodyCoordinateLength;
  final int leftHandCoordinateLength;
  final int rightHandCoordinateLength;

  final int collectedFrames;
  final int sequenceLength;
  final int completedSequences;
  final int modelInputLength;
  final int modelDimension;

  final bool validationAvailable;

  const DetectionInfoPanel({
    super.key,
    required this.isDetecting,
    required this.cameraStatus,
    required this.frameCount,
    required this.poseLandmarkCount,
    required this.leftHandLandmarkCount,
    required this.rightHandLandmarkCount,
    required this.leftHandDetected,
    required this.rightHandDetected,
    required this.bodyCoordinateLength,
    required this.leftHandCoordinateLength,
    required this.rightHandCoordinateLength,
    required this.collectedFrames,
    required this.sequenceLength,
    required this.completedSequences,
    required this.modelInputLength,
    required this.modelDimension,
    required this.validationAvailable,
  });

  Widget _detectionStatus(String label, bool detected) {
    return Row(
      children: [
        Icon(
          detected ? Icons.check_circle : Icons.cancel,
          color: detected ? Colors.green : Colors.red,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ${detected ? "Terdeteksi" : "Tidak terdeteksi"}',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalRawCoordinates =
        bodyCoordinateLength +
        leftHandCoordinateLength +
        rightHandCoordinateLength;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informasi Deteksi',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF183153),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color: isDetecting ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Status: $cameraStatus'),
              ),
            ],
          ),

          const Divider(height: 24),

          Text('Frame berhasil diproses: $frameCount'),
          const SizedBox(height: 8),

          Text('Pose: $poseLandmarkCount landmark'),
          const SizedBox(height: 8),

          Text('Tangan kiri: $leftHandLandmarkCount landmark'),
          const SizedBox(height: 8),

          Text('Tangan kanan: $rightHandLandmarkCount landmark'),

          const Divider(height: 24),

          const Text(
            'Status Deteksi Tangan',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),

          _detectionStatus('Left hand', leftHandDetected),
          const SizedBox(height: 8),

          _detectionStatus('Right hand', rightHandDetected),

          const Divider(height: 24),

          const Text(
            'Dimensi Koordinat Mentah',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),

          Text('Body: $bodyCoordinateLength / 24'),
          const SizedBox(height: 8),

          Text('Left Hand: $leftHandCoordinateLength / 42'),
          const SizedBox(height: 8),

          Text('Right Hand: $rightHandCoordinateLength / 42'),
          const SizedBox(height: 8),

          Text(
            'Total: $totalRawCoordinates / 108 fitur',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF145DA0),
            ),
          ),

          const Divider(height: 24),

          const Text(
            'Pemrosesan Sequence Model',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'Frame terkumpul: $collectedFrames / $sequenceLength',
          ),
          const SizedBox(height: 8),

          Text('Sequence selesai: $completedSequences'),
          const SizedBox(height: 8),

          const Text('Fitur per frame: 66'),
          const SizedBox(height: 8),

          Text(
            'Dimensi input model: '
            '$modelInputLength / '
            '${sequenceLength * modelDimension}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF145DA0),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Data validasi tersedia: '
            '${validationAvailable ? "Ya" : "Belum"}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: validationAvailable
                  ? Colors.green
                  : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
