import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';

import '../app_model.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

/// Library search (bundled catalog + custom exercises). Pops the chosen [Exercise].
class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key});

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  String _query = '';
  MuscleGroup? _muscle;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final filtered = model.repository.exercises().where((e) {
      if (e.isArchived) return false;
      if (!searchMatches(e.name, _query)) return false;
      final m = _muscle;
      return m == null || e.primaryMuscles.contains(m) || e.secondaryMuscles.any((s) => s.muscle == m);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const Key('exerciseSearch'),
              autofocus: false,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar ejercicio'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Crear ejercicio personalizado'),
            onTap: () async {
              final created = await Navigator.of(context)
                  .push<Exercise>(MaterialPageRoute(builder: (_) => const CustomExerciseForm()));
              if (created != null && context.mounted) Navigator.pop(context, created);
            },
          ),
          SectionTitle('${filtered.length} ejercicios'),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final e = filtered[i];
                return ListTile(
                  title: Row(
                    children: [
                      Flexible(child: Text(e.name)),
                      if (e.isCustom) ...[const SizedBox(width: 6), const GymBadge('Propio')],
                    ],
                  ),
                  subtitle: Text('${e.equipment.label} · ${e.primaryMuscles.map((m) => m.label).join(', ')}'),
                  onTap: () => Navigator.pop(context, e),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CustomExerciseForm extends StatefulWidget {
  const CustomExerciseForm({super.key});

  @override
  State<CustomExerciseForm> createState() => _CustomExerciseFormState();
}

class _CustomExerciseFormState extends State<CustomExerciseForm> {
  final _name = TextEditingController();
  final _increment = TextEditingController(text: '2,5');
  MeasurementType _measurement = MeasurementType.weightReps;
  Equipment _equipment = Equipment.machine;
  bool _perSide = false;
  final Set<MuscleGroup> _primary = {};
  final Set<MuscleGroup> _secondary = {};

  @override
  void dispose() {
    _name.dispose();
    _increment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final canCreate = swiftTrim(_name.text).isNotEmpty && _primary.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo ejercicio'),
        actions: [
          TextButton(
            onPressed: !canCreate
                ? null
                : () {
                    final increment = model.loadFormatter.parse(_increment.text) ?? 2.5;
                    final created = model.perform(
                      () => model.catalog.createCustomExercise(
                        name: _name.text,
                        measurement: _measurement,
                        equipment: _equipment,
                        loadMode: _perSide ? LoadMode.perSide : LoadMode.total,
                        primaryMuscles: MuscleGroup.values.where(_primary.contains).toList(),
                        secondaryMuscles: MuscleGroup.values
                            .where((m) => _secondary.contains(m) && !_primary.contains(m))
                            .map((m) => MuscleInvolvement(m))
                            .toList(),
                        increment: increment,
                      ),
                    );
                    if (created != null) Navigator.pop(context, created);
                  },
            child: const Text('Crear'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MeasurementType>(
            isExpanded: true,
            initialValue: _measurement,
            decoration: const InputDecoration(labelText: 'Medición'),
            items: [for (final m in MeasurementType.values) DropdownMenuItem(value: m, child: Text(m.label))],
            onChanged: (v) => setState(() => _measurement = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Equipment>(
            isExpanded: true,
            initialValue: _equipment,
            decoration: const InputDecoration(labelText: 'Equipamiento'),
            items: [for (final e in Equipment.values) DropdownMenuItem(value: e, child: Text(e.label))],
            onChanged: (v) => setState(() => _equipment = v!),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Peso por lado / por mano'),
            value: _perSide,
            onChanged: (v) => setState(() => _perSide = v),
          ),
          TextField(
            controller: _increment,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Incremento (${model.settings.weightUnit.name})'),
          ),
          const SectionTitle('Músculos principales'),
          _MuscleChips(selection: _primary, onChanged: () => setState(() {})),
          const SectionTitle('Músculos secundarios'),
          _MuscleChips(selection: _secondary, onChanged: () => setState(() {})),
        ],
      ),
    );
  }
}

class _MuscleChips extends StatelessWidget {
  const _MuscleChips({required this.selection, required this.onChanged});
  final Set<MuscleGroup> selection;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final m in MuscleGroup.values)
        FilterChip(
          label: Text(m.label),
          selected: selection.contains(m),
          onSelected: (on) {
            on ? selection.add(m) : selection.remove(m);
            onChanged();
          },
        ),
    ],
  );
}
