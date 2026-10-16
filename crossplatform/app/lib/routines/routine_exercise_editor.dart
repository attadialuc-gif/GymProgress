import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';

import '../app_model.dart';
import '../ui/theme.dart';

/// Target and progression criteria for one exercise of a routine (section 2.B): range, sets, RIR,
/// increment, available weights, consecutive sessions, strategy, rest, superset, notes.
class RoutineExerciseEditor extends StatefulWidget {
  const RoutineExerciseEditor({super.key, required this.itemId});
  final String itemId;

  @override
  State<RoutineExerciseEditor> createState() => _RoutineExerciseEditorState();
}

class _RoutineExerciseEditorState extends State<RoutineExerciseEditor> {
  bool _loaded = false;
  late ProgressionConfig _config;
  bool _hasRIR = true;
  int _rir = 2;
  final _initial = TextEditingController();
  final _increment = TextEditingController();
  final _available = TextEditingController();
  final _notes = TextEditingController();
  int _rest = 120;
  int _superset = 0;
  bool _applyToExercise = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final model = AppScope.read(context);
    final item = model.repository.routineExercise(widget.itemId)!;
    final f = model.loadFormatter;
    _config = (model.routines.effectiveConfig(item) ?? ProgressionConfig()).copy();
    _hasRIR = _config.targetRIR != null;
    _rir = _config.targetRIR ?? 2;
    _initial.text = f.editable(_config.initialWeight);
    _increment.text = f.editable(_config.increment);
    _available.text = (_config.availableWeights ?? const <double>[]).map(f.editable).join('; ');
    _rest =
        item.restSeconds ??
        model.repository.exercise(item.exerciseId)?.defaultRestSeconds ??
        model.settings.defaultRestSeconds;
    _notes.text = item.notes;
    _superset = item.supersetGroup ?? 0;
  }

  @override
  void dispose() {
    for (final c in [_initial, _increment, _available, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final model = AppScope.read(context);
    final f = model.loadFormatter;
    final item = model.repository.routineExercise(widget.itemId)!;
    void fail(String message) {
      model.errorMessage = message;
      model.perform(() {});
    }

    final updated = _config.copy()..targetRIR = _hasRIR ? _rir : null;
    // Never drop typed input silently: invalid values stop the save with an explanation.
    if (swiftTrim(_initial.text).isEmpty) {
      updated.initialWeight = null;
    } else {
      final initial = f.parse(_initial.text);
      if (initial == null) return fail('Peso inicial inválido: usá coma o punto decimal (ej.: 40 o 42,5).');
      updated.initialWeight = initial;
    }
    final inc = f.parse(_increment.text);
    if (inc == null || inc <= 0) return fail('Incremento inválido: usá coma o punto decimal (ej.: 2,5).');
    updated.increment = inc;
    final parts = _available.text.split(';').map(swiftTrim).where((p) => p.isNotEmpty).toList();
    final weights = parts.map(f.parse).whereType<double>().toList();
    if (weights.length != parts.length) {
      return fail('Pesos disponibles inválidos: separalos con punto y coma (ej.: 20; 22,5; 25).');
    }
    updated.availableWeights = weights.isEmpty ? null : weights;
    item
      ..progressionOverride = updated
      ..restSeconds = _rest
      ..notes = _notes.text
      ..supersetGroup = _superset == 0 ? null : _superset;
    final ok = model.perform(() {
      model.routines.updateRoutineExercise(item);
      if (_applyToExercise) model.catalog.updateProgression(item.exerciseId, updated);
      return true;
    });
    if (ok != null) Navigator.pop(context);
  }

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> onChanged, {int step = 1}) => Row(
    children: [
      Expanded(child: Text(label)),
      IconButton(
        tooltip: 'Menos',
        onPressed: value - step >= min ? () => setState(() => onChanged(value - step)) : null,
        icon: const Icon(Icons.remove_circle_outline),
      ),
      IconButton(
        tooltip: 'Más',
        onPressed: value + step <= max ? () => setState(() => onChanged(value + step)) : null,
        icon: const Icon(Icons.add_circle_outline),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final item = model.repository.routineExercise(widget.itemId);
    final exercise = item == null ? null : model.repository.exercise(item.exerciseId);
    final isDuration = exercise?.measurement == MeasurementType.duration;
    final unit = model.settings.weightUnit.name;
    final c = _config;
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(
        title: Text(exercise?.name ?? 'Ejercicio'),
        actions: [TextButton(onPressed: _save, child: const Text('Guardar'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle('Objetivo'),
          _stepper('Series: ${c.targetSets}', c.targetSets, 1, 10, (v) => c.targetSets = v),
          if (isDuration) ...[
            _stepper('Mínimo: ${c.secondsMin} s', c.secondsMin, 5, 600, (v) => c.secondsMin = v, step: 5),
            _stepper('Máximo: ${c.secondsMax} s', c.secondsMax, c.secondsMin, 900, (v) => c.secondsMax = v, step: 5),
            _stepper('Paso: ${c.secondsIncrement} s', c.secondsIncrement, 1, 60, (v) => c.secondsIncrement = v),
          ] else ...[
            _stepper('Repeticiones mínimas: ${c.repMin}', c.repMin, 1, 50, (v) {
              c.repMin = v;
              if (c.repMax < v) c.repMax = v;
            }),
            _stepper('Repeticiones máximas: ${c.repMax}', c.repMax, c.repMin, 60, (v) => c.repMax = v),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('RIR objetivo'),
            value: _hasRIR,
            onChanged: (v) => setState(() => _hasRIR = v),
          ),
          if (_hasRIR) _stepper('RIR $_rir (repeticiones en reserva)', _rir, 0, 5, (v) => _rir = v),
          const SectionTitle('Sin historial'),
          TextField(
            controller: _initial,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Peso inicial ($unit)', hintText: 'Opcional'),
          ),
          Text(
            'Se usa solo cuando todavía no hay sesiones comparables. La app nunca inventa un peso.',
            style: TextStyle(color: hint, fontSize: 12),
          ),
          const SectionTitle('Progresión'),
          TextField(
            controller: _increment,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Incremento ($unit)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _available,
            decoration: const InputDecoration(labelText: 'Pesos disponibles (ej.: 20; 22,5; 25)'),
          ),
          Text(
            'Con pesos disponibles (mancuernas, pila de la máquina) la recomendación usa el siguiente peso real de la lista. Separá los valores con punto y coma.',
            style: TextStyle(color: hint, fontSize: 12),
          ),
          _stepper(
            'Sesiones al tope antes de subir: ${c.requiredConsecutiveSessions}',
            c.requiredConsecutiveSessions,
            1,
            5,
            (v) => c.requiredConsecutiveSessions = v,
          ),
          _stepper(
            'Reevaluar tras ${c.reassessAfterDays} días sin entrenarlo',
            c.reassessAfterDays,
            7,
            90,
            (v) => c.reassessAfterDays = v,
            step: 7,
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Estrategia'),
            trailing: Text('Doble progresión'),
          ),
          const SectionTitle('Sesión'),
          _stepper('Descanso: $_rest s', _rest, 15, 600, (v) => _rest = v, step: 15),
          _stepper(_superset == 0 ? 'Sin superserie' : 'Superserie $_superset', _superset, 0, 9, (v) => _superset = v),
          TextField(
            controller: _notes,
            maxLines: null,
            decoration: const InputDecoration(labelText: 'Notas / técnica'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Usar también como predeterminado del ejercicio'),
            subtitle: const Text(
              'Cambiar estos criterios no modifica sesiones pasadas: cada sesión guarda los criterios vigentes.',
            ),
            value: _applyToExercise,
            onChanged: (v) => setState(() => _applyToExercise = v),
          ),
        ],
      ),
    );
  }
}
