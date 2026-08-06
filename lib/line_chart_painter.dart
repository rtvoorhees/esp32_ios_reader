import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class LiveLineChart extends StatelessWidget {
  final List<num> data;
  final Color color;
  final double height;

  const LiveLineChart({
    super.key,
    required this.data,
    required this.color,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (int i = 0; i < data.length; i++)
        FlSpot(i.toDouble(), data[i].toDouble()),
    ];

    double minY = 0;
    double maxY = 1;
    if (data.isNotEmpty) {
      minY = data.reduce((a, b) => a < b ? a : b).toDouble();
      maxY = data.reduce((a, b) => a > b ? a : b).toDouble();
      if (minY == maxY) {
        minY -= 1;
        maxY += 1;
      }
    }

    final maxX = data.isEmpty ? 1.0 : (data.length - 1).toDouble();

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: spots.length < 2
                ? const SizedBox.shrink()
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: maxX,
                      minY: minY,
                      maxY: maxY,
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: false,
                          color: color,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
