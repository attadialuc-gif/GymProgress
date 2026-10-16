import 'package:flutter/material.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../calendar/calendar_screen.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import 'exercise_progress_screen.dart';
import 'history_screens.dart';
import 'muscle_screens.dart';
import 'records_goals_screen.dart';

/// Definitions shown next to each metric (section 9.4: every indicator explains itself).
class MetricHelp {
  static const effectiveSets =
      'Series efectivas: series de trabajo completadas con peso y repeticiones válidos. El calentamiento no cuenta.';
  static const volume =
      'Volumen externo: suma de peso × repeticiones de las series efectivas. En mancuernas o unilaterales se cuenta el total de ambos lados. Más volumen no implica necesariamente más fuerza o hipertrofia.';
  static const oneRepMax =
      '1RM estimado: cálculo con la fórmula elegida en Perfil a partir de series de hasta el tope de repeticiones configurado. Es una estimación, no una medición.';
  static const indirect =
      'Series indirectas: series de ejercicios donde el músculo es secundario, multiplicadas por el factor de participación (0,5 por defecto). Se muestran aparte de las directas.';
  static const validSession =
      'Entrenamiento válido: finalizado y con al menos el mínimo de series efectivas configurado.';
  static const context =
      'Distintas máquinas o variantes no se comparan entre sí: cada una tiene su propia serie y sus récords. Si son equivalentes, vinculalas desde la pantalla del ejercicio durante un entrenamiento.';
}

class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Qué significa $title',
    visualDensity: VisualDensity.compact,
    icon: const Icon(Icons.help_outline, size: 18),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    ),
  );
}

/// Progress tab (section 9.4). Complements the recommendation system; never needed to know what
/// to do today.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  StatsPeriodKind _kind = StatsPeriodKind.last30Days;
  DateTime? _customStart;
  DateTime? _customEnd;
  String? _routineId;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final theme = Theme.of(context);
    final now = model.now();
    final stats = model.stats;
    final cal = stats.calendar;
    final dates = DateText(cal);
    final start = _customStart ?? cal.addMonths(-1, cal.day(now));
    final end = _customEnd ?? cal.day(now);
    final period = _kind == StatsPeriodKind.custom
        ? StatsPeriod.custom(DateInterval(start.isBefore(end) ? start : end, start.isBefore(end) ? end : start))
        : StatsPeriod(_kind);
    final comparison = stats.comparison(period, now: now, routineId: _routineId);
    final interval = period.interval(now, cal);
    final f = model.loadFormatter;
    final ids = model.history.exerciseIdsWithCompletedHistory();
    final withHistory = model.repository.exercises().where((e) => ids.contains(e.id)).toList();
    final routines = model.repository.routines();

    return Scaffold(
      appBar: AppBar(title: const Text('Progreso')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              spacing: 8,
              children: [
                DropdownButtonFormField<StatsPeriodKind>(
                  isExpanded: true,
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Período'),
                  items: [
                    for (final k in StatsPeriodKind.values)
                      DropdownMenuItem(value: k, child: Text(StatsPeriod(k).label)),
                  ],
                  onChanged: (v) => setState(() => _kind = v!),
                ),
                if (_kind == StatsPeriodKind.custom)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final d = await pickDay(context, cal, initial: start);
                            if (d != null) setState(() => _customStart = d);
                          },
                          child: Text('Desde ${dates.full(start)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final d = await pickDay(context, cal, initial: end);
                            if (d != null) setState(() => _customEnd = d);
                          },
                          child: Text('Hasta ${dates.full(end)}'),
                        ),
                      ),
                    ],
                  ),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _routineId,
                  decoration: const InputDecoration(labelText: 'Rutina'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                    for (final r in routines)
                      DropdownMenuItem<String?>(
                        value: r.id,
                        child: Text(r.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _routineId = v),
                ),
              ],
            ),
          ),
          SectionTitle(
            comparison.isToDate
                ? '${period.label} a la fecha vs. los mismos días del período anterior'
                : '${period.label} vs. período anterior equivalente',
          ),
          _ComparisonRow(
            'Entrenamientos válidos',
            MetricHelp.validSession,
            '${comparison.current.validSessions}',
            '${comparison.previous.validSessions}',
          ),
          _ComparisonRow(
            'Días entrenados',
            null,
            '${comparison.current.trainingDays}',
            '${comparison.previous.trainingDays}',
          ),
          _ComparisonRow(
            'Series efectivas',
            MetricHelp.effectiveSets,
            '${comparison.current.effectiveSets}',
            '${comparison.previous.effectiveSets}',
          ),
          _ComparisonRow(
            'Volumen externo',
            MetricHelp.volume,
            f.weight(comparison.current.volume),
            f.weight(comparison.previous.volume),
          ),
          const SectionTitle('Músculos'),
          ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: const Text('Series por grupo muscular'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MuscleVolumeScreen(interval: interval, title: period.label, routineId: _routineId),
              ),
            ),
          ),
          const SectionTitle('Ejercicios'),
          if (withHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Completá un entrenamiento para ver tu progreso.', style: TextStyle(color: theme.hintColor)),
            ),
          for (final e in withHistory)
            ListTile(
              title: Text(e.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExerciseProgressScreen(exerciseId: e.id, interval: interval, routineId: _routineId),
                ),
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: const Text('Récords y objetivos'),
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RecordsGoalsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Historial de entrenamientos'),
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SessionHistoryScreen())),
          ),
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow(this.title, this.help, this.current, this.previous);
  final String title;
  final String? help;
  final String current;
  final String previous;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: ListTile(
        title: Row(
          children: [
            Flexible(child: Text(title)),
            if (help != null) HelpButton(title: title, text: help!),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              current,
              style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            Text('antes: $previous', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ],
        ),
      ),
    );
  }
}
