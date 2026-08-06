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
    // TEMPORARY DIAGNOSTIC: plain fixed-size box, no chart library involved.
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'points: ${data.length}',
            style: TextStyle(color: color),
          ),
        ),
      ),
    );
  }
}
