import 'package:flutter/material.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

import '../app_model.dart';
import '../ui/format.dart';
import '../ui/theme.dart';

/// Picks a calendar day and returns its start in the user's calendar (time zone of the app).
Future<DateTime?> pickDay(
  BuildContext context,
  TrainingCalendar cal, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
}) async {
  LocalDateTime l(DateTime d) => cal.local(d);
  final i = l(initial);
  final f = first == null ? null : l(first);
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime(i.year, i.month, i.day),
    firstDate: f == null ? DateTime(2000) : DateTime(f.year, f.month, f.day),
    lastDate: last == null ? DateTime(2100) : DateTime(l(last).year, l(last).month, l(last).day),
    locale: const Locale('es', 'AR'),
  );
  return picked == null ? null : cal.instant(picked.year, picked.month, picked.day);
}

/// Monthly / weekly calendar: completed, planned, missed and rest days (section 9.5).
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime? _anchor;
  bool _weekly = false;

  static const _veryShort = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final theme = Theme.of(context);
    final now = model.now();
    final anchor = _anchor ?? now;
    final cal = model.consistency.calendar;
    final dates = DateText(cal);
    final days = _weekly ? model.consistency.week(anchor, now: now) : model.consistency.month(anchor, now: now);
    final ordered = [for (var i = 0; i < 7; i++) (cal.firstWeekday - 1 + i) % 7 + 1];
    final blanks = _weekly || days.isEmpty ? 0 : (cal.weekday(days.first.date) - cal.firstWeekday + 7) % 7;
    final plan = model.consistency.plan(now);
    final title = _weekly ? 'Semana del ${dates.dayMonth(cal.weekStart(anchor))}' : dates.monthYear(anchor);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendario')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Mes')),
              ButtonSegment(value: true, label: Text('Semana')),
            ],
            selected: {_weekly},
            onSelectionChanged: (v) => setState(() => _weekly = v.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: 'Anterior',
                onPressed: () =>
                    setState(() => _anchor = _weekly ? cal.addDays(-7, anchor) : cal.addMonths(-1, anchor)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'Siguiente',
                onPressed: () => setState(() => _anchor = _weekly ? cal.addDays(7, anchor) : cal.addMonths(1, anchor)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (final w in ordered)
                Expanded(
                  child: Text(
                    _veryShort[w - 1],
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.hintColor, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (var i = 0; i < blanks; i++) const SizedBox.shrink(),
              for (final d in days) _DayCell(day: d, dayNumber: cal.local(d.date).day, dates: dates),
            ],
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _LegendDot(color: GymColors.accent, text: 'Hecho'),
              _LegendDot(color: Colors.blue, text: 'Planificado'),
              _LegendDot(color: GymColors.caution, text: 'Omitido'),
              _LegendDot(color: Colors.grey, text: 'Descanso'),
            ],
          ),
          const SizedBox(height: 16),
          GymCard(
            children: [
              Text('Plan semanal vigente', style: theme.textTheme.titleMedium),
              if (plan.isEmpty) Text('Sin días planificados.', style: TextStyle(color: theme.hintColor)),
              for (final w in ordered)
                if (plan[w] != null && model.repository.routine(plan[w]!) != null)
                  Row(
                    children: [
                      Expanded(child: Text(_capitalize(dates.weekdayName(w)))),
                      Text(model.repository.routine(plan[w]!)!.name, style: TextStyle(color: theme.hintColor)),
                    ],
                  ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeeklyPlanEditor())),
                child: const Text('Editar plan'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.dayNumber, required this.dates});
  final CalendarDay day;
  final int dayNumber;
  final DateText dates;

  Color get _color => switch (day.status) {
    CalendarDayStatus.completed => GymColors.accent,
    CalendarDayStatus.planned => Colors.blue,
    CalendarDayStatus.missed => GymColors.caution,
    CalendarDayStatus.rest => Colors.grey.withValues(alpha: 0.4),
  };

  String get _status => switch (day.status) {
    CalendarDayStatus.completed => 'entrenamiento hecho',
    CalendarDayStatus.planned => 'planificado${day.plannedRoutineName == null ? '' : ': ${day.plannedRoutineName}'}',
    CalendarDayStatus.missed => 'planificado y omitido',
    CalendarDayStatus.rest => 'descanso',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${dates.weekdayDayMonth(day.date)}: $_status',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: day.isToday ? theme.colorScheme.primary.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$dayNumber', style: TextStyle(fontWeight: day.isToday ? FontWeight.bold : FontWeight.normal)),
            const SizedBox(height: 2),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 12)),
    ],
  );
}

/// Choose training days and the routine for each. Changes apply from the chosen date; the past
/// keeps the plan it had (validFrom).
class WeeklyPlanEditor extends StatefulWidget {
  const WeeklyPlanEditor({super.key});

  @override
  State<WeeklyPlanEditor> createState() => _WeeklyPlanEditorState();
}

class _WeeklyPlanEditorState extends State<WeeklyPlanEditor> {
  Map<int, String>? _assignments;
  DateTime? _from;

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final cal = model.consistency.calendar;
    final dates = DateText(cal);
    final now = model.now();
    final assignments = _assignments ??= Map.of(model.consistency.plan(now));
    final from = _from ?? cal.day(now);
    final routines = model.repository.routines().where((r) => !r.isArchived).toList();
    final ordered = [for (var i = 0; i < 7; i++) (cal.firstWeekday - 1 + i) % 7 + 1];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan semanal'),
        actions: [
          TextButton(
            onPressed: () {
              if (model.run(() => model.consistency.setWeeklyPlan(assignments, from: from, now: model.now()))) {
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
          for (final w in ordered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: assignments[w],
                decoration: InputDecoration(labelText: _capitalize(dates.weekdayName(w))),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Descanso')),
                  for (final r in routines)
                    DropdownMenuItem<String?>(
                      value: r.id,
                      child: Text(r.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => v == null ? assignments.remove(w) : assignments[w] = v),
              ),
            ),
          Text('${assignments.length} días por semana.', style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vigente desde'),
            subtitle: Text(dates.full(from)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              // Only today or later: the past keeps the plan it had.
              final picked = await pickDay(context, cal, initial: from, first: cal.day(model.now()));
              if (picked != null) setState(() => _from = picked);
            },
          ),
          Text(
            'Los días anteriores conservan el plan que tenían: el historial de planificados y omitidos no cambia.',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
