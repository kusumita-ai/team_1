import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: LatencyCompareDemo()));

class LatencyCompareDemo extends StatefulWidget {
  const LatencyCompareDemo({super.key});
  @override
  State<LatencyCompareDemo> createState() => _LatencyCompareDemoState();
}

class _LatencyCompareDemoState extends State<LatencyCompareDemo>
    with SingleTickerProviderStateMixin {
  final List<Offset> points = [];
  final List<int> latencies = [];
  int lastTime = 0;
  static const int maxPts = 300;
  bool useFastPath = false;

  Isolate? worker;
  SendPort? workerPort;
  final receivePort = ReceivePort();
  late final FastClassifier classifier;

  // ---------------- 3D spheres ----------------
  late final AnimationController sphereController;
  int numSpheres = 50;
  final List<double> rotationSpeeds = [];
  final List<double> phaseOffsets = [];

  @override
  void initState() {
    super.initState();
    classifier = FastClassifier();
    _spawnWorker();

    // sphere animation
    sphereController =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat();
    for (int i = 0; i < 400; i++) {
      rotationSpeeds.add(math.Random(i).nextDouble() * 3 + 0.5);
      phaseOffsets.add(math.Random(i + 1).nextDouble() * 2 * math.pi);
    }
  }

  @override
  void dispose() {
    worker?.kill(priority: Isolate.immediate);
    receivePort.close();
    sphereController.dispose();
    super.dispose();
  }

  void _spawnWorker() async {
    final ready = Completer<SendPort>();
    final isolate = await Isolate.spawn(_workerEntry, receivePort.sendPort);
    worker = isolate;
    receivePort.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        workerPort = msg;
      }
    });
    workerPort = await ready.future;
  }

  void _onPointer(PointerEvent e) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastTime < 16) return;
    lastTime = now;

    final sw = Stopwatch()..start();
    setState(() {
      points.add(e.localPosition);
      if (points.length > maxPts) points.removeAt(0);
    });

    // CPU load scaling by number of spheres
    final cpuLoad = numSpheres; // each sphere adds extra work
    if (!useFastPath) {
      _heavyWorkBlocking(cpuLoad); // baseline
    } else {
      final type = classifier.classify(e);
      if (type == GestureType.heavy) {
        // send to worker isolate
        workerPort?.send([e.localPosition.dx, e.localPosition.dy]);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      latencies.insert(0, ms);
      if (latencies.length > 60) latencies.removeLast();
      setState(() {});
    });
  }

  // CPU heavy work tuned with sphere scaling
  void _heavyWorkBlocking(int multiplier) {
    final sw = Stopwatch()..start();
    double acc = 0;
    while (sw.elapsedMilliseconds < 10 + multiplier ~/ 2) {
      for (int i = 0; i < 4000; i++) {
        acc += math.sqrt(i * 1.2345);
      }
    }
    if (acc.isNaN) debugPrint('');
  }

  int _percentile(List<int> a, double p) {
    if (a.isEmpty) return 0;
    final sorted = List<int>.from(a)..sort();
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...latencies]..sort();
    final p50 = _percentile(sorted, 0.50);
    final p55 = _percentile(sorted, 0.55);
    final p95 = _percentile(sorted, 0.95);
    final p99 = _percentile(sorted, 0.99);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(useFastPath
            ? '⚡ FAST PATH — UI + Worker'
            : '🧱 BASELINE — Heavy on UI'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              latencies.clear();
              useFastPath = !useFastPath;
            }),
            child: Text(
              useFastPath ? 'Switch to Baseline' : 'Switch to Fast Path',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Listener(
            onPointerMove: _onPointer,
            child: CustomPaint(
              painter: DrawPainter(points),
              child: Container(color: Colors.transparent),
            ),
          ),

          // ---------------- 3D spheres overlay ----------------
          Positioned(
            top: 40,
            right: 20,
            child: SizedBox(
              width: 300,
              height: 300,
              child: AnimatedBuilder(
                animation: sphereController,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: List.generate(numSpheres, (i) {
                      final rs = rotationSpeeds[i % rotationSpeeds.length];
                      final ph = phaseOffsets[i % phaseOffsets.length];
                      double angle =
                          sphereController.value * 2 * math.pi * rs + ph;
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
                                .withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),

          // ---------------- spheres slider ----------------
          Positioned(
            top: 350,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Text('Number of spheres: $numSpheres',
                    style: const TextStyle(color: Colors.white)),
                Slider(
                  value: numSpheres.toDouble(),
                  min: 0,
                  max: 400,
                  divisions: 40,
                  onChanged: (v) => setState(() => numSpheres = v.round()),
                  activeColor: Colors.blueAccent,
                  inactiveColor: Colors.white24,
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              width: 340,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(fontFamily: 'monospace'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Latency p50/p55/p95/p99: $p50 / $p55 / $p95 / $p99 ms'),
                    const SizedBox(height: 6),
                    Text('Last samples: ${latencies.take(15).join(', ')}'),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () => setState(() => latencies.clear()),
                      child: const Text('Clear Samples'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- FastClassifier ----------------
enum GestureType { light, heavy }

class FastClassifier {
  Offset? lastPos;
  int lastTime = 0;

  GestureType classify(PointerEvent e) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dt = (now - lastTime).clamp(1, 1000);
    lastTime = now;

    if (lastPos == null) {
      lastPos = e.localPosition;
      return GestureType.light;
    }

    final dx = (e.localPosition - lastPos!).distance;
    lastPos = e.localPosition;

    final velocity = dx / dt;
    final isHeavy = velocity < 0.05 || dx > 40;
    return isHeavy ? GestureType.heavy : GestureType.light;
  }
}

// ---------------- Worker isolate ----------------
void _workerEntry(SendPort sendPort) {
  final port = ReceivePort();
  sendPort.send(port.sendPort);
  port.listen((msg) {
    final dx = msg[0] as double;
    final dy = msg[1] as double;
    // simulate heavy compute
    double acc = 0;
    for (int k = 0; k < 600000; k++) {
      acc += math.sqrt(k + dx + dy);
    }
    sendPort.send(acc);
  });
}

// ---------------- Painter ----------------
class DrawPainter extends CustomPainter {
  final List<Offset> pts;
  DrawPainter(this.pts);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.blueAccent.withOpacity(0.5)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (int i = 1; i < pts.length; i++) {
      c.drawLine(pts[i - 1], pts[i], p);
    }
  }

  @override
  bool shouldRepaint(covariant DrawPainter oldDelegate) => true;
}