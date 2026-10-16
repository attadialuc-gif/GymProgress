import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../ui/charts.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import 'progress_screen.dart';

/// Direct and indirect sets per muscle in the period, with optional user-set weekly goals.
class MuscleVolumeScreen extends StatelessWidget {
  const MuscleVolumeScreen({super.key, required this.interval, required this.title, this.routineId});
  final DateInterval interval;
  final String title;
  final String? routineId;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final theme = Theme.of(context);
    final settings = model.settings;
    final stats = model.stats;
    final volume = stableSorted(
      stats.muscleVolume(interval, routineId: routineId),
      (MuscleSetVolume a, MuscleSetVolume b) => b.directSets.compareTo(a.directSets),
    );
    final days = stats.calendar.daysBetween(interval.start, interval.end) / 7;
    final weeks = days < 1 ? 1.0 : days;
    final hint = TextStyle(color: theme.hintColor, fontSize: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('Grupos musculares')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                const HelpButton(title: 'Series indirectas', text: MetricHelp.indirect),
              ],
            ),
          ),
          if (volume.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Sin series en este período.', style: TextStyle(color: theme.hintColor)),
            ),
          for (final item in volume)
            ListTile(
              title: Text(item.muscle.label),
              subtitle: settings.weeklySetGoal(item.muscle) == null
                  ? null
                  : Text('Tu objetivo: ${settings.weeklySetGoal(item.muscle)} series directas por semana'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${item.directSets} directas'),
                  Text(
                    '${GymFormat.number(item.indirectSets, maxFractionDigits: 1)} indirectas · '
                    '${GymFormat.number(item.frequencyDays / weeks, maxFractionDigits: 1)} días/sem.',
                    style: hint,
                  ),
                ],
              ),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => MuscleWeeklyScreen(muscle: item.muscle))),
              onLongPress: () => editMuscleGoal(context, item.muscle),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Los objetivos de series semanales son tuyos (mantené presionado un músculo, o usá el botón en su detalle, para definirlo): la app no impone una cantidad ideal.',
              style: hint,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> editMuscleGoal(BuildContext context, MuscleGroup muscle) async {
  final model = AppScope.read(context);
  final current = model.settings.weeklySetGoal(muscle);
  var hasGoal = current != null;
  var sets = current ?? 10;
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(muscle.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Objetivo semanal'),
              value: hasGoal,
              onChanged: (v) => setState(() => hasGoal = v),
            ),
            if (hasGoal)
              Row(
                children: [
                  Expanded(child: Text('$sets series directas por semana')),
                  IconButton(
                    tooltip: 'Menos',
                    onPressed: sets > 1 ? () => setState(() => sets--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  IconButton(
                    tooltip: 'Más',
                    onPressed: sets < 40 ? () => setState(() => sets++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    ),
  );
  if (save != true) return;
  final updated = model.settings..setWeeklySetGoal(hasGoal ? sets : null, muscle);
  model.perform(() => model.repository.saveSettings(updated));
}

class MuscleWeeklyScreen extends StatelessWidget {
  const MuscleWeeklyScreen({super.key, required this.muscle});
  final MuscleGroup muscle;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final weeks = model.stats.weeklyDirectSets(muscle, weeks: 12, now: model.now());
    final goal = model.settings.weeklySetGoal(muscle);
    final dates = DateText(model.stats.calendar);
    return Scaffold(
      appBar: AppBar(
        title: Text(muscle.label),
        actions: [
          IconButton(
            tooltip: 'Objetivo semanal',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => editMuscleGoal(context, muscle),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          WeeklyBarChart(
            labels: weeks.map((w) => dates.dayMonth(w.weekStart)).toList(),
            primary: weeks.map((w) => w.directSets.toDouble()).toList(),
            secondary: weeks.map((w) => w.indirectSets).toList(),
            goal: goal?.toDouble(),
            height: 220,
            semanticLabel: 'Series semanales de ${muscle.label}, últimas 12 semanas',
          ),
          const SizedBox(height: 8),
          Text(
            'Barras apiladas: directas (color pleno) e indirectas estimadas (color claro) se informan por separado.'
            '${goal == null ? '' : ' Línea punteada: tu objetivo de $goal series directas.'}',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final w in weeks.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Semana del ${dates.dayMonth(w.weekStart)}'),
              trailing: Text(
                '${w.directSets} directas · ${GymFormat.number(w.indirectSets, maxFractionDigits: 1)} indirectas',
              ),
            ),
          const SizedBox(height: 4),
          const GymBadge('Indirectas = estimación'),
        ],
      ),
    );
  }
}
