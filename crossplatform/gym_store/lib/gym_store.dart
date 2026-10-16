/// GymProgress persistence and application services (port of the Swift `GymStore` target):
/// SQLite repository, workout flow with persisted recommendation decisions, routines, catalog,
/// history, calendar/consistency, statistics and JSON/CSV exchange compatible with iOS.
library;

export 'src/catalog.dart';
export 'src/consistency_service.dart';
export 'src/export_service.dart';
export 'src/history_service.dart';
export 'src/records.dart';
export 'src/repository.dart';
export 'src/routine_service.dart';
export 'src/sqlite_repository.dart';
export 'src/stats_service.dart';
export 'src/workout_service.dart';
