import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';

import '../app_model.dart';
import '../progress/history_screens.dart';
import '../routines/exercise_picker_screen.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

/// Exercise library management: browse, create custom exercises, edit criteria, archive.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _query = '';
  MuscleGroup? _muscle;

  bool _matches(Exercise e) {
    final m = _muscle;
    return searchMatches(e.name, _query) &&
        (m == null || e.primaryMuscles.contains(m) || e.secondaryMuscles.any((s) => s.muscle == m));
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final all = model.repository.exercises();
    final active = all.where((e) => !e.isArchived && _matches(e)).toList();
    final archived = all.where((e) => e.isArchived && _matches(e)).toList();
    Widget tile(Exercise e) => ListTile(
      title: Row(
        children: [
          Flexible(child: Text(e.name)),
          if (e.isCustom) ...[const SizedBox(width: 6), const GymBadge('Propio')],
        ],
      ),
      subtitle: Text('${e.equipment.label} · ${e.primaryMuscles.map((m) => m.label).join(', ')}'),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExerciseDetailScreen(exerciseId: e.id))),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biblioteca'),
        actions: [
          IconButton(
            tooltip: 'Nuevo ejercicio',
            icon: const Icon(Icons.add),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<Exercise>(builder: (_) => const CustomExerciseForm())),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar ejercicio'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButtonFormField<MuscleGroup?>(
              isExpanded: true,
              initialValue: _muscle,
              decoration: const InputDecoration(labelText: 'Músculo'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                for (final m in MuscleGroup.values) DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (v) => setState(() => _muscle = v),
            ),
          ),
          SectionTitle('${active.length} ejercicios'),
          for (final e in active) tile(e),
          if (archived.isNotEmpty)
            ExpansionTile(
              title: Text('Archivados (${archived.length})'),
              children: [for (final e in archived) tile(e)],
            ),
        ],
      ),
    );
  }
}

/// Exercise detail: muscles, default progression criteria (section 2.B), archive / delete.
class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  bool _loaded = false;
  final _name = TextEditingController();
  final _increment = TextEditingController();
  final _initial = TextEditingController();
  final _available = TextEditingController();
  late ProgressionConfig _config;
  bool _hasRIR = true;
  int _rir = 2;
  int _rest = 120;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final model = AppScope.read(context);
    final e = model.repository.exercise(widget.exerciseId);
    if (e == null) return;
    _loaded = true;
    final f = model.loadFormatter;
    _name.text = e.name;
    _config = e.progression.copy();
    _hasRIR = _config.targetRIR != null;
    _rir = _config.targetRIR ?? 2;
    _increment.text = f.editable(_config.increment);
    _initial.text = f.editable(_config.initialWeight);
    _available.text = (_config.availableWeights ?? const <double>[]).map(f.editable).join('; ');
    _rest = e.defaultRestSeconds ?? model.settings.defaultRestSeconds;
  }

  @override
  void dispose() {
    for (final c in [_name, _increment, _initial, _available]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save(AppModel model, Exercise exercise) {
    final f = model.loadFormatter;
    final c = _config.copy()..targetRIR = _hasRIR ? _rir : null;
    // Never drop typed input silently: invalid values stop the save with an explanation.
    final inc = f.parseKeeping(_increment.text, _config.increment);
    if (inc == null || inc <= 0) {
      _error(model, 'Incremento inválido: usá coma o punto decimal (ej.: 2,5).');
      return;
    }
    c.increment = inc;
    if (swiftTrim(_initial.text).isEmpty) {
      c.initialWeight = null;
    } else {
      final initial = f.parseKeeping(_initial.text, _config.initialWeight);
      if (initial == null) {
        _error(model, 'Peso inicial inválido: usá coma o punto decimal (ej.: 40 o 42,5).');
        return;
      }
      c.initialWeight = initial;
    }
    final parts = _available.text.split(';').map(swiftTrim).where((p) => p.isNotEmpty).toList();
    final weights = parts.map((p) => f.parseKeepingAny(p, _config.availableWeights)).whereType<double>().toList();
    if (weights.length != parts.length) {
      _error(model, 'Pesos disponibles inválidos: separalos con punto y coma (ej.: 20; 22,5; 25).');
      return;
    }
    c.availableWeights = weights.isEmpty ? null : weights;
    final updated = exercise.copy()
      ..progression = c
      ..defaultIncrement = c.increment
      ..availableWeights = c.availableWeights
      ..defaultRestSeconds = _rest;
    if (exercise.isCustom) updated.name = _name.text;
    if (model.perform(() {
          model.catalog.updateExercise(updated);
          return true;
        }) !=
        null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Criterios guardados')));
    }
  }

  void _error(AppModel model, String message) {
    model.errorMessage = message;
    model.perform(() {});
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
    final exercise = model.repository.exercise(widget.exerciseId);
    if (exercise == null || !_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.delete_outline, title: 'Ejercicio eliminado'),
      );
    }
    final unit = model.settings.weightUnit.name;
    final hasHistory = model.repository.hasExerciseHistory(widget.exerciseId);
    final hint = TextStyle(color: Theme.of(context).hintColor, fontSize: 12);
    final c = _config;
    Widget info(String label, String value) => ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Flexible(child: Text(value, textAlign: TextAlign.end)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (exercise.isCustom)
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
          info('Medición', exercise.measurement.label),
          info('Equipamiento', exercise.equipment.label),
          info('Carga', exercise.loadMode == LoadMode.perSide ? 'Por lado / por mano' : 'Total'),
          info('Principales', exercise.primaryMuscles.map((m) => m.label).join(', ')),
          if (exercise.secondaryMuscles.isNotEmpty)
            info('Secundarios', exercise.secondaryMuscles.map((m) => m.muscle.label).join(', ')),
          const SectionTitle('Criterios de progresión predeterminados'),
          _stepper('Series: ${c.targetSets}', c.targetSets, 1, 10, (v) => c.targetSets = v),
          if (exercise.measurement == MeasurementType.duration) ...[
            _stepper('Mínimo: ${c.secondsMin} s', c.secondsMin, 5, 600, (v) => c.secondsMin = v, step: 5),
            _stepper('Máximo: ${c.secondsMax} s', c.secondsMax, c.secondsMin, 900, (v) => c.secondsMax = v, step: 5),
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
          if (_hasRIR) _stepper('RIR $_rir', _rir, 0, 5, (v) => _rir = v),
          TextField(
            controller: _increment,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Incremento ($unit)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _initial,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Peso inicial ($unit)', hintText: 'Opcional'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _available,
            decoration: const InputDecoration(labelText: 'Pesos disponibles (ej.: 20; 22,5; 25)'),
          ),
          _stepper(
            'Sesiones al tope antes de subir: ${c.requiredConsecutiveSessions}',
            c.requiredConsecutiveSessions,
            1,
            5,
            (v) => c.requiredConsecutiveSessions = v,
          ),
          _stepper(
            'Reevaluar tras ${c.reassessAfterDays} días',
            c.reassessAfterDays,
            7,
            90,
            (v) => c.reassessAfterDays = v,
            step: 7,
          ),
          _stepper('Descanso: $_rest s', _rest, 15, 600, (v) => _rest = v, step: 15),
          FilledButton(onPressed: () => _save(model, exercise), child: const Text('Guardar criterios')),
          Text('Se aplican en rutinas sin criterios propios. Cambiarlos no modifica sesiones pasadas.', style: hint),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Historial y próxima recomendación'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => ExerciseHistoryScreen(exerciseId: widget.exerciseId))),
          ),
          OutlinedButton(
            onPressed: () => model.perform(() => model.catalog.setArchived(widget.exerciseId, !exercise.isArchived)),
            child: Text(exercise.isArchived ? 'Restaurar' : 'Archivar'),
          ),
          if (!hasHistory)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () async {
                if (await confirm(
                  context,
                  title: '¿Eliminar "${exercise.name}"?',
                  message: 'No tiene historial. También se quita de las rutinas donde aparece.',
                  action: 'Eliminar',
                  destructive: true,
                )) {
                  model.perform(() => model.catalog.deleteExercise(widget.exerciseId));
                  if (context.mounted && model.repository.exercise(widget.exerciseId) == null) Navigator.pop(context);
                }
              },
              child: const Text('Eliminar'),
            )
          else
            Text(
              'Tiene historial: se puede archivar (deja de aparecer en la biblioteca) pero no eliminar.',
              style: hint,
            ),
        ],
      ),
    );
  }
}
