
class DetectionData {
  final List<double> bodyCoordinates;
  final List<double> leftHandCoordinates;
  final List<double> rightHandCoordinates;

  final int poseLandmarkCount;
  final int leftHandLandmarkCount;
  final int rightHandLandmarkCount;

  final bool leftHandDetected;
  final bool rightHandDetected;

  const DetectionData({
    required this.bodyCoordinates,
    required this.leftHandCoordinates,
    required this.rightHandCoordinates,
    required this.poseLandmarkCount,
    required this.leftHandLandmarkCount,
    required this.rightHandLandmarkCount,
    required this.leftHandDetected,
    required this.rightHandDetected,
  });
}
