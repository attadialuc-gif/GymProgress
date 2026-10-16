import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

/// Finished sessions, newest first (port of SessionHistoryView).
class SessionHistoryScreen extends StatelessWidget {
  const SessionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final summaries = model.history.completedSessionSummaries();
    final dates = DateText(model.workout.calendar);
    final f = model.loadFormatter;
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: summaries.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'Sin entrenamientos',
              message: 'Los entrenamientos finalizados aparecen acá.',
            )
          : ListView.separated(
              itemCount: summaries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = summaries[i];
                return ListTile(
                  title: Row(
                    children: [
                      Flexible(child: Text(s.session.routineNameSnapshot ?? 'Entrenamiento libre')),
                      if (s.session.isAtypical) ...[
                        const SizedBox(width: 6),
                        const GymBadge('Atípica', color: GymColors.caution),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${dates.weekdayDayMonth(s.session.startedAt)} · ${formatDuration(s.duration)} · '
                    '${s.effectiveSets} series · ${f.weight(s.volume)}\n${s.exerciseNames.join(', ')}',
                  ),
                  isThreeLine: true,
                  onTap: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(sessionId: s.session.id))),
                );
              },
            ),
    );
  }
}

/// One finished session with its exercises and sets (read only).
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final session = model.repository.session(sessionId);
    if (session == null) return Scaffold(appBar: AppBar());
    final dates = DateText(model.workout.calendar);
    final logs = model.repository.exerciseLogsOfSession(sessionId);
    return Scaffold(
      appBar: AppBar(title: Text(session.routineNameSnapshot ?? 'Entrenamiento libre')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${dates.full(session.startedAt)} · ${dates.time(session.startedAt)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (session.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(session.notes)),
          for (final log in logs) ...[
            const SizedBox(height: 12),
            _LogSummary(log: log, sets: model.repository.setLogs(log.id), decision: model.repository.decision(log.id)),
          ],
        ],
      ),
    );
  }
}

/// History of one exercise (port of ExerciseHistoryView): sets, decision and context per session.
class ExerciseHistoryScreen extends StatelessWidget {
  const ExerciseHistoryScreen({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final exercise = model.repository.exercise(exerciseId);
    final entries = model.history.exerciseHistory(exerciseId);
    final dates = DateText(model.workout.calendar);
    final next = model.workout.previewRecommendation(exerciseId, now: model.now());
    final f = model.loadFormatter;
    // Records of the context currently in use (other machines/variants: Récords y objetivos).
    final currentClass = model.stats.currentContextClass(exerciseId);
    final records = model.stats.records(exerciseId, contextClass: currentClass);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(exercise?.name ?? 'Ejercicio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (next != null)
            GymCard(
              children: [
                Text(
                  'Próxima sesión: ${next.actionTitle}',
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
                ),
                if (next.targetWeight != null)
                  Text(
                    '${f.load(next.targetWeight, next.measurement, next.context.loadMode)} × ${next.amountsText}',
                    style: theme.textTheme.titleLarge,
                  ),
                Text(next.reasonText),
                Text(
                  'Tendencia: ${next.trend.label}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          if (records.maxWeight != null) ...[
            SectionTitle(
              currentClass == null || currentClass.label == 'estándar' ? 'Récords' : 'Récords · ${currentClass.label}',
            ),
            ListTile(
              dense: true,
              title: const Text('Peso máximo (real)'),
              trailing: Text(f.weight(records.maxWeight!.value)),
            ),
            if (records.bestEstimatedOneRepMax != null)
              ListTile(
                dense: true,
                title: const Text('Mejor 1RM estimado'),
                trailing: Text('${f.weight(records.bestEstimatedOneRepMax!.value)} (estimado)'),
              ),
            if (records.maxSessionVolume != null)
              ListTile(
                dense: true,
                title: const Text('Mayor volumen en una sesión'),
                trailing: Text(f.weight(records.maxSessionVolume!.value)),
              ),
          ],
          const SectionTitle('Sesiones'),
          if (entries.isEmpty) const EmptyState(icon: Icons.history, title: 'Sin sesiones registradas'),
          for (final e in entries) ...[
            const SizedBox(height: 12),
            Text(
              '${dates.weekdayDayMonth(e.session.startedAt)} · ${e.session.routineNameSnapshot ?? 'Entrenamiento libre'}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            _LogSummary(log: e.log, sets: e.sets, decision: e.decision),
          ],
        ],
      ),
    );
  }
}

class _LogSummary extends StatelessWidget {
  const _LogSummary({required this.log, required this.sets, required this.decision});
  final ExerciseLog log;
  final List<SetLog> sets;
  final RecommendationDecision? decision;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final f = model.loadFormatter;
    final theme = Theme.of(context);
    final m = log.snapshot.measurement;
    final context2 = [log.equipmentLabel, log.variantLabel].whereType<String>().join(' · ');
    String setText(SetLog s) {
      final amount = m == MeasurementType.duration ? '${s.seconds ?? '–'} s' : '${s.reps ?? '–'}';
      final load = switch (m) {
        MeasurementType.bodyweightReps => f.load(s.performed.netAddedLoad, m, log.snapshot.loadMode),
        _ => s.weight == null ? '—' : f.load(s.weight, m, log.snapshot.loadMode),
      };
      final effort = s.rir != null
          ? ' · RIR ${GymFormat.number(s.rir!)}'
          : (s.rpe != null ? ' · RPE ${GymFormat.number(s.rpe!)}' : '');
      final kind = s.kind == SetKind.warmup ? 'C' : (s.kind == SetKind.dropSet ? 'D' : '');
      final pending = s.status == SetStatus.pending ? ' (no realizada)' : '';
      return '$kind$load × $amount$effort$pending';
    }

    return GymCard(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(child: Text(log.snapshot.name, style: theme.textTheme.titleSmall)),
            if (decision != null) GymBadge(decision!.kind.label, color: GymColors.positive),
            if (log.isAtypical) ...[const SizedBox(width: 6), const GymBadge('Atípico', color: GymColors.caution)],
          ],
        ),
        if (context2.isNotEmpty) Text(context2, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        for (final s in sets) Text(setText(s), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        if (log.notes.isNotEmpty) Text(log.notes, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
