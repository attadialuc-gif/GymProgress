import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../ui/format.dart';
import '../ui/theme.dart';

/// Section 2.A: the most prominent element of the exercise screen, above the set table.
/// It only presents what the engine returned (no business logic here).
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.recommendation,
    required this.decision,
    required this.formatter,
    required this.dates,
    required this.onAccept,
    required this.onModify,
    required this.onIgnore,
    required this.onCopyPrevious,
    required this.onSetInitialTarget,
  });

  final Recommendation recommendation;
  final RecommendationDecision? decision;
  final LoadFormatter formatter;
  final DateText dates;
  final VoidCallback onAccept;
  final VoidCallback onModify;
  final VoidCallback onIgnore;

  /// Parameter: copy from a non-equivalent context (explicit choice).
  final void Function(bool nonEquivalent) onCopyPrevious;
  final VoidCallback onSetInitialTarget;

  IconData get _icon => switch (recommendation.action) {
    RecommendationAction.needsInitialTarget => Icons.help_outline,
    RecommendationAction.increaseWeight => Icons.arrow_circle_up,
    RecommendationAction.increaseReps => Icons.add_circle,
    RecommendationAction.maintain => Icons.drag_handle,
    RecommendationAction.reassess => Icons.warning_amber_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = recommendation;
    final hint = theme.hintColor;
    return Semantics(
      container: true,
      label: 'Recomendación',
      child: GymCard(
        highlighted: decision == null,
        children: [
          // Header: the action title always has the full width; badges go below it.
          Row(
            children: [
              Icon(_icon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.actionTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (r.confidence == RecommendationConfidence.conditional || decision != null)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (r.confidence == RecommendationConfidence.conditional)
                  const GymBadge('Condicionada', color: GymColors.caution),
                if (decision != null) GymBadge(decision!.kind.label, color: GymColors.positive),
              ],
            ),
          // Last comparable session
          if (r.lastPerformance != null)
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Última sesión · ${dates.dayMonth(r.lastPerformance!.date)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: hint),
                  ),
                  Text(
                    '${formatter.load(r.lastPerformance!.workingLoad, r.lastPerformance!.measurement, r.lastPerformance!.context.loadMode)} × ${GymFormat.list(r.lastPerformance!.amounts)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (r.lastPerformance!.sets.any((s) => s.rir != null))
                    Text(
                      'RIR: ${r.lastPerformance!.sets.map((s) => s.rir == null ? '–' : GymFormat.number(s.rir!)).join(', ')}',
                      style: theme.textTheme.bodySmall?.copyWith(color: hint),
                    ),
                ],
              ),
            )
          else
            Text('Sin sesión anterior comparable', style: theme.textTheme.bodyMedium?.copyWith(color: hint)),
          const Divider(height: 1),
          Text(_targetText, style: theme.textTheme.bodyMedium?.copyWith(color: hint)),
          if (r.targetWeight != null || r.targetReps.isNotEmpty || r.targetSeconds != null)
            Semantics(
              label:
                  'Recomendado: ${formatter.load(r.targetWeight, r.measurement, r.context.loadMode)}, ${r.amountsText}',
              excludeSemantics: true,
              child: Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  BigNumber(formatter.load(r.targetWeight, r.measurement, r.context.loadMode), caption: 'Recomendado'),
                  BigNumber(
                    r.amountsText,
                    caption: r.measurement == MeasurementType.duration ? 'Segundos' : 'Repeticiones',
                  ),
                ],
              ),
            ),
          Text(r.reasonText, style: theme.textTheme.bodyMedium),
          for (final c in r.conditions) _Note(icon: Icons.info_outline, text: c, color: GymColors.caution),
          for (final n in r.notes) _Note(icon: Icons.lightbulb_outline, text: n, color: hint),
          if (r.nonEquivalentReference != null)
            _Note(
              icon: Icons.call_split,
              color: hint,
              text:
                  'Referencia no equivalente (otro contexto): ${formatter.load(r.nonEquivalentReference!.workingLoad, r.nonEquivalentReference!.measurement, r.nonEquivalentReference!.context.loadMode)} × ${GymFormat.list(r.nonEquivalentReference!.amounts)}',
            ),
          _buttons(context),
        ],
      ),
    );
  }

  String get _targetText {
    final t = recommendation.target;
    final range = recommendation.measurement == MeasurementType.duration
        ? '${t.secondsMin}–${t.secondsMax} s'
        : '${t.repMin}–${t.repMax}';
    final rir = t.targetRIR == null ? '' : ' · RIR ${t.targetRIR}';
    return 'Objetivo de hoy: ${t.sets} × $range$rir';
  }

  Widget _buttons(BuildContext context) {
    final r = recommendation;
    final needsTarget = r.action == RecommendationAction.needsInitialTarget && r.targetWeight == null;
    final buttons = needsTarget
        ? [
            FilledButton(onPressed: onSetInitialTarget, child: const Text('Definir objetivo inicial')),
            OutlinedButton(onPressed: onIgnore, child: const Text('Ignorar')),
          ]
        : [
            Tooltip(
              message: 'Precarga el peso recomendado en las series',
              child: FilledButton(onPressed: onAccept, child: const Text('Aceptar')),
            ),
            Tooltip(
              message: 'Ajustá peso y repeticiones objetivo de hoy',
              child: OutlinedButton(onPressed: onModify, child: const Text('Modificar')),
            ),
            Tooltip(
              message: 'No precarga nada',
              child: OutlinedButton(onPressed: onIgnore, child: const Text('Ignorar')),
            ),
          ];
    final showCopy = decision?.kind == DecisionKind.ignored || r.action == RecommendationAction.needsInitialTarget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: buttons),
        if (showCopy && r.lastPerformance != null)
          TextButton.icon(
            onPressed: () => onCopyPrevious(false),
            icon: const Icon(Icons.copy),
            label: const Text('Copiar cargas anteriores'),
          )
        else if (showCopy && r.nonEquivalentReference != null)
          // Explicit and labeled: the loads come from another machine/variant.
          TextButton.icon(
            onPressed: () => onCopyPrevious(true),
            icon: const Icon(Icons.copy),
            label: const Text('Copiar cargas de otro contexto (no equivalente)'),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
      ),
    ],
  );
}

/// Editor for "Modificar" (and for the initial target): weight typed with comma or dot or nudged
/// with ± by the exercise increment; reps/seconds per set with steppers.
class ModifySheet extends StatefulWidget {
  const ModifySheet({
    super.key,
    required this.recommendation,
    required this.increment,
    required this.formatter,
    required this.title,
    required this.onSave,
  });

  final Recommendation recommendation;
  final double increment;
  final LoadFormatter formatter;
  final String title;
  final void Function(double? weight, List<int> reps, List<int>? seconds) onSave;

  @override
  State<ModifySheet> createState() => _ModifySheetState();
}

class _ModifySheetState extends State<ModifySheet> {
  final _weight = TextEditingController();
  late List<int> _amounts;

  bool get _isDuration => widget.recommendation.measurement == MeasurementType.duration;
  bool get _isBodyweight => widget.recommendation.measurement == MeasurementType.bodyweightReps;

  /// Same bounds as iOS: 0…100 reps, 0…3600 s.
  int get _max => _isDuration ? 3600 : 100;
  int get _step => _isDuration ? 5 : 1;

  @override
  void initState() {
    super.initState();
    final r = widget.recommendation;
    // Start from the recommendation, else the last comparable load; never invent a number.
    final start = r.targetWeight ?? r.lastPerformance?.workingLoad;
    if (start != null && !(_isDuration && LoadMath.key(start) == 0)) _show(start);
    final base = _isDuration ? (r.targetSeconds ?? const <int>[]) : r.targetReps;
    _amounts = base.isEmpty
        ? List.filled(r.target.sets, _isDuration ? r.target.secondsMin : r.target.repMin)
        : List.of(base);
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  /// Last value written into the field by the app (prefill or ±): returned as is while the text
  /// is unchanged, so lb display rounding never alters the kg value.
  double? _shownKg;
  String? _shownText;

  void _show(double kg) {
    _shownKg = kg;
    _shownText = _display(kg);
    _weight.text = _shownText!;
  }

  String _display(double kg) =>
      _isBodyweight && kg < 0 ? '-${widget.formatter.editable(-kg)}' : widget.formatter.editable(kg);

  /// Parsed weight in kg. Body weight accepts a leading "-" for assistance. Empty = no load.
  double? get _parsed {
    final t = swiftTrim(_weight.text);
    if (t.isEmpty) return null;
    if (_shownKg != null && t == _shownText) return _shownKg;
    final negative = _isBodyweight && (t.startsWith('-') || t.startsWith('−'));
    final m = widget.formatter.parse(negative ? t.substring(1) : t);
    if (m == null) return null;
    return negative ? -m : m;
  }

  bool get _invalid => swiftTrim(_weight.text).isNotEmpty && _parsed == null;

  void _nudge(double delta) {
    final current = _parsed ?? 0;
    final floor = _isBodyweight ? -500.0 : 0.0;
    final next = LoadMath.normalized(current + delta);
    setState(() => _show(next < floor ? floor : next));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.formatter;
    final r = widget.recommendation;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              Text(_isBodyweight ? 'Lastre (+) o asistencia (−)' : 'Peso objetivo', style: theme.textTheme.labelLarge),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Restar ${f.weight(widget.increment)}',
                    onPressed: () => _nudge(-widget.increment),
                    icon: const Icon(Icons.remove),
                  ),
                  Expanded(
                    child: MergeSemantics(
                      child: Semantics(
                        label: _isBodyweight ? 'Lastre o asistencia objetivo' : 'Peso objetivo',
                        child: TextField(
                          key: const Key('modifyWeight'),
                          controller: _weight,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.numberWithOptions(decimal: true, signed: _isBodyweight),
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: _isDuration ? 'Sin carga' : f.unit.name,
                            errorText: _invalid ? 'Número inválido. Usá coma o punto decimal (ej.: 61,5).' : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Sumar ${f.weight(widget.increment)}',
                    onPressed: () => _nudge(widget.increment),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              Text(
                _isDuration
                    ? 'Opcional: dejalo vacío si no usás carga.'
                    : 'Podés escribir cualquier valor o usar ± ${f.weight(widget.increment)}.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              Text(_isDuration ? 'Segundos por serie' : 'Repeticiones por serie', style: theme.textTheme.labelLarge),
              for (var i = 0; i < _amounts.length; i++)
                Row(
                  children: [
                    Expanded(child: Text('Serie ${i + 1}: ${_amounts[i]}${_isDuration ? ' s' : ''}')),
                    IconButton(
                      tooltip: 'Menos en la serie ${i + 1}',
                      onPressed: _amounts[i] > 0
                          ? () => setState(() => _amounts[i] = (_amounts[i] - _step).clamp(0, _max))
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Más en la serie ${i + 1}',
                      onPressed: _amounts[i] < _max
                          ? () => setState(() => _amounts[i] = (_amounts[i] + _step).clamp(0, _max))
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => setState(
                      () => _amounts.add(
                        _amounts.isNotEmpty ? _amounts.last : (_isDuration ? r.target.secondsMin : r.target.repMin),
                      ),
                    ),
                    child: const Text('Agregar serie'),
                  ),
                  if (_amounts.length > 1)
                    TextButton(
                      onPressed: () => setState(() => _amounts.removeLast()),
                      child: const Text('Quitar serie'),
                    ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                  FilledButton(
                    key: const Key('modifySave'),
                    onPressed: _invalid || _amounts.isEmpty
                        ? null
                        : () {
                            if (_isDuration) {
                              widget.onSave(_parsed, const [], List.of(_amounts));
                            } else {
                              widget.onSave(_parsed, List.of(_amounts), null);
                            }
                            Navigator.pop(context);
                          },
                    child: const Text('Usar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
