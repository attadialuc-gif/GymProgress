import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../ui/charts.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import 'history_screens.dart';
import 'progress_screen.dart';

enum _Metric { load, amount, oneRepMax, volume }

/// Charts of one exercise in one comparability class: load, reps/seconds, estimated 1RM and
/// volume per session (real data only). Different machines/variants are never joined.
class ExerciseProgressScreen extends StatefulWidget {
  const ExerciseProgressScreen({super.key, required this.exerciseId, required this.interval, this.routineId});
  final String exerciseId;
  final DateInterval interval;
  final String? routineId;

  @override
  State<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

class _ExerciseProgressScreenState extends State<ExerciseProgressScreen> {
  _Metric _metric = _Metric.load;
  String? _classId;

  String _title(_Metric m, MeasurementType measurement) => switch (m) {
    _Metric.load => measurement == MeasurementType.bodyweightReps ? 'Lastre' : 'Peso',
    _Metric.amount => measurement == MeasurementType.duration ? 'Segundos' : 'Repeticiones',
    _Metric.oneRepMax => '1RM estimado',
    _Metric.volume => measurement == MeasurementType.duration ? 'Tiempo' : 'Volumen',
  };

  String _footer(MeasurementType measurement) => switch (_metric) {
    _Metric.oneRepMax => MetricHelp.oneRepMax,
    _Metric.volume =>
      measurement == MeasurementType.duration ? 'Tiempo total bajo carga de las series efectivas.' : MetricHelp.volume,
    _Metric.load =>
      measurement == MeasurementType.bodyweightReps
          ? 'Carga neta sobre el peso corporal: lastre (+) o asistencia (−). Puntos grises: sesiones atípicas.'
          : 'Peso de trabajo: el más usado en las series efectivas de la sesión. Puntos grises: sesiones atípicas (no cuentan para tendencias).',
    _Metric.amount =>
      measurement == MeasurementType.duration
          ? 'Segundos totales en las series de trabajo de cada sesión.'
          : 'Repeticiones totales en las series de trabajo de cada sesión.',
  };

  double? _value(ExercisePoint p, LoadFormatter f) => switch (_metric) {
    _Metric.load => f.value(p.workingLoad),
    _Metric.amount => p.totalAmount.toDouble(),
    _Metric.oneRepMax => p.estimatedOneRepMax == null ? null : f.value(p.estimatedOneRepMax!),
    _Metric.volume => p.measurement == MeasurementType.duration ? p.totalAmount.toDouble() : f.value(p.volume),
  };

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final theme = Theme.of(context);
    final stats = model.stats;
    final f = model.loadFormatter;
    final dates = DateText(stats.calendar);
    final classes = stats.contextClasses(widget.exerciseId);
    final selected = classes.where((c) => c.id == _classId).firstOrNull ?? classes.firstOrNull;
    final points = stats.exerciseSeries(
      widget.exerciseId,
      interval: widget.interval,
      contextClass: selected,
      routineId: widget.routineId,
    );
    final measurement =
        points.firstOrNull?.measurement ??
        model.repository.exercise(widget.exerciseId)?.measurement ??
        MeasurementType.weightReps;
    final metrics = _Metric.values
        .where((m) => m != _Metric.oneRepMax || measurement == MeasurementType.weightReps)
        .toList();
    if (!metrics.contains(_metric)) _metric = _Metric.load;
    final values = [
      for (final p in points)
        if (_value(p, f) case final v?) (p, v),
    ];
    final hint = TextStyle(color: theme.hintColor, fontSize: 12);

    return Scaffold(
      appBar: AppBar(title: Text(model.repository.exercise(widget.exerciseId)?.name ?? 'Ejercicio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (classes.length > 1) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: selected?.id,
              decoration: const InputDecoration(labelText: 'Máquina / variante'),
              items: [
                for (final c in classes)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _classId = v),
            ),
            Row(
              children: [
                Expanded(child: Text('Cada contexto tiene su propio gráfico y récords.', style: hint)),
                const HelpButton(title: 'Contextos', text: MetricHelp.context),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SegmentedButton<_Metric>(
            showSelectedIcon: false,
            segments: [
              for (final m in metrics)
                ButtonSegment(
                  value: m,
                  label: Text(_title(m, measurement), style: const TextStyle(fontSize: 12)),
                ),
            ],
            selected: {_metric},
            onSelectionChanged: (v) => setState(() => _metric = v.first),
          ),
          const SizedBox(height: 12),
          if (values.isEmpty)
            Text(
              points.isEmpty
                  ? 'Sin sesiones en este período.'
                  : 'Sin datos para esta métrica (por ejemplo, ninguna serie dentro del tope de repeticiones del 1RM).',
              style: TextStyle(color: theme.hintColor),
            )
          else
            SeriesLineChart(
              points: [for (final (p, v) in values) SeriesPoint(dates.dayMonth(p.date), v, highlighted: !p.isAtypical)],
              semanticLabel: '${_title(_metric, measurement)} por sesión',
            ),
          const SizedBox(height: 8),
          Text(_footer(measurement), style: hint),
          const SectionTitle('Sesiones'),
          for (final p in points.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Flexible(child: Text(dates.full(p.date))),
                  if (p.isAtypical) ...[const SizedBox(width: 6), const GymBadge('Atípica', color: Colors.grey)],
                ],
              ),
              trailing: Text(
                '${f.load(p.workingLoad, p.measurement, p.loadMode)} · ${p.measurement == MeasurementType.duration ? '${p.totalAmount} s' : '${p.totalAmount} reps'}',
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => ExerciseHistoryScreen(exerciseId: widget.exerciseId))),
            child: const Text('Historial completo y recomendación'),
          ),
        ],
      ),
    );
  }
}
