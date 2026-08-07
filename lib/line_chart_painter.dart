import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A hand-rolled replacement for fl_chart for live, high-frequency BLE data.
class LiveLineChartPainter extends CustomPainter {
  LiveLineChartPainter({
    required this.data,
    this.lineColor = Colors.cyanAccent,
    this.lineWidth = 2.0,
    this.fillGradient = true,
    this.gridColor,
    this.showGrid = true,
    this.minY,
    this.maxY,
    this.padding = const EdgeInsets.only(left: 4, right: 4, top: 8, bottom: 8),
  });

  final List<num> data;

  final Color lineColor;
  final double lineWidth;
  final bool fillGradient;
  final Color? gridColor;
  final bool showGrid;

  final double? minY;
  final double? maxY;

  final EdgeInsets padding;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final chartRect = Rect.fromLTRB(
      padding.left,
      padding.top,
      size.width - padding.right,
      size.height - padding.bottom,
    );

    if (showGrid) {
      _drawGrid(canvas, chartRect);
    }

    if (data.length < 2) return;

    final samples = data.map((e) => e.toDouble()).toList(growable: false);

    double lo = minY ?? samples.reduce((a, b) => a < b ? a : b);
    double hi = maxY ?? samples.reduce((a, b) => a > b ? a : b);
    if ((hi - lo).abs() < 1e-6) {
      hi += 1;
      lo -= 1;
    }
    final headroom = (hi - lo) * 0.08;
    lo -= headroom;
    hi += headroom;

    final dx = chartRect.width / (samples.length - 1);
    Offset pointAt(int i) {
      final x = chartRect.left + dx * i;
      final normalized = (samples[i] - lo) / (hi - lo);
      final y = chartRect.bottom - normalized * chartRect.height;
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < samples.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }

    if (fillGradient) {
      final fillPath = Path.from(path)
        ..lineTo(chartRect.right, chartRect.bottom)
        ..lineTo(chartRect.left, chartRect.bottom)
        ..close();
      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, chartRect.top),
          Offset(0, chartRect.bottom),
          [lineColor.withValues(alpha: 0.28), lineColor.withValues(alpha: 0.0)],
        );
      canvas.drawPath(fillPath, fillPaint);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.clipRect(rect);
    canvas.drawPath(path, linePaint);

    final tip = pointAt(samples.length - 1);
    canvas.drawCircle(tip, lineWidth * 1.8, Paint()..color = lineColor);
  }

  void _drawGrid(Canvas canvas, Rect chartRect) {
    final paint = Paint()
      ..color = gridColor ?? Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    const hLines = 4;
    for (var i = 0; i <= hLines; i++) {
      final y = chartRect.top + chartRect.height * (i / hLines);
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant LiveLineChartPainter oldDelegate) {
    return true;
  }
}

/// Convenience wrapper that scopes the repaint cost to just this chart.
class LiveLineChart extends StatelessWidget {
  const LiveLineChart({
    super.key,
    required this.data,
    this.lineColor = Colors.cyanAccent,
    this.lineWidth = 2.0,
    this.minY,
    this.maxY,
  });

  final List<num> data;
  final Color lineColor;
  final double lineWidth;
  final double? minY;
  final double? maxY;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: LiveLineChartPainter(
          data: data,
          lineColor: lineColor,
          lineWidth: lineWidth,
          minY: minY,
          maxY: maxY,
        ),
        size: Size.infinite,
      ),
    );
  }
}
