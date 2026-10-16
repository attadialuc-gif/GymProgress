import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';

/// One point of a time series (real data only).
class SeriesPoint {
  const SeriesPoint(this.label, this.value, {this.highlighted = true});
  final String label;
  final double value;

  /// false = drawn grey (e.g. atypical session).
  final bool highlighted;
}

String _axis(double v) => GymFormat.number(v, maxFractionDigits: v.abs() < 10 ? 1 : 0);

/// Line chart over sessions (x = session order, labelled by date).
class SeriesLineChart extends StatelessWidget {
  const SeriesLineChart({super.key, required this.points, required this.semanticLabel, this.height = 220});
  final List<SeriesPoint> points;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint = Theme.of(context).hintColor;
    final values = points.map((p) => p.value);
    final minY = values.reduce((a, b) => a < b ? a : b), maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() < 1e-9 ? (maxY.abs() * 0.1 + 1) : (maxY - minY) * 0.15;
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minY: minY - pad,
            maxY: maxY + pad,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: hint.withValues(alpha: 0.15), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(_axis(v), style: TextStyle(fontSize: 10, color: hint)),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 24,
                  getTitlesWidget: (v, meta) {
                    final i = v.round();
                    final step = (points.length / 4).ceil().clamp(1, 1000);
                    if (i < 0 || i >= points.length || (i % step != 0 && i != points.length - 1)) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(points[i].label, style: TextStyle(fontSize: 10, color: hint)),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value)],
                color: scheme.primary,
                barWidth: 2.5,
                dotData: FlDotData(
                  getDotPainter: (spot, _, _, i) => FlDotCirclePainter(
                    radius: 3.5,
                    color: points[i].highlighted ? scheme.primary : Colors.grey,
                    strokeWidth: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bars per week; optional second (stacked) value and a dashed goal line.
class WeeklyBarChart extends StatelessWidget {
  const WeeklyBarChart({
    super.key,
    required this.labels,
    required this.primary,
    this.secondary,
    this.goal,
    required this.semanticLabel,
    this.height = 120,
  });
  final List<String> labels;
  final List<double> primary;
  final List<double>? secondary;
  final double? goal;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint = Theme.of(context).hintColor;
    final light = scheme.primary.withValues(alpha: 0.35);
    var maxY = 1.0;
    for (var i = 0; i < primary.length; i++) {
      final total = primary[i] + (secondary?[i] ?? 0);
      if (total > maxY) maxY = total;
    }
    if (goal != null && goal! > maxY) maxY = goal!;
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            maxY: maxY * 1.15,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            extraLinesData: goal == null
                ? null
                : ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(y: goal!, color: hint, strokeWidth: 1, dashArray: [4, 4]),
                    ],
                  ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(_axis(v), style: TextStyle(fontSize: 10, color: hint)),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, meta) {
                    final i = v.round();
                    if (i < 0 || i >= labels.length || (labels.length > 8 && i.isOdd)) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(labels[i], style: TextStyle(fontSize: 9, color: hint)),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < primary.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: primary[i] + (secondary?[i] ?? 0),
                      width: 12,
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(3),
                      rodStackItems: secondary == null
                          ? const []
                          : [
                              BarChartRodStackItem(0, primary[i], scheme.primary),
                              BarChartRodStackItem(primary[i], primary[i] + secondary![i], light),
                            ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
