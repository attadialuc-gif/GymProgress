import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import 'recommendation_card.dart';
import 'set_table.dart';

/// Exercise screen during a session: recommendation card first, then the set table.
class ExerciseLogScreen extends StatefulWidget {
  const ExerciseLogScreen({super.key, required this.logId, this.onOpenExercise});
  final String logId;

  /// Superset hop: replaces this screen with another exercise of the session.
  final void Function(String logId)? onOpenExercise;

  @override
  State<ExerciseLogScreen> createState() => _ExerciseLogScreenState();
}

class _ExerciseLogScreenState extends State<ExerciseLogScreen> {
  bool _opened = false;
  String? _nextInSuperset;
  final _notes = TextEditingController();
  final _notesFocus = FocusNode();
  late AppModel _model;
  String? _openError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model = AppScope.read(context);
    if (_opened) return;
    _opened = true;
    // Opening freezes the recommendation (computed with history prior to this session).
    final model = _model;
    // Saved quietly: this runs while the tree builds (the screen reads the store itself).
    ExerciseLogState? state;
    model.performQuietly(() => state = model.workout.openExercise(widget.logId, now: model.now()));
    if (state == null) {
      _openError = model.errorMessage ?? 'No se pudo abrir el ejercicio.';
      // Surface the error dialog after this frame (no notify while building).
      WidgetsBinding.instance.addPostFrameCallback((_) => model.perform(() {}));
    }
    _notes.text = state?.log.notes ?? '';
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus) _saveNotes();
    });
  }

  @override
  void dispose() {
    _saveNotes(notify: false);
    _notes.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _saveNotes({bool notify = true}) {
    final model = _model;
    final log = model.repository.exerciseLog(widget.logId);
    if (log == null || log.notes == _notes.text) return;
    if (notify) {
      model.perform(() => model.workout.setExerciseNotes(widget.logId, _notes.text));
    } else {
      // The screen is being removed: save without rebuilding a tree that is being torn down.
      model.performQuietly(() => model.workout.setExerciseNotes(widget.logId, _notes.text));
    }
  }

  /// Re-reads sets/decision after each mutation; the recommendation itself stays frozen.
  ExerciseLogState? _state(AppModel model) {
    final log = model.repository.exerciseLog(widget.logId);
    final rec = log?.frozenRecommendation;
    if (log == null || rec == null) return null;
    return ExerciseLogState(log, model.repository.setLogs(widget.logId), rec, model.repository.decision(widget.logId));
  }

  void _complete(AppModel model, SetLog set) {
    final done = model.perform(() => model.workout.completeSet(set.id, now: model.now()));
    if (done == null) return;
    HapticFeedback.mediumImpact();
    final advice = model.workout.restAdvice(set.id);
    setState(() => _nextInSuperset = advice.nextExerciseLogId);
    if (advice.restSeconds != null) {
      model.restTimer.start(advice.restSeconds!, model.now());
    } else {
      // Mid-round of a superset: no rest; cancel a timer left from before.
      model.restTimer.stop();
    }
  }

  Future<void> _openModify(ExerciseLogState state, {required bool initialTarget}) async {
    final model = AppScope.read(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ModifySheet(
        recommendation: state.recommendation,
        increment: state.log.configSnapshot.increment,
        formatter: model.loadFormatter,
        title: initialTarget ? 'Objetivo inicial' : 'Modificar objetivo',
        onSave: (weight, reps, seconds) {
          if (initialTarget) {
            model.perform(
              () => model.workout.setInitialTarget(
                widget.logId,
                weight: weight,
                reps: reps,
                seconds: seconds,
                now: model.now(),
              ),
            );
          } else {
            model.perform(
              () => model.workout.decide(
                widget.logId,
                ModifyChoice(weight: weight, reps: reps, seconds: seconds),
                now: model.now(),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final state = _state(model);
    if (state == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _openError == null
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(icon: Icons.error_outline, title: 'No se pudo abrir el ejercicio', message: _openError),
      );
    }
    final log = state.log;
    final next = _nextInSuperset == null ? null : model.repository.exerciseLog(_nextInSuperset!);
    final dates = DateText(model.workout.calendar);
    return Scaffold(
      appBar: AppBar(title: Text(log.snapshot.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            RecommendationCard(
              recommendation: state.recommendation,
              decision: state.decision,
              formatter: model.loadFormatter,
              dates: dates,
              onAccept: () =>
                  model.perform(() => model.workout.decide(widget.logId, const AcceptChoice(), now: model.now())),
              onModify: () => _openModify(state, initialTarget: false),
              onIgnore: () =>
                  model.perform(() => model.workout.decide(widget.logId, const IgnoreChoice(), now: model.now())),
              onCopyPrevious: (nonEquivalent) => model.perform(
                () =>
                    model.workout.copyPreviousLoads(widget.logId, allowNonEquivalent: nonEquivalent, now: model.now()),
              ),
              onSetInitialTarget: () => _openModify(state, initialTarget: true),
            ),
            const SizedBox(height: 12),
            _ContextRow(log: log),
            const SizedBox(height: 8),
            SetTable(
              log: log,
              sets: state.sets,
              previous: state.recommendation.lastPerformance,
              onComplete: (s) => _complete(model, s),
            ),
            const RestTimerBanner(),
            if (next != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() => _nextInSuperset = null);
                    widget.onOpenExercise?.call(next.id);
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: Text('Superserie: seguí con ${next.snapshot.name}'),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => model.perform(() => model.workout.addSet(widget.logId)),
                  icon: const Icon(Icons.add),
                  label: const Text('Serie'),
                ),
                OutlinedButton.icon(
                  onPressed: () => model.perform(() => model.workout.addSet(widget.logId, kind: SetKind.warmup)),
                  icon: const Icon(Icons.local_fire_department_outlined),
                  label: const Text('Calentamiento'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ejercicio atípico hoy'),
              value: log.isAtypical,
              onChanged: (v) => model.perform(() => model.workout.setExerciseAtypical(widget.logId, v)),
            ),
            TextField(
              controller: _notes,
              focusNode: _notesFocus,
              maxLines: null,
              decoration: const InputDecoration(labelText: 'Notas del ejercicio'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({required this.log});
  final ExerciseLog log;

  @override
  Widget build(BuildContext context) {
    final parts = [log.equipmentLabel, log.variantLabel].whereType<String>().toList();
    return Semantics(
      hint: 'Indicá si hoy usás otra máquina o variante: no se compara con otro contexto',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.tune),
        title: Text(parts.isEmpty ? 'Máquina / variante: estándar' : parts.join(' · ')),
        trailing: Text('Cambiar', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _ContextEditor(log: log),
        ),
      ),
    );
  }
}

/// Change of machine / variant (comparability context, section 8.1).
class _ContextEditor extends StatefulWidget {
  const _ContextEditor({required this.log});
  final ExerciseLog log;

  @override
  State<_ContextEditor> createState() => _ContextEditorState();
}

class _ContextEditorState extends State<_ContextEditor> {
  late final _equipment = TextEditingController(text: widget.log.equipmentLabel ?? '');
  late final _variant = TextEditingController(text: widget.log.variantLabel ?? '');

  @override
  void dispose() {
    _equipment.dispose();
    _variant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.read(context);
    final theme = Theme.of(context);
    final current = [widget.log.equipmentLabel, widget.log.variantLabel].whereType<String>().join(' · ');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text('Contexto', style: theme.textTheme.titleLarge),
              TextField(
                controller: _equipment,
                decoration: const InputDecoration(labelText: 'Máquina / equipo (ej.: Polea 2)'),
              ),
              TextField(
                controller: _variant,
                decoration: const InputDecoration(labelText: 'Variante (ej.: agarre cerrado)'),
              ),
              Text(
                'Con otro contexto la app no compara automáticamente con el historial anterior. Si son equivalentes, podés vincularlos.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              FilledButton(
                onPressed: () {
                  model.perform(
                    () => model.workout.setContext(
                      widget.log.id,
                      variantLabel: _variant.text,
                      equipmentLabel: _equipment.text,
                      now: model.now(),
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Guardar'),
              ),
              OutlinedButton(
                onPressed: () {
                  model.perform(
                    () => model.workout.switchContextTreatingAsEquivalent(
                      widget.log.id,
                      variantLabel: _variant.text,
                      equipmentLabel: _equipment.text,
                      now: model.now(),
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Guardar y tratar como equivalente al anterior'),
              ),
              Text(
                'Vincula el contexto que estabas usando (${current.isEmpty ? 'estándar' : current}) con el nuevo: desde ahora sus resultados se comparan entre sí.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rest countdown from the stored end time (survives background/lock).
class RestTimerBanner extends StatefulWidget {
  const RestTimerBanner({super.key});

  @override
  State<RestTimerBanner> createState() => _RestTimerBannerState();
}

class _RestTimerBannerState extends State<RestTimerBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      // Only while visible: current route of the selected tab.
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (AppScope.read(context).selectedTab != AppTab.workout) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final timer = model.restTimer;
    return ListenableBuilder(
      listenable: timer,
      builder: (context, _) {
        if (!timer.isRunning) return const SizedBox.shrink();
        final remaining = timer.remaining(model.now());
        final color = remaining > 0 ? Theme.of(context).colorScheme.primary : GymColors.positive;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Semantics(
            liveRegion: remaining == 0,
            label: remaining > 0
                ? 'Descanso: ${formatDuration(remaining.toDouble(), hours: false)}'
                : 'Descanso terminado',
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Icon(Icons.timer_outlined, color: color),
                Text(remaining > 0 ? 'Descanso' : 'Descanso terminado', style: TextStyle(color: color)),
                Text(
                  formatDuration(remaining.toDouble(), hours: false),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                OutlinedButton(onPressed: () => timer.add(30, model.now()), child: const Text('+30 s')),
                IconButton(tooltip: 'Detener descanso', onPressed: timer.stop, icon: const Icon(Icons.close)),
              ],
            ),
          ),
        );
      },
    );
  }
}
