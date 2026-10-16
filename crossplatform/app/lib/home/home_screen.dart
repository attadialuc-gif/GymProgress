import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../calendar/calendar_screen.dart';
import '../progress/history_screens.dart';
import '../ui/charts.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

/// Home (section 9.1): next workout with its recommendations first, then week, streak, volume,
/// records and last session. Every number comes from recorded data (port of HomeView).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// With a plan: the next planned workout (today unless already done or a rest day).
  /// Without a plan: the routine after the last one trained, else the first.
  static ({RoutineTemplate routine, DateTime? plannedDay})? nextRoutine(AppModel model, DateTime now) {
    final routines = model.repository.routines().where((r) => !r.isArchived).toList();
    if (routines.isEmpty) return null;
    final planned = model.consistency.nextPlannedWorkout(now);
    if (planned != null) {
      final r = routines.where((r) => r.id == planned.routineId).firstOrNull;
      if (r != null) return (routine: r, plannedDay: planned.date);
    }
    final completed = model.repository.sessions().where((s) => s.status == SessionStatus.completed).toList();
    final lastId = completed.isEmpty ? null : completed.last.routineId;
    final index = routines.indexWhere((r) => r.id == lastId);
    if (index >= 0) return (routine: routines[(index + 1) % routines.length], plannedDay: null);
    return (routine: routines.first, plannedDay: null);
  }

  String _nextTitle(AppModel model, DateTime? day, DateText dates) {
    if (day == null) return 'Próximo entrenamiento';
    final cal = model.consistency.calendar;
    final today = cal.day(model.now());
    if (day.compareTo(today) == 0) return 'Hoy';
    if (day.compareTo(cal.addDays(1, today)) == 0) return 'Mañana';
    final w = cal.weekday(day);
    return 'Próximo: ${dates.weekdayName(w)} ${dates.dayMonth(day)}';
  }

  static String recordText(LoadFormatter f, PersonalRecord r, DateText dates) {
    final date = dates.dayMonth(r.date);
    return switch (r.kind) {
      RecordKind.maxWeight => 'Peso máximo: ${f.weight(r.value)} · $date',
      RecordKind.maxRepsAtWeight => '${r.value.toInt()} reps con ${f.weight(r.weight)} · $date',
      RecordKind.bestEstimatedOneRepMax => '1RM estimado: ${f.weight(r.value)} (estimación) · $date',
      RecordKind.maxSessionVolume => 'Volumen en una sesión: ${f.weight(r.value)} · $date',
    };
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final theme = Theme.of(context);
    final now = model.now();
    final f = model.loadFormatter;
    final dates = DateText(model.consistency.calendar);
    final open = model.workout.openSession();
    final next = nextRoutine(model, now);
    final previews = next == null
        ? const <(RoutineExercise, Exercise, Recommendation)>[]
        : model.workout.previewRecommendations(next.routine.id, now: now);
    final week = model.consistency.weekSummary(now);
    final streak = model.consistency.streak(now);
    final comparison = model.stats.comparison(const StatsPeriod(StatsPeriodKind.week), now: now);
    final records = model.stats.recentRecords(days: 30, now: now);
    final last = model.history.completedSessionSummaries(limit: 1).firstOrNull;
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);

    return Scaffold(
      appBar: AppBar(title: const Text('Inicio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (open != null) ...[
            GymCard(
              highlighted: true,
              children: [
                Text('Entrenamiento en curso', style: theme.textTheme.titleMedium),
                Text(open.routineNameSnapshot ?? 'Entrenamiento libre', style: TextStyle(color: theme.hintColor)),
                FilledButton(onPressed: () => model.selectTab(AppTab.workout), child: const Text('Retomar')),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (next != null)
            GymCard(
              children: [
                Text(_nextTitle(model, next.plannedDay, dates), style: hint),
                Text(next.routine.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                for (final (item, exercise, rec) in previews)
                  MergeSemantics(
                    key: ValueKey(item.id),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.trending_up, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(exercise.name, style: theme.textTheme.titleSmall),
                              Text(
                                rec.action == RecommendationAction.needsInitialTarget && rec.targetWeight == null
                                    ? 'Sin datos: definí un objetivo inicial'
                                    : '${rec.actionTitle} · ${f.load(rec.targetWeight, rec.measurement, rec.context.loadMode)} × ${rec.amountsText}',
                                style: hint,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (open == null)
                  FilledButton.icon(
                    onPressed: () {
                      if (model.perform(() => model.workout.startSession(next.routine.id, now: model.now())) != null) {
                        model.selectTab(AppTab.workout);
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Comenzar'),
                  ),
              ],
            )
          else
            GymCard(
              children: [
                Text('Empezá creando una rutina', style: theme.textTheme.titleMedium),
                TextButton(onPressed: () => model.selectTab(AppTab.routines), child: const Text('Ir a Rutinas')),
              ],
            ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final weekCard = GymCard(
                children: [
                  Text('Esta semana', style: hint),
                  BigNumber('${week.validSessions}/${week.weeklyGoal}', caption: 'entrenamientos'),
                  LinearProgressIndicator(value: week.goalFraction),
                  if (week.goalMet)
                    const Text('Objetivo cumplido. ¡Bien!', style: TextStyle(color: GymColors.positive))
                  else if (week.planned > 0)
                    Text('${week.planned} días planificados', style: hint),
                ],
              );
              final streakCard = GymCard(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Racha', style: hint)),
                      IconButton(
                        tooltip: 'Cómo se calcula la racha',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.info_outline, size: 18),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Racha'),
                            content: Text(streak.definition),
                            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                          ),
                        ),
                      ),
                    ],
                  ),
                  BigNumber(
                    '${streak.result.current}',
                    caption: streak.result.mode == StreakMode.weeklyPlan ? 'semanas' : 'días',
                  ),
                  Text('Récord: ${streak.result.best}', style: hint),
                ],
              );
              if (c.maxWidth < 360) return Column(spacing: 12, children: [weekCard, streakCard]);
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: weekCard),
                    const SizedBox(width: 12),
                    Expanded(child: streakCard),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          GymCard(
            children: [
              Text('Volumen de la semana', style: hint),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  BigNumber('${comparison.current.effectiveSets}', caption: 'series efectivas'),
                  BigNumber(f.weight(comparison.current.volume), caption: 'volumen externo'),
                ],
              ),
              Text(
                '${comparison.isToDate ? 'Mismos días de la semana anterior' : 'Semana anterior'}: '
                '${comparison.previous.effectiveSets} series · ${f.weight(comparison.previous.volume)}',
                style: hint,
              ),
              _WeeklySetsChart(model: model, now: now),
            ],
          ),
          if (records.isNotEmpty) ...[
            const SizedBox(height: 12),
            GymCard(
              children: [
                Text('Récords recientes', style: hint),
                for (final item in records)
                  MergeSemantics(
                    child: Row(
                      children: [
                        Icon(
                          item.record.isEstimated ? Icons.functions : Icons.emoji_events,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.contextLabel == 'estándar'
                                    ? item.exerciseName
                                    : '${item.exerciseName} · ${item.contextLabel}',
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(recordText(f, item.record, dates), style: hint),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (last != null) ...[
            const SizedBox(height: 12),
            GymCard(
              children: [
                Text('Última sesión', style: hint),
                Text(last.session.routineNameSnapshot ?? 'Entrenamiento libre', style: theme.textTheme.titleMedium),
                Text(
                  '${dates.dayMonth(last.session.startedAt)} ${dates.time(last.session.startedAt)} · ${last.effectiveSets} series',
                  style: hint,
                ),
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(sessionId: last.session.id))),
                  child: const Text('Ver detalle'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CalendarScreen())),
            icon: const Icon(Icons.calendar_month),
            label: const Text('Calendario y plan semanal'),
          ),
        ],
      ),
    );
  }
}

/// Effective sets per week, last 8 weeks (compact progression chart for Home).
class _WeeklySetsChart extends StatelessWidget {
  const _WeeklySetsChart({required this.model, required this.now});
  final AppModel model;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final stats = model.stats;
    final cal = stats.calendar;
    final dates = DateText(cal);
    final start = cal.weekStart(now);
    final weeks = [for (var back = 7; back >= 0; back--) cal.addDays(-7 * back, start)];
    final values = [for (final s in weeks) stats.totals(DateInterval(s, cal.addDays(7, s))).effectiveSets.toDouble()];
    return WeeklyBarChart(
      labels: weeks.map(dates.dayMonth).toList(),
      primary: values,
      semanticLabel: 'Series efectivas por semana, últimas 8 semanas',
    );
  }
}
