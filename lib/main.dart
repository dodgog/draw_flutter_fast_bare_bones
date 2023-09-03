import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:delaunay/delaunay.dart';

void main() {
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

final List<double> ratios = [];

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
  static const double size = 3;
  static const double thinning = 0; //0.2;
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

// State of teh touch tracer
class _TouchTracerState extends State<_TouchTracer> {
  // one empty stroke stored in the past strokes
  final _pastVertices = ValueNotifier<List<Vertices>>([]);

  // Value notifier initialized to be an empty stroke
  final _currentStroke = ValueNotifier<_Stroke?>(null);

  @override
  void dispose() {
    super.dispose();
    _pastVertices.dispose();
    _currentStroke.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _currentStroke.value = const _Stroke([], DefaultDrawStrokeProperties.processAndDrawPressure ? [] : null);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final currentStroke = _currentStroke.value;
    if (currentStroke == null) {
      return;
    }
    // If [processAndDrawPressure] is set to true, pressure value is
    // going to be either the reported physical pressure or 1.0
    _currentStroke.value = currentStroke.copyWithPoint(
        event.localPosition, DefaultDrawStrokeProperties.processAndDrawPressure ? event.pressure : null);
  }

  void _onPointerEnd(PointerUpEvent event) {
    final endedStroke = _currentStroke.value;
    if (endedStroke == null) {
      return;
    }
    /*
    final points = _processStrokeToPoints(endedStroke)!;
    final vertices = _processPointsToTriangles(points);
    _pastVertices.value.add(vertices);
    */
    _pastVertices.value.addAll(_createTriangulationOutlineFromRawStroke(endedStroke));

    ratios.add(_processStrokeToPoints(endedStroke)!.length / endedStroke.points.length);
    //print("${_processStroke(endedStroke)!.length} / ${endedStroke.points.length}");
    //print(ratios.reduce((a, b) => a + b) / ratios.length);

    // set copy to trigger re-draw
    _pastVertices.value = _pastVertices.value.toList();
    _currentStroke.value = null;
  }

  void _onClearStrokes() {
    _pastVertices.value = [];
  }

  void _onUndoLastStroke() {
    // Run twice because the press of the button is a stroke
    // TODO fix
    _pastVertices.value.removeLast();
    _pastVertices.value.removeLast();
    _pastVertices.value = _pastVertices.value.toList();
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
                painter: _PastStrokePainter(listener: _pastVertices),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _CurrentStrokePainter(listener: _currentStroke)),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 100,
                height: 100,
                child: Row(
                  children: [
                    IconButton(onPressed: _onClearStrokes, icon: const Icon(Icons.ac_unit_outlined)),
                    IconButton(onPressed: _onUndoLastStroke, icon: const Icon(Icons.undo)),
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

class _Stroke {
  const _Stroke(this.points, [this.pressures]);
  final List<Offset> points;
  // This list won't be initialized if [processAndDrawPressure] is false.
  final List<double>? pressures;

  // Add a point to the copy of list of points and return this new extended copy
  _Stroke copyWithPoint(Offset point, [double? pressure]) {
    List<double>? newPressures;
    final newPoints = points.toList();
    // If pressures are collected, [processAndDrawPressure] is set true, the list
    // of pressures is not null and the pressure value is not null.
    // The list [pressures] is then always the same length as the list [points].
    if (pressures != null && pressure != null) {
      newPressures = pressures?.toList();
      newPressures?.add(pressure);
    }
    newPoints.add(point);
    return _Stroke(newPoints, newPressures);
  }
}

class _PastStrokePainter extends CustomPainter {
  const _PastStrokePainter({required this.listener}) : super(repaint: listener);
  //final ValueNotifier<List<List<Point>>> listener;
  final ValueNotifier<List<Vertices>> listener;

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

    for (var vertices in verticesList) {
      //_centeredDrawPointsFromList(canvas, pointList, size);
      _drawVerticesOnCanvas(canvas, vertices);
    }
  }
}

class _CurrentStrokePainter extends CustomPainter {
  const _CurrentStrokePainter({required this.listener}) : super(repaint: listener);
  final ValueNotifier<_Stroke?> listener;

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

    List<Point>? outlinePoints = _processStrokeToPoints(stroke);

    //_centeredDrawVerticesFromPointsList(canvas, outlinePoints!, size);
    _drawPointsFromList(canvas, outlinePoints!);
  }
}

List<Point>? _processStrokeToPoints(_Stroke stroke) {
  if (stroke.points.isEmpty) {
    return null;
  }

  final List<Point> pointsList = List.filled(stroke.points.length, const Point(0, 0), growable: false);
  for (var i = 0; i <= stroke.points.length - 1; i++) {
    late final Point point;
    if (stroke.pressures != null) {
      point = Point(stroke.points[i].dx, stroke.points[i].dy, stroke.pressures![i]);
    } else {
      point = Point(stroke.points[i].dx, stroke.points[i].dy);
    }
    pointsList[i] = point;
  }

  //final points = stroke.points.map((e, i) => Point(e.dx, e.dy, ))

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
  //print("${pointsList.length} -> ${outlinePoints.length}");

  return outlinePoints;
}

// Draw an already processed path
void _drawPointsFromList(Canvas canvas, List<Point> pointsList) {
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

void _centeredDrawPointsFromList(Canvas canvas, List<Point> pointsList, Size size) {
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

Vertices _processPointsToTriangles(List<Point> pointsList) {
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

  final vertices = Vertices.raw(VertexMode.triangles, triangleVerticesList);

  return vertices;
}

void _drawVerticesOnCanvas(Canvas canvas, Vertices vertices) {
/*
  final dylib = DynamicLibrary.open("lib/libdelabella.dylib");
  final getTriangleList = dylib.lookupFunction<Pointer<Float> Function(Pointer<Float>, Int32),
      Pointer<Float> Function(Pointer<Float>, int)>('createlistoftriangles');
      */

  //final dylib = DynamicLibrary.open("lib/libdelabella.dylib");

  canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke);
}

void _drawVerticesListOnCanvas(Canvas canvas, List<Vertices> verticesList) {
  for (Vertices vertices in verticesList) {
    canvas.drawVertices(
        vertices,
        BlendMode.srcOver,
        Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.stroke);
  }
}

List<Vertices> _createTriangulationOutlineFromRawStroke(_Stroke stroke) {
  final points = stroke.points;

  //List<Offset> pointsSurrounding = [];
  final positions = Float32List(points.length * 4);

  for (int i = 0; i < points.length; i++) {
    late final Offset vectorAlongPath;
    late Offset vectorPerpendicularToPath;
    if (i == points.length - 1) {
      vectorAlongPath = points[i] - points[i - 1];
    } else {
      vectorAlongPath = points[i + 1] - points[i];
    }
    vectorPerpendicularToPath = Offset(-vectorAlongPath.dy, vectorAlongPath.dx);
    vectorPerpendicularToPath *= DefaultDrawStrokeProperties.size /
        vectorPerpendicularToPath.distance; //pointsSurrounding.add(points[i] + unitVectorPerpendicularToPath);
    //pointsSurrounding.add(points[i] - unitVectorPerpendicularToPath);
    positions[4 * i] = points[i].dx + vectorPerpendicularToPath.dx;
    positions[4 * i + 1] = points[i].dy + vectorPerpendicularToPath.dy;
    positions[4 * i + 2] = points[i].dx - vectorPerpendicularToPath.dx;
    positions[4 * i + 3] = points[i].dy - vectorPerpendicularToPath.dy;
  }

  return [Vertices.raw(VertexMode.triangleStrip, positions)];
}
