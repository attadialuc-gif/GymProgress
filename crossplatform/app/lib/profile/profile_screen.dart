import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../ui/theme.dart';

/// Profile and settings (section 9.7), export / import / backup (section 12).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _bodyweight = TextEditingController();
  final _bodyweightFocus = FocusNode();
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final model = AppScope.read(context);
    _bodyweight.text = model.loadFormatter.editable(model.settings.bodyweightKg);
    _bodyweightFocus.addListener(() {
      if (!_bodyweightFocus.hasFocus) _saveBodyweight();
    });
  }

  @override
  void dispose() {
    _bodyweight.dispose();
    _bodyweightFocus.dispose();
    super.dispose();
  }

  void _save(void Function(UserSettings s) change) {
    final model = AppScope.read(context);
    final s = model.settings;
    change(s);
    model.perform(() => model.repository.saveSettings(s));
  }

  void _saveBodyweight() {
    if (!mounted) return;
    final model = AppScope.read(context);
    final t = swiftTrim(_bodyweight.text);
    double? value;
    if (t.isNotEmpty) {
      value = model.loadFormatter.parseKeeping(t, model.settings.bodyweightKg);
      if (value == null || value <= 0) {
        model.errorMessage = 'Peso corporal inválido: usá coma o punto decimal (ej.: 78,5).';
        model.perform(() {});
        return;
      }
    }
    if (value == model.settings.bodyweightKg) return;
    _save((s) => s.bodyweightKg = value);
  }

  String _stamp(AppModel model) {
    final l = model.consistency.calendar.local(model.now());
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }

  Future<void> _export(AppModel model, {required bool csv}) async {
    final content = csv
        ? model.perform(model.exporter.exportSetsCsv)
        : model.perform(() => model.exporter.exportJson(now: model.now()));
    if (content == null) return;
    final name = csv ? 'GymProgress-series-${_stamp(model)}.csv' : 'GymProgress-${_stamp(model)}.json';
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: csv ? 'Guardar series (CSV)' : 'Guardar copia (JSON)',
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: csv ? 'text/csv' : 'application/json',
        type: FileType.custom,
        allowedExtensions: [csv ? 'csv' : 'json'],
      );
      if (!mounted || saved == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Guardado: $name')));
    } catch (e) {
      model.errorMessage = 'No se pudo guardar el archivo: $e';
      model.perform(() {});
    }
  }

  Future<void> _import(AppModel model) async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Importar copia de GymProgress',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null || !mounted) return;
      final String text;
      try {
        text = utf8.decode(await file.readAsBytes());
      } catch (_) {
        model.errorMessage = 'No se pudo leer el archivo.';
        model.perform(() {});
        return;
      }
      final summary = model.perform(() => model.exporter.importJson(text));
      if (summary == null || !mounted) return;
      var message = 'Se agregaron ${summary.inserted} registros. ${summary.unchanged} ya estaban.';
      if (summary.conflicts > 0) {
        message += ' ${summary.conflicts} registros del archivo eran distintos a los tuyos: se conservaron los tuyos.';
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importación'),
          content: Text(message),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      model.errorMessage = 'No se pudo abrir el archivo: $e';
      model.perform(() {});
    }
  }

  Widget _stepper(String label, int value, int min, int max, void Function(UserSettings, int) set, {int step = 1}) =>
      ListTile(
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Menos',
              onPressed: value - step >= min ? () => _save((s) => set(s, value - step)) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            IconButton(
              tooltip: 'Más',
              onPressed: value + step <= max ? () => _save((s) => set(s, value + step)) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final s = model.settings;
    final theme = Theme.of(context);
    final hint = TextStyle(color: theme.hintColor, fontSize: 12);
    Widget footer(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(text, style: hint),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        children: [
          const SectionTitle('Preferencias'),
          ListTile(
            title: const Text('Unidad de peso'),
            subtitle: SegmentedButton<WeightUnit>(
              segments: const [
                ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
                ButtonSegment(value: WeightUnit.lb, label: Text('lb')),
              ],
              selected: {s.weightUnit},
              onSelectionChanged: (v) {
                _save((x) => x.weightUnit = v.first);
                _bodyweight.text = model.loadFormatter.editable(model.settings.bodyweightKg);
              },
            ),
          ),
          ListTile(
            title: const Text('La semana empieza'),
            subtitle: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('Lunes')),
                ButtonSegment(value: 1, label: Text('Domingo')),
              ],
              selected: {s.firstWeekday},
              onSelectionChanged: (v) => _save((x) => x.firstWeekday = v.first),
            ),
          ),
          _stepper(
            'Descanso por defecto: ${s.defaultRestSeconds} s',
            s.defaultRestSeconds,
            15,
            600,
            (x, v) => x.defaultRestSeconds = v,
            step: 15,
          ),
          ListTile(
            title: const Text('Tema'),
            subtitle: DropdownButton<AppTheme>(
              value: s.theme,
              onChanged: (v) => _save((x) => x.theme = v!),
              items: const [
                DropdownMenuItem(value: AppTheme.dark, child: Text('Oscuro')),
                DropdownMenuItem(value: AppTheme.light, child: Text('Claro')),
                DropdownMenuItem(value: AppTheme.system, child: Text('Sistema')),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Mantener pantalla encendida en sesión'),
            value: s.keepScreenOn,
            onChanged: (v) => _save((x) => x.keepScreenOn = v),
          ),
          SwitchListTile(
            title: const Text('Aviso al terminar el descanso'),
            value: s.restNotifications,
            onChanged: (v) => _save((x) => x.restNotifications = v),
          ),
          if (s.restNotifications && (model.platform?.supportsExactAlarmSetting ?? false))
            ListTile(
              leading: const Icon(Icons.alarm),
              title: const Text('Permitir avisos puntuales'),
              subtitle: const Text('Sin este permiso del sistema el aviso puede llegar unos segundos tarde.'),
              onTap: () => model.platform?.requestExactAlarms(),
            ),
          const SectionTitle('Constancia'),
          _stepper('Objetivo semanal: ${s.weeklyGoal} entrenamientos', s.weeklyGoal, 1, 14, (x, v) => x.weeklyGoal = v),
          ListTile(
            title: const Text('Racha'),
            subtitle: DropdownButton<StreakMode>(
              value: s.streakMode,
              onChanged: (v) => _save((x) => x.streakMode = v!),
              items: const [
                DropdownMenuItem(value: StreakMode.weeklyPlan, child: Text('Por cumplimiento del plan')),
                DropdownMenuItem(value: StreakMode.dayGap, child: Text('Por días de entrenamiento')),
              ],
            ),
          ),
          if (s.streakMode == StreakMode.dayGap)
            _stepper(
              'Máximo entre entrenamientos: ${s.maxGapDays} días',
              s.maxGapDays,
              1,
              7,
              (x, v) => x.maxGapDays = v,
            ),
          _stepper(
            'Sesión válida: ≥ ${s.minSetsForValidSession} series efectivas',
            s.minSetsForValidSession,
            1,
            20,
            (x, v) => x.minSetsForValidSession = v,
          ),
          footer(model.consistency.streak(model.now()).definition),
          const SectionTitle('Cálculos'),
          ListTile(
            title: const Text('Fórmula de 1RM'),
            subtitle: SegmentedButton<OneRepMaxFormula>(
              segments: const [
                ButtonSegment(value: OneRepMaxFormula.epley, label: Text('Epley')),
                ButtonSegment(value: OneRepMaxFormula.brzycki, label: Text('Brzycki')),
              ],
              selected: {s.oneRepMax.formula},
              onSelectionChanged: (v) =>
                  _save((x) => x.oneRepMax = OneRepMaxSettings(formula: v.first, maxReps: x.oneRepMax.maxReps)),
            ),
          ),
          _stepper(
            'Usar series de hasta ${s.oneRepMax.maxReps} reps',
            s.oneRepMax.maxReps,
            1,
            20,
            (x, v) => x.oneRepMax = OneRepMaxSettings(formula: x.oneRepMax.formula, maxReps: v),
          ),
          ListTile(
            title: Text('Factor de series indirectas: ${GymFormat.number(s.indirectSetFactor)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Menos',
                  onPressed: s.indirectSetFactor > 0.05
                      ? () => _save((x) => x.indirectSetFactor = LoadMath.normalized(x.indirectSetFactor - 0.1))
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  tooltip: 'Más',
                  onPressed: s.indirectSetFactor < 0.95
                      ? () => _save((x) => x.indirectSetFactor = LoadMath.normalized(x.indirectSetFactor + 0.1))
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _bodyweight,
              focusNode: _bodyweightFocus,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Peso corporal (${s.weightUnit.name})', hintText: 'Opcional'),
              onSubmitted: (_) => _saveBodyweight(),
            ),
          ),
          footer(
            'El 1RM es siempre una estimación. El peso corporal solo se usa para el volumen de ejercicios con peso corporal; si no lo cargás, se cuenta solo la carga externa.',
          ),
          const SectionTitle('Datos y copias de seguridad'),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Exportar copia completa (JSON)'),
            onTap: () => _export(model, csv: false),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Exportar series (CSV)'),
            onTap: () => _export(model, csv: true),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Importar / restaurar copia…'),
            onTap: () => _import(model),
          ),
          footer(
            'Tus datos viven solo en este dispositivo. La copia incluye entrenamientos, decisiones sobre recomendaciones y vínculos de equivalencia, '
            'y es compatible con la app de iPhone. Importar solo agrega lo que no existe: nunca reemplaza ni borra lo que ya tenés.',
          ),
          const SectionTitle('Acerca de'),
          footer(
            'GymProgress 1.0.0. Las recomendaciones son orientativas, se basan solo en tus registros y no constituyen consejo médico. '
            'Sin conexión, sin cuentas y sin analíticas.',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
