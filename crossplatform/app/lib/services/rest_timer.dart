import 'package:flutter/foundation.dart';

/// Rest countdown kept as an end timestamp (port of RestTimerService): it survives the app going
/// to background, a lock or a process restart while the screen re-reads the clock.
class RestTimer extends ChangeNotifier {
  DateTime? _endsAt;

  /// Called when a countdown starts or changes (platform layer schedules a notification/sound).
  void Function(DateTime endsAt, int seconds)? onScheduled;

  /// Called when the countdown is cancelled.
  VoidCallback? onCancelled;

  bool get isRunning => _endsAt != null;
  DateTime? get endsAt => _endsAt;

  /// Seconds left (0 when finished, never negative).
  int remaining(DateTime now) {
    final end = _endsAt;
    if (end == null) return 0;
    final s = (end.difference(now).inMilliseconds / 1000).ceil();
    return s > 0 ? s : 0;
  }

  void start(int seconds, DateTime now) {
    _endsAt = now.add(Duration(seconds: seconds));
    onScheduled?.call(_endsAt!, seconds);
    notifyListeners();
  }

  void add(int seconds, DateTime now) {
    final base = _endsAt != null && _endsAt!.isAfter(now) ? _endsAt! : now;
    _endsAt = base.add(Duration(seconds: seconds));
    onScheduled?.call(_endsAt!, remaining(now));
    notifyListeners();
  }

  void stop() {
    if (_endsAt == null) return;
    _endsAt = null;
    onCancelled?.call();
    notifyListeners();
  }
}
