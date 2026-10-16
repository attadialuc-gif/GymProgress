import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../calendar/calendar_screen.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import 'progress_screen.dart';

/// Records (real vs estimated, visually separated) and goals with progress (section 9.6).
class RecordsGoalsScreen extends StatefulWidget {
  const RecordsGoalsScreen({super.key});

  @override
  State<RecordsGoalsScreen> createState() => _RecordsGoalsScreenState();
}

class _RecordsGoalsScreenState extends State<RecordsGoalsScreen> {
  bool _refreshed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_refreshed) return;
    _refreshed = true;
    final model = AppScope.read(context);
    // Marks reached goals as achieved (dated by the record). Quiet: runs while building.
    model.performQuietly(() => model.stats.refreshGoals(now: model.now()));
  }

  static String goalText(Goal goal, LoadFormatter f, DateText dates) {
    final date = goal.targetDate == null ? '' : ' para el ${dates.full(goal.targetDate!)}';
    return switch (goal.metric) {
      GoalMetric.weight => 'Levantar ${f.weight(goal.value)}$date',
      GoalMetric.repsAtWeight => '${goal.value.toInt()} reps con ${f.weight(goal.weight)}$date',
      GoalMetric.estimatedOneRepMax => '1RM estimado de ${f.weight(goal.value)}$date',
      GoalMetric.sessionVolume => 'Volumen de ${f.weight(goal.value)} en una sesión$date',
    };
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final theme = Theme.of(context);
    final f = model.loadFormatter;
    final stats = model.stats;
    final dates = DateText(stats.calendar);
    final goals = stats.goalProgress(now: model.now());
    final ids = model.history.exerciseIdsWithCompletedHistory();
    final exercises = model.repository.exercises().where((e) => ids.contains(e.id)).toList();
    final hint = TextStyle(color: theme.hintColor, fontSize: 12);

    Widget row(String label, String value, {bool estimated = false}) => ListTile(
      dense: true,
      title: Row(
        children: [
          Flexible(child: Text(label)),
          if (estimated) ...[
            const SizedBox(width: 6),
            const GymBadge('Estimación', color: Colors.grey),
            const HelpButton(title: '1RM estimado', text: MetricHelp.oneRepMax),
          ],
        ],
      ),
      trailing: Text(value, style: estimated ? const TextStyle(fontStyle: FontStyle.italic) : null),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Récords y objetivos'),
        actions: [
          IconButton(
            tooltip: 'Nuevo objetivo',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NewGoalScreen())),
          ),
        ],
      ),
      body: ListView(
        children: [
          const SectionTitle('Objetivos'),
          if (goals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Sin objetivos. Agregá uno para seguir tu progreso.',
                style: TextStyle(color: theme.hintColor),
              ),
            ),
          for (final p in goals)
            ListTile(
              title: Row(
                children: [
                  Expanded(child: Text(model.repository.exercise(p.goal.exerciseId)?.name ?? 'Ejercicio')),
                  if (p.achieved) const GymBadge('Logrado', color: GymColors.positive),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(goalText(p.goal, f, dates)),
                  LinearProgressIndicator(value: p.fraction),
                  Text(
                    p.current == null
                        ? 'Todavía sin datos'
                        : 'Actual: ${p.goal.metric == GoalMetric.repsAtWeight ? '${p.current!.toInt()} reps' : f.weight(p.current)}',
                    style: hint,
                  ),
                ],
              ),
              trailing: IconButton(
                tooltip: 'Eliminar objetivo',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, title: '¿Eliminar el objetivo?', action: 'Eliminar', destructive: true)) {
                    model.perform(() => model.repository.deleteGoal(p.goal.id));
                  }
                },
              ),
            ),
          // One section per exercise *and* comparable context: machines/variants never mix.
          for (final e in exercises)
            for (final c in stats.contextClasses(e.id)) ...[
              SectionTitle(c.label == 'estándar' ? e.name : '${e.name} · ${c.label}'),
              if (stats.records(e.id, contextClass: c) case final r) ...[
                if (r.maxWeight != null)
                  row('Peso máximo', '${f.weight(r.maxWeight!.value)} · ${dates.dayMonth(r.maxWeight!.date)}'),
                if (r.maxSessionVolume != null) row('Mayor volumen en una sesión', f.weight(r.maxSessionVolume!.value)),
                for (final x
                    in r.maxRepsAtWeight.length > 3
                        ? r.maxRepsAtWeight.sublist(r.maxRepsAtWeight.length - 3)
                        : r.maxRepsAtWeight)
                  row('Más reps con ${f.weight(x.weight)}', '${x.value.toInt()}'),
                if (r.bestEstimatedOneRepMax != null)
                  row('1RM estimado', f.weight(r.bestEstimatedOneRepMax!.value), estimated: true),
              ],
            ],
        ],
      ),
    );
  }
}

class NewGoalScreen extends StatefulWidget {
  const NewGoalScreen({super.key});

  @override
  State<NewGoalScreen> createState() => _NewGoalScreenState();
}

class _NewGoalScreenState extends State<NewGoalScreen> {
  String? _exerciseId;
  GoalMetric _metric = GoalMetric.weight;
  final _value = TextEditingController();
  final _weight = TextEditingController();
  DateTime? _date;

  @override
  void dispose() {
    _value.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final f = model.loadFormatter;
    final unit = model.settings.weightUnit.name;
    final cal = model.stats.calendar;
    final exercises = model.repository
        .exercises()
        .where((e) => !e.isArchived && e.measurement == MeasurementType.weightReps)
        .toList();
    final value = _metric == GoalMetric.repsAtWeight
        ? WeightParser.parseInt(_value.text)?.toDouble()
        : f.parse(_value.text);
    // Reps-at-weight needs a valid weight, or the goal could never be reached.
    final valid =
        _exerciseId != null &&
        value != null &&
        value > 0 &&
        (_metric != GoalMetric.repsAtWeight || f.parse(_weight.text) != null);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo objetivo'),
        actions: [
          TextButton(
            onPressed: !valid
                ? null
                : () {
                    final goal = Goal(
                      exerciseId: _exerciseId!,
                      metric: _metric,
                      value: value,
                      weight: _metric == GoalMetric.repsAtWeight ? f.parse(_weight.text) : null,
                      targetDate: _date,
                      createdAt: model.now(),
                    );
                    if (model.run(() => model.repository.upsertGoal(goal))) {
                      Navigator.pop(context);
                    }
                  },
            child: const Text('Guardar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _exerciseId,
            decoration: const InputDecoration(labelText: 'Ejercicio'),
            hint: const Text('Elegí…'),
            items: [
              for (final e in exercises)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(e.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _exerciseId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<GoalMetric>(
            isExpanded: true,
            initialValue: _metric,
            decoration: const InputDecoration(labelText: 'Métrica'),
            items: const [
              DropdownMenuItem(value: GoalMetric.weight, child: Text('Peso máximo')),
              DropdownMenuItem(value: GoalMetric.repsAtWeight, child: Text('Repeticiones con un peso')),
              DropdownMenuItem(value: GoalMetric.estimatedOneRepMax, child: Text('1RM estimado')),
              DropdownMenuItem(value: GoalMetric.sessionVolume, child: Text('Volumen en una sesión')),
            ],
            onChanged: (v) => setState(() => _metric = v!),
          ),
          const SizedBox(height: 12),
          if (_metric == GoalMetric.repsAtWeight) ...[
            TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Peso ($unit)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Repeticiones'),
              onChanged: (_) => setState(() {}),
            ),
          ] else
            TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Valor ($unit)'),
              onChanged: (_) => setState(() {}),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fecha objetivo'),
            value: _date != null,
            onChanged: (on) async {
              if (!on) {
                setState(() => _date = null);
                return;
              }
              final d = await pickDay(context, cal, initial: model.now());
              if (d != null) setState(() => _date = d);
            },
          ),
          if (_date != null) Text(DateText(cal).full(_date!)),
        ],
      ),
    );
  }
}
