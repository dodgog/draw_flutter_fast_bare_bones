import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:fontrender/fontrender.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:delaunay/delaunay.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

void main() async {
  Font.loadSharedLibrary(await ensureFontLibraryExtracted());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const Scaffold(body: _TouchTracer()),
    );
  }
}

// Home of the project
class _TouchTracer extends StatefulWidget {
  const _TouchTracer();

  @override
  State<_TouchTracer> createState() => _TouchTracerState();
}

class DefaultDrawStrokeProperties {
  /// Parameters for event proceccing
  static const bool processAndDrawPressure = true;

  /// Parameters for the perfect_freehand stroke processing
  static const double size = 10;
  static const double thinning = 0.8; //0.2;
  static const double smoothing = 0.8; //0;
  static const double streamline = 0.5;
  static const double taperStart = 0;
  static const double taperEnd = 0;
  static const bool capStart = true;
  static const bool capEnd = true;
  static const bool simulatePressure = false;

  /// Parameters for flutter's Path drawing
  static const Color color = Color.fromARGB(255, 97, 25, 74);
  static const int powerOfPathCurveDrawnOnCanvas = 1;

  static const bool drawDelaunay = true;
}

// State of the touch tracer
class _TouchTracerState extends State<_TouchTracer> {
  // Initialize an empty list of points
  final _pastTrianglePoints = ValueNotifier<Float32List>(Float32List(0));

  // Value notifier initialized to be an empty stroke
  final _currentStroke = ValueNotifier<List<Point>?>(null);

  @override
  void dispose() {
    super.dispose();
    _currentStroke.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _currentStroke.value = [];
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_currentStroke.value == null) {
      return;
    }
    // If [processAndDrawPressure] is set to true, pressure value is
    // going to be the reported physical pressure, else 1.0
    _currentStroke.value!.add(Point(event.localPosition.dx, event.localPosition.dy,
        DefaultDrawStrokeProperties.processAndDrawPressure ? event.pressure : 1.0));
    setState(() {
      _currentStroke.value = _currentStroke.value!.toList();
    });
  }

  void _onPointerEnd(PointerUpEvent event) {
    final endedStroke = _currentStroke.value;
    if (endedStroke == null || endedStroke.isEmpty) {
      return;
    }

    final List<Point> outlinePoints = _getOutlineWithPerfectFreehand(endedStroke);
    _pastTrianglePoints.value =
        joinFloat32Lists(_pastTrianglePoints.value, _processPointsToLibtess2Triangles(outlinePoints));

    /*
    _pastTrianglePoints.value = joinFloat32Lists(
        _pastTrianglePoints.value, _createThickTriangulationStripFloat32ListFromRawStroke(endedStroke));
      */

    _currentStroke.value = null;
  }

  void _onClearStrokes() {
    _pastTrianglePoints.value = Float32List(0);
  }

  void _onUndoLastStroke() {
    // Run twice because the press of the button is a stroke
    _pastTrianglePoints.value.removeLast();
    _pastTrianglePoints.value.removeLast();
  }

  void _onPrintNumberOfPoints() {
    print(_pastTrianglePoints.value.length);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PastStrokePainter(listener: _pastTrianglePoints),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _CurrentStrokePainter(listener: _currentStroke)),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: IntrinsicWidth(
                child: Row(
                  children: [
                    IconButton(onPressed: _onClearStrokes, icon: const Icon(Icons.ac_unit_outlined)),
                    IconButton(onPressed: _onUndoLastStroke, icon: const Icon(Icons.undo)),
                    IconButton(onPressed: _onPrintNumberOfPoints, icon: const Icon(Icons.turn_sharp_left)),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _PastStrokePainter extends CustomPainter {
  const _PastStrokePainter({required this.listener}) : super(repaint: listener);
  final ValueNotifier<Float32List> listener;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final verticesList = listener.value;
    if (verticesList.isEmpty) {
      return;
    }

    _drawVerticesOnCanvas(canvas, Vertices.raw(VertexMode.triangles, verticesList));
  }
}

class _CurrentStrokePainter extends CustomPainter {
  const _CurrentStrokePainter({required this.listener}) : super(repaint: listener);
  final ValueNotifier<List<Point>?> listener;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = listener.value;
    if (stroke == null) {
      return;
    }

    List<Point> outlinePoints = _getOutlineWithPerfectFreehand(stroke);

    _drawPointsAsPath(canvas, outlinePoints);
    //_drawEnlargedStrokeOutlineWithBox(canvas, outlinePoints, size);
  }
}

List<Point> _getOutlineWithPerfectFreehand(List<Point> pointsList) {
  final outlinePoints = getStroke(
    pointsList,
    size: DefaultDrawStrokeProperties.size,
    thinning: DefaultDrawStrokeProperties.thinning,
    smoothing: DefaultDrawStrokeProperties.smoothing,
    streamline: DefaultDrawStrokeProperties.streamline,
    taperStart: DefaultDrawStrokeProperties.taperStart,
    taperEnd: DefaultDrawStrokeProperties.taperEnd,
    capStart: DefaultDrawStrokeProperties.capStart,
    capEnd: DefaultDrawStrokeProperties.capEnd,
    simulatePressure: DefaultDrawStrokeProperties.simulatePressure,
  );
  return outlinePoints;
}

// Draw an already processed path
void _drawPointsAsPath(Canvas canvas, List<Point> pointsList) {
  final path = Path();

  // Otherwise, draw a line that connects each point with a bezier curve segment.
  path.moveTo(pointsList[0].x, pointsList[0].y);

  for (int i = 1; i < pointsList.length - 1; i++) {
    final p0 = pointsList[i];
    switch (DefaultDrawStrokeProperties.powerOfPathCurveDrawnOnCanvas) {
      case 1:
        path.lineTo(p0.x, p0.y);
        break;
      case 2:
        final p1 = pointsList[i + 1];
        path.quadraticBezierTo(p0.x, p0.y, ((p0.x + p1.x) / 2), ((p0.y + p1.y) / 2));
        break;
      case 3:
        if (i >= pointsList.length - 2) break;
        final p1 = pointsList[i + 1];
        final p2 = pointsList[i + 2];
        path.cubicTo(p0.x, p0.y, p1.x, p1.y, p2.x, p2.y);
        break;
      default:
        break;
    }
  }
  canvas.drawPath(
      path,
      Paint()
        ..color = DefaultDrawStrokeProperties.color
        ..style = PaintingStyle.fill
        ..strokeWidth = 1);
}

void _drawEnlargedStrokeOutlineWithBox(Canvas canvas, List<Point> pointsList, Size size) {
  Path path = Path();

  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;

  for (int i = 1; i < pointsList.length - 1; i++) {
    final p0 = pointsList[i];

    if (p0.x < minX) minX = p0.x;
    if (p0.x > maxX) maxX = p0.x;
    if (p0.y < minY) minY = p0.y;
    if (p0.y > maxY) maxY = p0.y;
  }

  double frameThickness = 3;

  double height = maxY - minY + 2 * frameThickness;
  double width = maxX - minX + 2 * frameThickness;

  Offset firstPoint = Offset(pointsList[0].x, pointsList[0].y);
  Offset initialShift = Offset(-minX + frameThickness, -minY + frameThickness);
  double scaleVertical = height / (size.height);
  double scaleHorizontal = width / (size.width);
  double scale = max(scaleHorizontal, scaleVertical);

  Offset p0 = (firstPoint + initialShift) / scale;
  Offset pfirst = p0;
  Offset p0last = p0;
  path.moveTo(p0.dx, p0.dy);

  final gradient = LinearGradient(
    colors: generateColors(pointsList.length),
  );
  for (int i = 1; i < pointsList.length - 1; i++) {
    p0last = p0;
    p0 = Offset(pointsList[i].x, pointsList[i].y);
    p0 = (p0 + initialShift) / scale;
    path.lineTo(p0.dx, p0.dy);

    canvas.drawLine(p0last, p0, Paint()..color = gradient.colors[i]);
  }
  canvas.drawLine(p0last, pfirst, Paint()..color = gradient.colors.last);

  canvas.drawRect(
      Rect.fromPoints((Offset(minX, minY) + initialShift) / scale, (Offset(maxX, maxY) + initialShift) / scale),
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
}

List<Color> generateColors(int numberOfColors) {
  const Color startColor = Colors.red;
  const Color endColor = Colors.blue;

  return List.generate(numberOfColors, (index) {
    final t = index / (numberOfColors - 1);
    return Color.lerp(startColor, endColor, t)!;
  });
}

Float32List _processPointsToDelaunayTriangles(List<Point> pointsList) {
  Float32List verticesList = Float32List(pointsList.length * 2);
  for (int i = 0; i < pointsList.length; i++) {
    verticesList[2 * i] = pointsList[i].x;
    verticesList[2 * i + 1] = pointsList[i].y;
  }
  Delaunay delaunay = Delaunay(verticesList);
  delaunay.update();

  Float32List triangleVerticesList = Float32List(delaunay.triangles.length * 2 * 3);
  for (int i = 0; i < delaunay.triangles.length; i += 1) {
    int triangleVertexIndex = delaunay.triangles[i];

    double ax = delaunay.coords[2 * triangleVertexIndex];
    double ay = delaunay.coords[2 * triangleVertexIndex + 1];
    triangleVerticesList[2 * i] = ax;
    triangleVerticesList[2 * i + 1] = ay;
  }

  return triangleVerticesList;
}

Float32List _processPointsToLibtess2Triangles(List<Point> pointsList) {
  final tess = Tess();

  final vectorPoints = pointsList.map((e) => Vector2(e.x, e.y)).toList();
  tess.addContour(vectorPoints);

  final result = tess.tessellate();
  final trinagles = result.triangles();

  final Float32List verticesList = Float32List(trinagles.length * 2);

  for (int i = 0; i < trinagles.length; i++) {
    verticesList[2 * i] = trinagles[i].x;
    verticesList[2 * i + 1] = trinagles[i].y;
  }
  return verticesList;
}

void _drawVerticesOnCanvas(Canvas canvas, Vertices vertices) {
  canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke // style doesn't matter for vertices
      );
}

Float32List _createThickTriangulationStripFloat32ListFromRawStroke(List<Point> pointsWithPressure) {
  final points = pointsWithPressure.map((e) => Offset(e.x, e.y)).toList();
  final positions = Float32List(points.length * 2 * 2);

  for (int i = 0; i < points.length; i++) {
    late final Offset vectorAlongPath;
    late Offset vectorPerpendicularToPath;
    if (i == points.length - 1) {
      vectorAlongPath = points[i] - points[i - 1];
    } else {
      vectorAlongPath = points[i + 1] - points[i];
    }
    vectorPerpendicularToPath = Offset(-vectorAlongPath.dy, vectorAlongPath.dx);
    vectorPerpendicularToPath *= DefaultDrawStrokeProperties.size / vectorPerpendicularToPath.distance;
    positions[4 * i] = points[i].dx + vectorPerpendicularToPath.dx;
    positions[4 * i + 1] = points[i].dy + vectorPerpendicularToPath.dy;
    positions[4 * i + 2] = points[i].dx - vectorPerpendicularToPath.dx;
    positions[4 * i + 3] = points[i].dy - vectorPerpendicularToPath.dy;
  }
  return positions;
}

Float32List joinFloat32Lists(Float32List list1, Float32List list2) {
  Float32List concatenatedList = Float32List(list1.length + list2.length);
  concatenatedList.setAll(0, list1);
  concatenatedList.setAll(list1.length, list2);
  return concatenatedList;
}
