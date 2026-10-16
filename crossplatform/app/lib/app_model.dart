import 'package:flutter/widgets.dart';
import 'package:gym_store/gym_store.dart';

import 'ui/format.dart';
import 'services/rest_timer.dart';

enum AppTab { home, routines, workout, progress, profile }

/// Composition root (port of the iOS AppModel). Owns the repository; views read through it and
/// call [perform] for every mutation (saved immediately, then views refresh). No business logic.
class AppModel extends ChangeNotifier {
  AppModel(this.repository, {required this.timeZone, DateTime Function()? clock, this.storeError})
    : _clock = clock ?? DateTime.now;

  final GymRepository repository;

  /// IANA zone of the device, refreshed on resume (travel, DST).
  String timeZone;
  final DateTime Function() _clock;

  /// The persistent store could not be opened: the app blocks logging (nothing would be saved).
  final String? storeError;
  String? errorMessage;
  int revision = 0;
  AppTab selectedTab = AppTab.home;
  final RestTimer restTimer = RestTimer();

  WorkoutService get workout => WorkoutService(repository, timeZone: timeZone);
  RoutineService get routines => RoutineService(repository);
  ExerciseCatalogService get catalog => ExerciseCatalogService(repository);
  HistoryService get history => HistoryService(repository);
  ExportService get exporter => ExportService(repository);
  ConsistencyService get consistency => ConsistencyService(repository, timeZone: timeZone);
  StatsService get stats => StatsService(repository, timeZone: timeZone);

  UserSettings get settings => repository.settings();
  LoadFormatter get loadFormatter => LoadFormatter(settings.weightUnit);

  /// The clock is read only here, at the UI edge; services and the engine receive it injected.
  DateTime now() => _clock().toUtc();

  void selectTab(AppTab tab) {
    selectedTab = tab;
    notifyListeners();
  }

  /// Runs a mutation, surfaces errors in Spanish, refreshes views.
  T? perform<T>(T Function() action) {
    try {
      final result = action();
      revision++;
      notifyListeners();
      return result;
    } on GymStoreError catch (e) {
      errorMessage = message(e);
      revision++;
      notifyListeners();
      return null;
    }
  }

  /// Saves without notifying (widget teardown); the next rebuild shows the change.
  void performQuietly(void Function() action) {
    try {
      action();
      revision++;
    } on GymStoreError catch (e) {
      errorMessage = message(e);
    }
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  /// Idempotent: inserts the bundled library and refreshes catalog fields.
  void seedCatalog() => perform(() => catalog.seed(ExerciseCatalog.bundled()));

  static String message(GymStoreError e) => switch (e.kind) {
    GymStoreErrorKind.notFound => (e.message ?? '').contains(' ') ? e.message! : 'No se encontró el elemento.',
    GymStoreErrorKind.sessionAlreadyOpen =>
      'Ya hay un entrenamiento en curso. Terminalo o descartalo antes de empezar otro.',
    GymStoreErrorKind.sessionNotOpen => 'El entrenamiento ya no está en curso.',
    GymStoreErrorKind.hasHistory => 'Tiene historial: no se puede borrar, pero podés archivarlo.',
    GymStoreErrorKind.hasCompletedSets => 'Este ejercicio ya tiene series completadas en la sesión.',
    GymStoreErrorKind.missingValues => 'Completá peso y repeticiones antes de marcar la serie.',
    GymStoreErrorKind.invalidValue => e.message ?? 'Valor inválido.',
    GymStoreErrorKind.unsupportedSchemaVersion =>
      'La copia es de una versión más nueva de la app (esquema ${e.message}).',
    GymStoreErrorKind.invalidImport => e.message ?? 'El archivo no es una copia válida de GymProgress.',
    GymStoreErrorKind.storage => 'Error al guardar: ${e.message}',
  };
}

/// Gives every screen access to the [AppModel] and rebuilds dependents on change.
class AppScope extends InheritedNotifier<AppModel> {
  const AppScope({super.key, required AppModel model, required super.child}) : super(notifier: model);

  static AppModel of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Without subscribing (for callbacks).
  static AppModel read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
