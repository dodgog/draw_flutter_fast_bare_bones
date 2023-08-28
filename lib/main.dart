import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

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
  static const double thinning = 0.2;
  static const double smoothing = 0;
  static const double streamline = 0.5;
  static const double taperStart = 0;
  static const double taperEnd = 0;
  static const bool capStart = true;
  static const bool capEnd = true;
  static const bool simulatePressure = false;

  /// Parameters for flutter's Path drawing
  static const Color color = Color.fromARGB(255, 97, 25, 74);
  static const int powerOfPathCurveDrawnOnCanvas = 1;
}

// State of teh touch tracer
class _TouchTracerState extends State<_TouchTracer> {
  // one empty stroke stored in the past strokes
  final _pastStrokes = ValueNotifier<List<List<Point>>>([]);

  // Value notifier initialized to be an empty stroke
  final _currentStroke = ValueNotifier<_Stroke?>(null);

  @override
  void dispose() {
    super.dispose();
    _pastStrokes.dispose();
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
    _currentStroke.value = currentStroke.copyWithPoint(
        event.localPosition, DefaultDrawStrokeProperties.processAndDrawPressure ? event.pressure : null);
  }

  void _onPointerEnd(PointerUpEvent event) {
    final endedStroke = _currentStroke.value;
    if (endedStroke == null) {
      return;
    }
    _pastStrokes.value.add(_processStroke(endedStroke)!);
    // set copy to trigger re-draw
    _pastStrokes.value = _pastStrokes.value.toList();
    _currentStroke.value = null;
  }

  void _onClearStrokes() {
    _pastStrokes.value = [];
  }

  void _onRedrawPastStrokes() {
    _pastStrokes.value = _pastStrokes.value.toList();
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
                painter: _PastStrokePainter(listener: _pastStrokes),
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
                    IconButton(onPressed: _onRedrawPastStrokes, icon: const Icon(Icons.redo)),
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
  final List<double>? pressures;
  //final List<Point>? canvasPoints;

  // Add a point to the copy of list of points and return this new extended copy
  _Stroke copyWithPoint(Offset point, [double? pressure]) {
    List<double>? newPressures;
    final newPoints = points.toList();
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
  final ValueNotifier<List<List<Point>>> listener;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pointLists = listener.value;
    if (pointLists.isEmpty) {
      return;
    }

    for (var pointList in pointLists) {
      _drawPointsFromList(canvas, pointList);
      //_drawStroke(canvas, stroke);
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

    _drawStroke(canvas, stroke);
  }
}

List<Point>? _processStroke(_Stroke stroke) {
  if (stroke.points.isEmpty) {
    return null;
  }

  final List<Point> pointsList = [];
  for (var i = 0; i <= stroke.points.length - 1; i++) {
    late final Point point;
    if (stroke.pressures != null) {
      point = Point(stroke.points[i].dx, stroke.points[i].dy, stroke.pressures![i]);
    } else {
      point = Point(stroke.points[i].dx, stroke.points[i].dy);
    }
    pointsList.add(point);
  }

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
        if (i >= pointsList.length - 1) break;
        final p1 = pointsList[i + 1];
        final p2 = pointsList[i + 2];
        path.cubicTo(p0.x, p0.y, p1.x, p1.y, p2.x, p2.y);
        break;
      default:
        break;
    }
  }

  canvas.drawPath(path, Paint()..color = DefaultDrawStrokeProperties.color);
}

void _drawStroke(Canvas canvas, _Stroke stroke) {
  List<Point>? outlinePoints = _processStroke(stroke);
  if (outlinePoints == null) return;

  _drawPointsFromList(canvas, outlinePoints);
}
