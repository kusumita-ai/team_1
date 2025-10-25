import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

// ---------------- Main App ----------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RAW Baseline Latency Demo',
      theme: ThemeData.dark(),
      home: const StressTestPage(),
    );
  }
}

// ---------------- Stress Test Page (Baseline) ----------------
class StressTestPage extends StatefulWidget {
  const StressTestPage({super.key});

  @override
  State<StressTestPage> createState() => _StressTestPageState();
}

class _StressTestPageState extends State<StressTestPage>
    with SingleTickerProviderStateMixin {
  final List<Offset> _points = [];
  late AnimationController _animationController;

  // Latency Measurement
  final List<int> _rawLatency = [];
  static const int maxSamples = 8;

  // GPU stress spheres
  final int numSpheres = 200;
  final List<double> rotationSpeeds = [];
  final List<double> phaseOffsets = [];

  // Debounce
  int _lastUpdateTime = 0;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    for (int i = 0; i < numSpheres; i++) {
      rotationSpeeds.add(math.Random().nextDouble() * 3 + 0.5);
      phaseOffsets.add(math.Random().nextDouble() * 2 * math.pi);
    }
  }

  void _recordLatency(int durationMicroseconds) {
    setState(() {
      final durationMs = (durationMicroseconds / 1000).round();
      _rawLatency.insert(0, durationMs);
      if (_rawLatency.length > maxSamples) _rawLatency.removeLast();
    });
  }

  // Simulate extra heavy drawing
  void _simulateHeavyDrawing() {
    for (int i = 0; i < 500; i++) {
      for (int j = 0; j < 500; j++) {
        math.sqrt(i * j * math.Random().nextDouble());
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('RAW Baseline Latency Demo'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // GPU Stress Animation
          Positioned(
            top: 50,
            right: 50,
            child: SizedBox(
              width: 350,
              height: 350,
              child: Extreme3DAnimation(
                controller: _animationController,
                numSpheres: numSpheres,
                rotationSpeeds: rotationSpeeds,
                phaseOffsets: phaseOffsets,
              ),
            ),
          ),

          // Drawing Layer
          GestureDetector(
            onPanUpdate: (details) {
              int now = DateTime.now().millisecondsSinceEpoch;
              if (now - _lastUpdateTime < 16) return; // ~60fps
              _lastUpdateTime = now;

              final stopwatch = Stopwatch()..start();

              RenderBox renderBox = context.findRenderObject() as RenderBox;
              final point = renderBox.globalToLocal(details.globalPosition);

              setState(() {
                _points.add(point);
                if (_points.length > 50) _points.removeAt(0);
              });

              // Simulate heavy drawing in baseline
              _simulateHeavyDrawing();

              WidgetsBinding.instance.addPostFrameCallback((_) {
                stopwatch.stop();
                _recordLatency(stopwatch.elapsedMicroseconds);
              });
            },
            child: RepaintBoundary(
              child: CustomPaint(
                painter: ExtremeDrawingPainter(_points),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // Latency Display
          Positioned(
            bottom: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Latency (ms):',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  ..._rawLatency.map((ms) => Text(
                        '${ms.toString().padLeft(3)} ms',
                        style: const TextStyle(
                            color: Colors.redAccent, fontFamily: 'monospace'),
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Extreme 3D Animation ----------------
class Extreme3DAnimation extends StatelessWidget {
  final AnimationController controller;
  final int numSpheres;
  final List<double> rotationSpeeds;
  final List<double> phaseOffsets;

  const Extreme3DAnimation({
    required this.controller,
    required this.numSpheres,
    required this.rotationSpeeds,
    required this.phaseOffsets,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..setEntry(3, 2, 0.003),
          child: Stack(
            alignment: Alignment.center,
            children: List.generate(numSpheres, (i) {
              double angle =
                  controller.value * 2 * math.pi * rotationSpeeds[i] +
                      phaseOffsets[i];
              double radius = 20 + i % 20 * 8;
              double dx = radius * math.cos(angle);
              double dy = radius * math.sin(angle);
              double size = 15 + (i % 5) * 8;
              return Transform.translate(
                offset: Offset(dx, dy),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: Colors.primaries[i % Colors.primaries.length]
                        .withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

// ---------------- Extreme Drawing Painter ----------------
class ExtremeDrawingPainter extends CustomPainter {
  final List<Offset> points;
  ExtremeDrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != Offset.zero && points[i + 1] != Offset.zero) {
        for (int j = 0; j < 20; j++) {
          final offset1 = points[i] +
              Offset(math.sin(i * 0.1 + j) * 10, math.cos(i * 0.1 + j) * 10);
          final offset2 = points[i + 1] +
              Offset(math.sin(i * 0.1 + j) * 10, math.cos(i * 0.1 + j) * 10);
          paint.color =
              Colors.primaries[j % Colors.primaries.length].withOpacity(0.4);
          canvas.drawLine(offset1, offset2, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(ExtremeDrawingPainter oldDelegate) => true;
}