import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

/// Set table: number · load · reps (or seconds) · RIR · state, with last session's value next to
/// each set. Every edit is saved when the field loses focus, on submit, and always right before
/// completing the set (port of SetTable/SetRow).
class SetTable extends StatelessWidget {
  const SetTable({super.key, required this.log, required this.sets, required this.previous, required this.onComplete});
  final ExerciseLog log;
  final List<SetLog> sets;
  final PerformanceSummary? previous;
  final void Function(SetLog set) onComplete;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final theme = Theme.of(context);
    final unit = model.settings.weightUnit.name;
    final loadHeader = switch (log.snapshot.measurement) {
      MeasurementType.bodyweightReps => 'Lastre (+) / asist. (−) $unit',
      _ => log.snapshot.loadMode == LoadMode.perSide ? 'Peso por lado ($unit)' : 'Peso ($unit)',
    };
    final working = sets.where((s) => s.kind != SetKind.warmup).toList();
    return Column(
      spacing: 4,
      children: [
        DefaultTextStyle.merge(
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          child: Row(
            children: [
              const SizedBox(width: 40, child: Text('Serie')),
              Expanded(child: Text(loadHeader)),
              SizedBox(
                width: 72,
                child: Text(
                  log.snapshot.measurement == MeasurementType.duration ? 'Seg.' : 'Reps',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 56, child: Text('RIR', textAlign: TextAlign.center)),
              const SizedBox(width: 48),
            ],
          ),
        ),
        for (var i = 0; i < sets.length; i++)
          SetRow(
            key: ValueKey(sets[i].id),
            log: log,
            entry: sets[i],
            label: sets[i].kind == SetKind.warmup ? 'C' : '${working.indexWhere((s) => s.id == sets[i].id) + 1}',
            previous: _previousText(model.loadFormatter, sets[i]),
            onComplete: () => onComplete(sets[i]),
          ),
      ],
    );
  }

  String? _previousText(LoadFormatter f, SetLog set) {
    final p = previous;
    if (set.kind != SetKind.working || p == null) return null;
    final i = sets.where((s) => s.kind == SetKind.working).toList().indexWhere((s) => s.id == set.id);
    if (i < 0 || i >= p.sets.length) return null;
    return 'Antes: ${f.editable(p.sets[i].load)} × ${p.sets[i].amount}';
  }
}

class SetRow extends StatefulWidget {
  const SetRow({
    super.key,
    required this.log,
    required this.entry,
    required this.label,
    required this.previous,
    required this.onComplete,
  });
  final ExerciseLog log;
  final SetLog entry;
  final String label;
  final String? previous;
  final VoidCallback onComplete;

  @override
  State<SetRow> createState() => SetRowState();
}

class SetRowState extends State<SetRow> with WidgetsBindingObserver {
  final _load = TextEditingController();
  final _amount = TextEditingController();
  final _loadFocus = FocusNode();
  final _amountFocus = FocusNode();
  String? _warning;

  bool get _isDuration => widget.log.snapshot.measurement == MeasurementType.duration;
  bool get _isBodyweight => widget.log.snapshot.measurement == MeasurementType.bodyweightReps;
  bool get _done => widget.entry.status == SetStatus.completed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFocus.addListener(() => _loadFocus.hasFocus ? null : commit());
    _amountFocus.addListener(() => _amountFocus.hasFocus ? null : commit());
  }

  late AppModel _model;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model = AppScope.read(context);
    _sync();
  }

  @override
  void didUpdateWidget(SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the stored set changed (Aceptar, Copiar…): a rejected entry stays visible.
    if (canonicalJson(oldWidget.entry.toJson()) != canonicalJson(widget.entry.toJson())) _sync();
  }

  bool _disposing = false;

  @override
  void dispose() {
    // The row is going away (navigation, tab switch, app teardown): never lose what was typed.
    _disposing = true;
    commit();
    WidgetsBinding.instance.removeObserver(this);
    _load.dispose();
    _amount.dispose();
    _loadFocus.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  /// Closing the window (Windows) saves what was typed.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    commit();
    return AppExitResponse.exit;
  }

  /// Leaving the app (call, lock, app switcher) saves what was typed, even mid-edit.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) commit();
  }

  LoadFormatter get _fmt => _model.loadFormatter;

  double? get _storedLoad {
    final e = widget.entry;
    if (_isBodyweight) return e.addedWeight != null || e.assistance != null ? e.performed.netAddedLoad : null;
    return e.weight;
  }

  int? get _storedAmount => _isDuration ? widget.entry.seconds : widget.entry.reps;

  String _loadDisplay(double? v) {
    if (v == null) return '';
    return _isBodyweight && v < 0 ? '-${_fmt.editable(-v)}' : _fmt.editable(v);
  }

  /// Pulls values written elsewhere ("Aceptar", "Copiar") into the fields. Never writes back.
  void _sync() {
    if (!_loadFocus.hasFocus) _load.text = _loadDisplay(_storedLoad);
    if (!_amountFocus.hasFocus) _amount.text = _storedAmount?.toString() ?? '';
  }

  /// Saves typed text if it differs from what is stored (by its displayed form, so rounding for
  /// display never rewrites a stored value).
  void commit() {
    final model = _model;
    final s = model.repository.setLog(widget.entry.id);
    if (s == null) return;
    String? parseWarning;
    if (_load.text != _loadDisplay(_storedLoad)) {
      final t = swiftTrim(_load.text);
      if (_isBodyweight) {
        final negative = t.startsWith('-') || t.startsWith('−');
        final m = t.isEmpty ? null : _fmt.parse(negative ? t.substring(1) : t);
        if (t.isEmpty) {
          s
            ..addedWeight = null
            ..assistance = null;
        } else if (m != null) {
          s
            ..addedWeight = negative ? null : (m > 0 ? m : null)
            ..assistance = negative ? m : null;
        } else {
          parseWarning = 'Peso inválido: usá coma o punto decimal.';
        }
      } else if (t.isEmpty) {
        s.weight = null;
      } else {
        final v = _fmt.parse(t);
        if (v != null) {
          s.weight = v;
        } else {
          parseWarning = 'Peso inválido: usá coma o punto decimal.';
        }
      }
    }
    if (_amount.text != (_storedAmount?.toString() ?? '')) {
      if (_amount.text.isEmpty) {
        if (_isDuration) {
          s.seconds = null;
        } else {
          s.reps = null;
        }
      } else {
        final v = WeightParser.parseInt(_amount.text);
        if (v != null) {
          if (_isDuration) {
            s.seconds = v;
          } else {
            s.reps = v;
          }
        } else {
          parseWarning = 'Ingresá un número entero.';
        }
      }
    }
    _save(model, s, parseWarning);
  }

  void _save(AppModel model, SetLog s, String? parseWarning) {
    void warn(String? w) {
      if (mounted && !_disposing) setState(() => _warning = w);
    }

    if (canonicalJson(s.toJson()) == canonicalJson(widget.entry.toJson())) {
      warn(parseWarning);
      return;
    }
    final issues = SetValidator.validate(weight: s.weight, reps: s.reps, seconds: s.seconds, rir: s.rir, rpe: s.rpe);
    final unusual = issues.where((i) => !i.isError).map((i) => i.message).firstOrNull;
    // A typing error is shown first; it is never hidden by another field's save.
    warn(parseWarning ?? unusual);
    if (mounted && !_disposing) {
      model.perform(() => model.workout.updateSet(s));
    } else {
      // Row being removed (navigation): save without rebuilding the tree being torn down.
      model.performQuietly(() => model.workout.updateSet(s));
    }
  }

  void _setEffort({double? rir, double? rpe}) {
    final model = _model;
    final s = model.repository.setLog(widget.entry.id);
    if (s == null) return;
    s
      ..rir = rir
      ..rpe = rpe;
    _save(model, s, null);
  }

  String get _effortLabel {
    final e = widget.entry;
    if (e.rir != null) return GymFormat.number(e.rir!);
    if (e.rpe != null) return '@${GymFormat.number(e.rpe!)}';
    return '–';
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final theme = Theme.of(context);
    final e = widget.entry;
    final numberStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final subtitle = [
      if (widget.previous != null) widget.previous!,
      if (e.targetReps != null && !_isDuration) 'Objetivo: ${e.targetReps}',
      if (e.targetSeconds != null && _isDuration) 'Objetivo: ${e.targetSeconds} s',
    ];
    return Opacity(
      opacity: _done ? 0.75 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: GestureDetector(
                    onLongPress: () => _rowMenu(context),
                    child: Text(
                      widget.label,
                      style: numberStyle?.copyWith(color: e.kind == SetKind.warmup ? theme.hintColor : null),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: Key('load-${e.id}'),
                    controller: _load,
                    focusNode: _loadFocus,
                    style: numberStyle,
                    keyboardType: TextInputType.numberWithOptions(decimal: true, signed: _isBodyweight),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: _isBodyweight ? '0' : (_isDuration ? '–' : model.settings.weightUnit.name),
                    ),
                    onSubmitted: (_) => commit(),
                  ).withSemantics('Peso de la serie ${widget.label}'),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child:
                      TextField(
                        key: Key('amount-${e.id}'),
                        controller: _amount,
                        focusNode: _amountFocus,
                        style: numberStyle,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: _isDuration
                              ? (e.targetSeconds?.toString() ?? 's')
                              : (e.targetReps?.toString() ?? 'reps'),
                        ),
                        onSubmitted: (_) => commit(),
                      ).withSemantics(
                        _isDuration
                            ? 'Segundos de la serie ${widget.label}'
                            : 'Repeticiones de la serie ${widget.label}',
                      ),
                ),
                SizedBox(width: 56, child: Center(child: _effortMenu(context))),
                SizedBox(
                  width: 48,
                  child: IconButton(
                    key: Key('complete-${e.id}'),
                    tooltip: _done
                        ? 'Serie ${widget.label} completada; tocá para reabrir'
                        : 'Completar serie ${widget.label}',
                    iconSize: 32,
                    icon: Icon(
                      _done ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: _done ? GymColors.positive : theme.hintColor,
                    ),
                    onPressed: () {
                      if (_done) {
                        model.perform(() => model.workout.reopenSet(e.id));
                      } else {
                        commit();
                        FocusScope.of(context).unfocus();
                        widget.onComplete();
                      }
                    },
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty || _warning != null)
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 2),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final s in subtitle)
                      Text(
                        s,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: s.startsWith('Objetivo') ? theme.colorScheme.primary : theme.hintColor,
                        ),
                      ),
                    if (_warning != null)
                      Text(_warning!, style: theme.textTheme.labelSmall?.copyWith(color: GymColors.caution)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// RIR in one tap (0–10) or RPE (6–10). Optional; feeds the engine's effort check.
  Widget _effortMenu(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Esfuerzo de la serie ${widget.label}: ${_effortLabel == '–' ? 'sin registrar' : _effortLabel}',
    onSelected: (v) {
      if (v == 'none') {
        _setEffort();
      } else if (v.startsWith('rir')) {
        _setEffort(rir: double.parse(v.substring(3)));
      } else {
        _setEffort(rpe: double.parse(v.substring(3)));
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'none', child: Text('Sin registrar')),
      const PopupMenuDivider(),
      for (var i = 0; i <= 10; i++) PopupMenuItem(value: 'rir$i', child: Text('RIR $i')),
      const PopupMenuDivider(),
      for (final v in [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0])
        PopupMenuItem(value: 'rpe$v', child: Text('RPE ${GymFormat.number(v)}')),
    ],
    child: Container(
      width: 48,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_effortLabel),
    ),
  );

  Future<void> _rowMenu(BuildContext context) async {
    final model = AppScope.read(context);
    final e = widget.entry;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(e.kind == SetKind.warmup ? 'Marcar como efectiva' : 'Marcar como calentamiento'),
              onTap: () => Navigator.pop(context, 'kind'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Quitar serie'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'kind') {
      final s = model.repository.setLog(e.id)!..kind = e.kind == SetKind.warmup ? SetKind.working : SetKind.warmup;
      model.perform(() => model.workout.updateSet(s));
    } else if (action == 'remove' &&
        await confirm(context, title: '¿Quitar la serie ${widget.label}?', action: 'Quitar serie', destructive: true)) {
      model.perform(() => model.workout.removeSet(e.id));
    }
  }
}

extension on Widget {
  /// One accessible node: the label and the editable field are announced together.
  Widget withSemantics(String label) => MergeSemantics(
    child: Semantics(label: label, child: this),
  );
}
