import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../library/library_screen.dart';
import 'exercise_picker_screen.dart';
import 'routine_exercise_editor.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  bool _showArchived = false;

  Future<void> _delete(BuildContext context, AppModel model, RoutineTemplate r) async {
    if (model.repository.hasRoutineHistory(r.id)) {
      if (await confirm(
        context,
        title: '¿Eliminar la rutina?',
        message: '"${r.name}" tiene entrenamientos registrados: se archiva y el historial queda intacto.',
        action: 'Archivar',
      )) {
        model.perform(() => model.routines.setArchived(r.id, true));
      }
    } else if (await confirm(
      context,
      title: '¿Eliminar la rutina?',
      message: '"${r.name}" no tiene historial y se eliminará.',
      action: 'Eliminar',
      destructive: true,
    )) {
      model.perform(() => model.routines.deleteRoutine(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final all = model.repository.routines();
    final active = all.where((r) => !r.isArchived).toList();
    final archived = all.where((r) => r.isArchived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rutinas'),
        actions: [
          IconButton(
            tooltip: 'Biblioteca',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LibraryScreen())),
          ),
          PopupMenuButton<String>(
            key: const Key('newRoutineMenu'),
            tooltip: 'Nueva rutina',
            icon: const Icon(Icons.add),
            onSelected: (v) async {
              if (v == 'empty') {
                final name = await promptText(context, title: 'Nueva rutina', hint: 'Nombre', action: 'Crear');
                if (name != null) model.perform(() => model.routines.createRoutine(name, now: model.now()));
              } else {
                final preset = RoutinePreset.all.firstWhere((p) => p.id == v);
                model.perform(() => model.routines.createFromPreset(preset, now: model.now()));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'empty',
                child: ListTile(leading: Icon(Icons.add), title: Text('Rutina vacía')),
              ),
              const PopupMenuDivider(),
              for (final p in RoutinePreset.all) PopupMenuItem(value: p.id, child: Text('Plantilla: ${p.name}')),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          if (active.isEmpty)
            const EmptyState(
              icon: Icons.list_alt,
              title: 'Sin rutinas',
              message: 'Creá una rutina vacía o partí de una plantilla editable (botón +).',
            ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (from, to) {
              final ids = active.map((r) => r.id).toList();
              final moved = ids.removeAt(from);
              ids.insert(to, moved);
              model.perform(() => model.routines.reorderRoutines(ids));
            },
            children: [
              for (final r in active)
                ListTile(
                  key: ValueKey(r.id),
                  title: Text(r.name),
                  subtitle: Text(_count(model.repository.routineExercises(r.id).length)),
                  onTap: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => RoutineDetailScreen(routineId: r.id))),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Opciones de ${r.name}',
                    onSelected: (v) {
                      switch (v) {
                        case 'duplicate':
                          model.perform(() => model.routines.duplicateRoutine(r.id, now: model.now()));
                        case 'archive':
                          model.perform(() => model.routines.setArchived(r.id, true));
                        case 'delete':
                          _delete(context, model, r);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'duplicate', child: Text('Duplicar')),
                      PopupMenuItem(value: 'archive', child: Text('Archivar')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
                ),
            ],
          ),
          if (archived.isNotEmpty)
            ExpansionTile(
              title: Text('Archivadas (${archived.length})'),
              initiallyExpanded: _showArchived,
              onExpansionChanged: (v) => setState(() => _showArchived = v),
              children: [
                for (final r in archived)
                  ListTile(
                    title: Text(r.name, style: TextStyle(color: Theme.of(context).hintColor)),
                    trailing: TextButton(
                      onPressed: () => model.perform(() => model.routines.setArchived(r.id, false)),
                      child: const Text('Restaurar'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _count(int n) => n == 0 ? 'Sin ejercicios' : (n == 1 ? '1 ejercicio' : '$n ejercicios');
}

/// Routine editor + recommendation preview + start button.
class RoutineDetailScreen extends StatelessWidget {
  const RoutineDetailScreen({super.key, required this.routineId});
  final String routineId;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final routine = model.repository.routine(routineId);
    if (routine == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.help_outline, title: 'Rutina no encontrada'),
      );
    }
    final items = model.repository.routineExercises(routineId);
    final previews = {for (final p in model.workout.previewRecommendations(routineId, now: model.now())) p.$1.id: p.$3};
    final open = model.workout.openSession();
    return Scaffold(
      appBar: AppBar(
        title: Text(routine.name),
        actions: [
          IconButton(
            tooltip: 'Renombrar',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final name = await promptText(context, title: 'Renombrar rutina', initial: routine.name);
              if (name != null) model.perform(() => model.routines.updateRoutine(routine..name = name));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              key: const Key('startRoutine'),
              onPressed: items.isEmpty || open != null
                  ? null
                  : () {
                      if (model.perform(() => model.workout.startSession(routineId, now: model.now())) != null) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        model.selectTab(AppTab.workout);
                      }
                    },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Comenzar entrenamiento'),
            ),
          ),
          if (open != null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Ya hay un entrenamiento en curso (pestaña Entrenar).'),
            ),
          const SectionTitle('Ejercicios'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (from, to) {
              final ids = items.map((i) => i.id).toList();
              final moved = ids.removeAt(from);
              ids.insert(to, moved);
              model.perform(() => model.routines.moveExercises(routineId, ids));
            },
            children: [
              for (final item in items)
                if (model.repository.exercise(item.exerciseId) case final exercise?)
                  _RoutineExerciseTile(
                    key: ValueKey(item.id),
                    item: item,
                    exercise: exercise,
                    config: model.routines.effectiveConfig(item) ?? exercise.progression,
                    preview: previews[item.id],
                  ),
            ],
          ),
          ListTile(
            key: const Key('addRoutineExercise'),
            leading: const Icon(Icons.add),
            title: const Text('Agregar ejercicio'),
            onTap: () async {
              final picked = await Navigator.of(context)
                  .push<Exercise>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
              if (picked != null) model.perform(() => model.routines.addExercise(routineId, picked.id));
            },
          ),
          if (routine.notes.isNotEmpty) ...[
            const SectionTitle('Notas'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(routine.notes)),
          ],
        ],
      ),
    );
  }
}

class _RoutineExerciseTile extends StatelessWidget {
  const _RoutineExerciseTile({
    super.key,
    required this.item,
    required this.exercise,
    required this.config,
    required this.preview,
  });
  final RoutineExercise item;
  final Exercise exercise;
  final ProgressionConfig config;
  final Recommendation? preview;

  String get _target {
    final rir = config.targetRIR == null ? '' : ' · RIR ${config.targetRIR}';
    if (exercise.measurement == MeasurementType.duration) {
      return '${config.targetSets} × ${config.secondsMin}–${config.secondsMax} s$rir';
    }
    return '${config.targetSets} × ${config.repMin}–${config.repMax}$rir';
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final f = model.loadFormatter;
    final p = preview;
    String? summary;
    if (p != null) {
      summary = p.action == RecommendationAction.needsInitialTarget
          ? (p.targetWeight == null
                ? 'Sin datos: configurá un objetivo inicial'
                : 'Inicial: ${f.load(p.targetWeight, p.measurement, p.context.loadMode)}')
          : '${p.actionTitle}: ${f.load(p.targetWeight, p.measurement, p.context.loadMode)} × ${p.amountsText}';
    }
    return ListTile(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RoutineExerciseEditor(itemId: item.id))),
      title: Row(
        children: [
          Flexible(child: Text(exercise.name)),
          if (item.supersetGroup != null) ...[const SizedBox(width: 6), GymBadge('Superserie ${item.supersetGroup}')],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_target),
          // Recommendation summary also appears in the routine preview (section 2.A).
          if (summary != null)
            Row(
              children: [
                Flexible(
                  child: Text(summary, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ),
                if (p!.confidence == RecommendationConfidence.conditional) ...[
                  const SizedBox(width: 6),
                  const GymBadge('Condicionada', color: GymColors.caution),
                ],
              ],
            ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Opciones de ${exercise.name}',
        onSelected: (v) {
          if (v == 'duplicate') model.perform(() => model.routines.duplicateRoutineExercise(item.id));
          if (v == 'remove') model.perform(() => model.routines.removeRoutineExercise(item.id));
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'duplicate', child: Text('Duplicar')),
          PopupMenuItem(value: 'remove', child: Text('Quitar')),
        ],
      ),
    );
  }
}
