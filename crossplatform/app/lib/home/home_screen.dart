import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';

import '../app_model.dart';
import '../progress/history_screens.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

/// Home: workout in progress, next recommendations and recent history (stage D core; the full
/// iOS Home — plan, streak, weekly goal, records — is added in stage E).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final theme = Theme.of(context);
    final open = model.workout.openSession();
    final routines = model.repository.routines().where((r) => !r.isArchived).toList();
    final summaries = model.history.completedSessionSummaries(limit: 3);
    final dates = DateText(model.workout.calendar);
    final f = model.loadFormatter;
    final next = routines.isEmpty ? null : routines.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Inicio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (open != null)
            GymCard(
              highlighted: true,
              children: [
                Text('Entrenamiento en curso', style: theme.textTheme.titleMedium),
                Text(open.routineNameSnapshot ?? 'Entrenamiento libre'),
                FilledButton.icon(
                  onPressed: () => model.selectTab(AppTab.workout),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Retomar'),
                ),
              ],
            )
          else if (next != null) ...[
            Text('Próximo: ${next.name}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final (item, exercise, rec) in model.workout.previewRecommendations(next.id, now: model.now()))
              ListTile(
                key: ValueKey(item.id),
                contentPadding: EdgeInsets.zero,
                title: Text(exercise.name),
                subtitle: Text(
                  rec.action == RecommendationAction.needsInitialTarget && rec.targetWeight == null
                      ? 'Sin datos: configurá un objetivo inicial'
                      : '${rec.actionTitle}: ${f.load(rec.targetWeight, rec.measurement, rec.context.loadMode)} × ${rec.amountsText}',
                ),
                trailing: rec.confidence == RecommendationConfidence.conditional
                    ? const GymBadge('Condicionada', color: GymColors.caution)
                    : null,
              ),
          ] else
            const EmptyState(
              icon: Icons.fitness_center,
              title: 'Empezá creando una rutina',
              message: 'En la pestaña Rutinas podés crear una rutina vacía o partir de una plantilla editable.',
            ),
          const SectionTitle('Últimos entrenamientos'),
          if (summaries.isEmpty) const Text('Todavía no hay entrenamientos finalizados.'),
          for (final s in summaries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.session.routineNameSnapshot ?? 'Entrenamiento libre'),
              subtitle: Text('${dates.weekdayDayMonth(s.session.startedAt)} · ${s.effectiveSets} series'),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(sessionId: s.session.id))),
            ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SessionHistoryScreen())),
            child: const Text('Ver historial completo'),
          ),
        ],
      ),
    );
  }
}
