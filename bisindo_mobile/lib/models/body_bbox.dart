class BodyBBox {
  final double startX;
  final double endX;
  final double startY;
  final double endY;

  const BodyBBox(
    this.startX,
    this.endX,
    this.startY,
    this.endY,
  );

  double get width => endX - startX;
  double get height => startY - endY;
}