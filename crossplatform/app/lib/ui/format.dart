import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

/// Presentation of loads in the user's unit. Data is always stored in kg (port of LoadFormatter).
class LoadFormatter {
  const LoadFormatter([this.unit = WeightUnit.kg, this.locale = GymLocale.esAR]);
  final WeightUnit unit;
  final GymLocale locale;

  static const kgPerLb = 0.45359237;

  double value(double kg) => unit == WeightUnit.kg ? kg : kg / kgPerLb;

  String weight(double? kg) => kg == null ? '—' : '${GymFormat.number(value(kg), locale: locale)} ${unit.name}';

  /// Load as the engine describes it (body weight, assistance, per side…), in the user's unit.
  String load(double? kg, MeasurementType measurement, LoadMode loadMode) {
    if (kg == null) return '—';
    if (unit == WeightUnit.kg) return GymFormat.load(kg, measurement, loadMode, locale: locale);
    return GymFormat.load(value(kg), measurement, loadMode, locale: locale).replaceAll(' kg', ' lb');
  }

  /// Parses a typed value in the user's unit (comma or dot) and returns kg.
  double? parse(String text) {
    final v = WeightParser.parse(text);
    if (v == null) return null;
    return unit == WeightUnit.kg ? v : LoadMath.normalized(v * kgPerLb);
  }

  String editable(double? kg) => kg == null ? '' : GymFormat.number(value(kg), locale: locale);
}

const _months = ['ene.', 'feb.', 'mar.', 'abr.', 'may.', 'jun.', 'jul.', 'ago.', 'sept.', 'oct.', 'nov.', 'dic.'];
const _monthsLong = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];
const _weekdays = ['dom.', 'lun.', 'mar.', 'mié.', 'jue.', 'vie.', 'sáb.'];
const _weekdaysLong = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];

/// es-AR date texts in the user's calendar (time zone of the device).
class DateText {
  const DateText(this.calendar);
  final TrainingCalendar calendar;

  /// "15 ene."
  String dayMonth(DateTime d) {
    final l = calendar.local(d);
    return '${l.day} ${_months[l.month - 1]}';
  }

  /// "lun. 15 ene."
  String weekdayDayMonth(DateTime d) => '${_weekdays[calendar.local(d).weekday - 1]} ${dayMonth(d)}';

  /// "lunes"
  String weekdayName(int swiftWeekday) => _weekdaysLong[swiftWeekday - 1];
  String weekdayShort(int swiftWeekday) => _weekdays[swiftWeekday - 1];

  /// "15 ene. 2026"
  String full(DateTime d) => '${dayMonth(d)} ${calendar.local(d).year}';

  /// "enero 2026"
  String monthYear(DateTime d) {
    final l = calendar.local(d);
    return '${_monthsLong[l.month - 1]} ${l.year}';
  }

  /// "18:05"
  String time(DateTime d) {
    final l = calendar.local(d);
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

/// "1:05:09" / "5:09".
String formatDuration(double seconds, {bool hours = true}) {
  final total = seconds.floor();
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return hours ? '$h:${two(m)}:${two(s)}' : '${m + h * 60}:${two(s)}';
}

extension RecommendationLabels on Recommendation {
  /// Short Spanish title for the card.
  String get actionTitle => switch (action) {
    RecommendationAction.needsInitialTarget => targetWeight == null ? 'Datos insuficientes' : 'Objetivo inicial',
    RecommendationAction.increaseWeight =>
      confidence == RecommendationConfidence.conditional ? 'Podrías subir la carga' : 'Subí la carga',
    RecommendationAction.increaseReps => 'Sumá repeticiones',
    RecommendationAction.maintain => 'Mantené la carga',
    RecommendationAction.reassess => 'Reevaluá',
  };

  String get amountsText {
    final seconds = targetSeconds;
    if (seconds != null && seconds.isNotEmpty) return seconds.map((s) => '$s s').join(', ');
    return targetReps.isEmpty ? '—' : GymFormat.list(targetReps);
  }
}

extension DecisionKindLabel on DecisionKind {
  String get label => switch (this) {
    DecisionKind.accepted => 'Aceptada',
    DecisionKind.modified => 'Modificada',
    DecisionKind.ignored => 'Ignorada',
  };
}

extension TrendLabel on TrendClassification {
  String get label => switch (this) {
    TrendClassification.insufficientData => 'Sin datos suficientes (mín. 3 sesiones)',
    TrendClassification.progressing => 'Progresando',
    TrendClassification.stable => 'Estable',
    TrendClassification.possiblePlateau => 'Posible estancamiento',
    TrendClassification.declining => 'En descenso',
  };
}

extension MuscleLabel on MuscleGroup {
  String get label => switch (this) {
    MuscleGroup.chest => 'Pecho',
    MuscleGroup.upperBack => 'Espalda alta',
    MuscleGroup.lats => 'Dorsales',
    MuscleGroup.traps => 'Trapecios',
    MuscleGroup.frontDelts => 'Deltoides anterior',
    MuscleGroup.sideDelts => 'Deltoides lateral',
    MuscleGroup.rearDelts => 'Deltoides posterior',
    MuscleGroup.biceps => 'Bíceps',
    MuscleGroup.triceps => 'Tríceps',
    MuscleGroup.forearms => 'Antebrazos',
    MuscleGroup.quads => 'Cuádriceps',
    MuscleGroup.hamstrings => 'Isquiotibiales',
    MuscleGroup.glutes => 'Glúteos',
    MuscleGroup.calves => 'Gemelos',
    MuscleGroup.adductors => 'Aductores',
    MuscleGroup.abductors => 'Abductores',
    MuscleGroup.abs => 'Abdominales',
    MuscleGroup.obliques => 'Oblicuos',
    MuscleGroup.lowerBack => 'Zona lumbar',
  };
}

extension EquipmentLabel on Equipment {
  String get label => switch (this) {
    Equipment.barbell => 'Barra',
    Equipment.dumbbell => 'Mancuernas',
    Equipment.machine => 'Máquina',
    Equipment.cable => 'Polea',
    Equipment.smithMachine => 'Smith',
    Equipment.kettlebell => 'Kettlebell',
    Equipment.bodyweight => 'Peso corporal',
    Equipment.band => 'Banda',
    Equipment.ezBar => 'Barra Z',
    Equipment.other => 'Otro',
  };
}

extension MeasurementLabel on MeasurementType {
  String get label => switch (this) {
    MeasurementType.weightReps => 'Peso × repeticiones',
    MeasurementType.bodyweightReps => 'Peso corporal × repeticiones',
    MeasurementType.duration => 'Duración',
  };
}

/// Case- and accent-insensitive search (like `localizedStandardContains`).
bool searchMatches(String text, String query) =>
    query.trim().isEmpty || foldDiacritics(text).contains(foldDiacritics(swiftTrim(query)));
