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

// State of teh touch tracer
class _TouchTracerState extends State<_TouchTracer> {
  // one empty stroke stored in the past strokes
  final _pastStrokes = ValueNotifier<List<_Stroke>>([]);

  // Value notifier initialized to be an empty stroke
  final _currentStroke = ValueNotifier<_Stroke?>(null);

  static const receiveAndDrawPressure = true;

  @override
  void dispose() {
    super.dispose();
    _pastStrokes.dispose();
    _currentStroke.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _currentStroke.value = const _Stroke([], receiveAndDrawPressure ? [] : null);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final currentStroke = _currentStroke.value;
    if (currentStroke == null) {
      return;
    }
    _currentStroke.value =
        currentStroke.copyWithPoint(event.localPosition, receiveAndDrawPressure ? event.pressure : null);
  }

  void _onPointerEnd(PointerUpEvent event) {
    final endedStroke = _currentStroke.value;
    if (endedStroke == null) {
      return;
    }
    _pastStrokes.value.add(endedStroke);
    // set copy to trigger re-draw
    _pastStrokes.value = _pastStrokes.value.toList();
    _currentStroke.value = null;
  }

  void _onClearStrokes() {
    _pastStrokes.value = [];
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
              child: IconButton(onPressed: _onClearStrokes, icon: Icon(Icons.ac_unit_outlined)),
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
  final ValueNotifier<List<_Stroke>> listener;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final strokes = listener.value;
    if (strokes.isEmpty) {
      return;
    }

    for (var stroke in strokes) {
      _drawStroke(canvas, stroke);
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

void _drawStroke(Canvas canvas, _Stroke stroke) {
  if (stroke.points.isEmpty) {
    return;
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
    //print("Point x: \t${point.x} y: \t${point.y} p: \t${point.p}");
  }

  /*
  final outlinePoints = getStroke(
    stroke.points.map((point) => Point(point.dx, point.dy)).toList(),
    size: 1,
    simulatePressure: false,

    /// Note: it was found in practice that the stroke changing while writing
    /// felt off. This might be a bug in the library or could be the result of
    /// the current performance. This behavior should be re-evaluated in the future.
    isComplete: true,
  );
  */
  final outlinePoints =
      getStroke(pointsList, size: 3, simulatePressure: false, isComplete: true, smoothing: 1, thinning: 0.5);
  print(
      "lenghts ${(outlinePoints.length / pointsList.length).toStringAsFixed(2)} ${pointsList.length}, ${outlinePoints.length}");

  final path = Path();

  // Otherwise, draw a line that connects each point with a bezier curve segment.
  path.moveTo(outlinePoints[0].x, outlinePoints[0].y);

  for (int i = 1; i < outlinePoints.length - 1; ++i) {
    final p0 = outlinePoints[i];
    final p1 = outlinePoints[i + 1];
    path.quadraticBezierTo(p0.x, p0.y, ((p0.x + p1.x) / 2), ((p0.y + p1.y) / 2));
  }

  canvas.drawPath(path, Paint()..color = Colors.red);
}
