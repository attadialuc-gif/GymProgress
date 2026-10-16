import 'package:flutter/material.dart';

import '../app_model.dart';
import '../ui/theme.dart';
import 'history_screens.dart';

/// Progress (stage D core: session history and per-exercise history with the next
/// recommendation; filters, charts, muscles and records come in stage E).
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final ids = model.history.exerciseIdsWithCompletedHistory();
    final exercises = model.repository.exercises().where((e) => ids.contains(e.id)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Progreso')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Historial de entrenamientos'),
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SessionHistoryScreen())),
          ),
          const SectionTitle('Ejercicios'),
          if (exercises.isEmpty)
            const EmptyState(
              icon: Icons.show_chart,
              title: 'Sin datos todavía',
              message: 'Finalizá un entrenamiento para ver tu progreso.',
            ),
          for (final e in exercises)
            ListTile(
              title: Text(e.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => ExerciseHistoryScreen(exerciseId: e.id))),
            ),
        ],
      ),
    );
  }
}
