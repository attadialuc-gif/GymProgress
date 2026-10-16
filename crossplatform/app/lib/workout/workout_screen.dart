import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../routines/exercise_picker_screen.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import 'exercise_log_screen.dart';

/// "Entrenar" tab: the open session, or a quick way to start one.
class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final session = model.workout.openSession();
    return session == null ? const _StartWorkout() : WorkoutSessionView(sessionId: session.id);
  }
}

class _StartWorkout extends StatelessWidget {
  const _StartWorkout();

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final routines = model.repository.routines().where((r) => !r.isArchived).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Entrenar')),
      body: ListView(
        children: [
          const SectionTitle('Elegí una rutina'),
          if (routines.isEmpty) const ListTile(title: Text('Creá una rutina en la pestaña Rutinas.')),
          for (final r in routines)
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(r.name),
              onTap: () => model.perform(() => model.workout.startSession(r.id, now: model.now())),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Entrenamiento libre'),
            onTap: () => model.perform(() => model.workout.startSession(null, now: model.now())),
          ),
        ],
      ),
    );
  }
}

/// The active session: elapsed time (minus pauses), exercises, pause/finish/discard.
class WorkoutSessionView extends StatefulWidget {
  const WorkoutSessionView({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<WorkoutSessionView> createState() => _WorkoutSessionViewState();
}

class _WorkoutSessionViewState extends State<WorkoutSessionView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _openExercise(BuildContext context, String logId, {bool replace = false}) {
    final route = MaterialPageRoute<void>(
      builder: (_) => ExerciseLogScreen(
        logId: logId,
        // Superset hop replaces the current screen (A → B → A never piles up screens).
        onOpenExercise: (next) => _openExercise(context, next, replace: true),
      ),
    );
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final session = model.repository.session(widget.sessionId);
    if (session == null) return const SizedBox.shrink();
    final logs = model.repository.exerciseLogsOfSession(widget.sessionId);
    final theme = Theme.of(context);
    final paused = session.status == SessionStatus.paused;
    return Scaffold(
      appBar: AppBar(title: const Text('En curso')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.routineNameSnapshot ?? 'Entrenamiento libre', style: theme.textTheme.titleMedium),
                      Text(
                        formatDuration(session.elapsed(model.now())),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: paused ? theme.hintColor : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (paused)
                  FilledButton.icon(
                    onPressed: () => model.perform(() => model.workout.resume(widget.sessionId, now: model.now())),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Reanudar'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => model.perform(() => model.workout.pause(widget.sessionId, now: model.now())),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pausar'),
                  ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: RestTimerBanner()),
          const SectionTitle('Ejercicios'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorderItem: (from, to) {
              final ids = logs.map((l) => l.id).toList();
              final moved = ids.removeAt(from);
              ids.insert(to, moved);
              model.perform(() => model.workout.moveExercises(widget.sessionId, ids));
            },
            children: [
              for (final log in logs)
                _SessionExerciseTile(
                  key: ValueKey(log.id),
                  log: log,
                  onTap: () => _openExercise(context, log.id),
                  onRemove: () async {
                    if (await confirm(
                      context,
                      title: '¿Quitar este ejercicio del entrenamiento de hoy?',
                      message: 'La rutina no cambia. Se pierde lo cargado en este ejercicio hoy (no tiene series completadas).',
                      action: 'Quitar de hoy',
                      destructive: true,
                    )) {
                      model.perform(() => model.workout.removeExercise(log.id));
                    }
                  },
                ),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Agregar ejercicio (solo hoy)'),
            onTap: () async {
              final picked = await Navigator.of(context)
                  .push<Exercise>(MaterialPageRoute(builder: (_) => const ExercisePickerScreen()));
              if (picked != null) {
                model.perform(() => model.workout.addExercise(widget.sessionId, picked.id, now: model.now()));
              }
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Sesión atípica (enfermedad, descarga, viaje)'),
            subtitle: const Text('Se guarda y se muestra, pero no cuenta para tendencias ni recomendaciones.'),
            value: session.isAtypical,
            onChanged: (v) =>
                model.perform(() => model.workout.setSessionAtypical(widget.sessionId, v, now: model.now())),
          ),
          ListTile(
            leading: const Icon(Icons.notes),
            title: Text(session.notes.isEmpty ? 'Agregar nota' : session.notes),
            onTap: () async {
              final text = await promptText(context, title: 'Nota de la sesión', initial: session.notes);
              if (text != null) {
                model.perform(() => model.workout.setSessionNotes(widget.sessionId, text, now: model.now()));
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              key: const Key('finishWorkout'),
              onPressed: () async {
                if (await confirm(
                  context,
                  title: '¿Finalizar el entrenamiento?',
                  message: 'Las series pendientes quedan sin realizar (no cuentan como cero).',
                  action: 'Finalizar',
                )) {
                  model.perform(() => model.workout.finish(widget.sessionId, now: model.now()));
                  model.restTimer.stop();
                }
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Finalizar entrenamiento'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              onPressed: () async {
                if (await confirm(
                  context,
                  title: '¿Descartar el entrenamiento?',
                  message: 'No contará en el historial, las estadísticas ni las recomendaciones.',
                  action: 'Descartar',
                  destructive: true,
                )) {
                  model.perform(() => model.workout.discard(widget.sessionId, now: model.now()));
                  model.restTimer.stop();
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Descartar entrenamiento'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionExerciseTile extends StatelessWidget {
  const _SessionExerciseTile({super.key, required this.log, required this.onTap, required this.onRemove});
  final ExerciseLog log;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final sets = model.repository.setLogs(log.id).where((s) => s.kind != SetKind.warmup).toList();
    final done = sets.where((s) => s.status == SetStatus.completed).length;
    final label = [log.variantLabel, log.equipmentLabel].whereType<String>().firstOrNull;
    return Semantics(
      label: '${log.snapshot.name}, $done de ${sets.length} series completadas',
      child: ListTile(
        onTap: onTap,
        onLongPress: onRemove,
        title: Row(
          children: [
            Flexible(child: Text(log.snapshot.name)),
            if (log.supersetGroup != null) ...[const SizedBox(width: 6), GymBadge('Superserie ${log.supersetGroup}')],
          ],
        ),
        subtitle: label == null ? null : Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$done/${sets.length}',
              style: TextStyle(
                color: done == sets.length && done > 0 ? GymColors.positive : Theme.of(context).hintColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(tooltip: 'Quitar de hoy', onPressed: onRemove, icon: const Icon(Icons.remove_circle_outline)),
          ],
        ),
      ),
    );
  }
}
