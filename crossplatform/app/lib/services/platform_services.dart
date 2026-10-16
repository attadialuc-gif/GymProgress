import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_model.dart';

/// Platform adaptations (D-106, docs/PARIDAD.md). Everything here is optional comfort: if a
/// platform feature is missing or denied, the app keeps working and nothing is lost.
class PlatformServices {
  PlatformServices(this.model, {required this.dataDir});

  final AppModel model;

  /// App private data folder (same as the database).
  final String dataDir;

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  bool _permissionAsked = false;
  bool _wakelockOn = false;
  Timer? _desktopAlarm;
  static const _restId = 7001;

  bool get _android => !kIsWeb && Platform.isAndroid;
  bool get _windows => !kIsWeb && Platform.isWindows;
  File get _timerFile => File('$dataDir${Platform.pathSeparator}rest_timer.json');

  Future<void> start() async {
    await _initNotifications();
    _restoreRestTimer();
    model.restTimer.onScheduled = _onRestScheduled;
    model.restTimer.onCancelled = _onRestCancelled;
    model.addListener(updateWakelock);
    updateWakelock();
  }

  Future<void> _initNotifications() async {
    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: 'GymProgress',
            appUserModelId: 'GymProgress.GymProgress',
            guid: '6f8b2d4a-1c3e-4b5f-9a7d-2e4c6b8a0d1f',
          ),
        ),
      );
      _notificationsReady = true;
    } catch (e) {
      // No notifications on this system: the in-app countdown still works.
      debugPrint('notifications unavailable: $e');
    }
  }

  // MARK: Rest timer

  /// A countdown that was running when the process died is restored (timestamp-based).
  void _restoreRestTimer() {
    try {
      if (!_timerFile.existsSync()) return;
      final data = jsonDecode(_timerFile.readAsStringSync()) as Map<String, Object?>;
      final end = DateTime.fromMillisecondsSinceEpoch(data['endsAt'] as int, isUtc: true);
      final remaining = end.difference(model.now()).inSeconds;
      if (remaining > 0 && model.workout.openSession() != null) {
        model.restTimer.start(remaining, model.now());
      } else {
        _timerFile.deleteSync();
      }
    } catch (_) {
      // A damaged convenience file only loses the countdown, never workout data.
    }
  }

  Future<void> _onRestScheduled(DateTime endsAt, int seconds) async {
    try {
      _timerFile.writeAsStringSync(jsonEncode({'endsAt': endsAt.toUtc().millisecondsSinceEpoch}));
    } catch (_) {}
    await _onRestCancelled();
    if (!model.settings.restNotifications || !_notificationsReady) return;
    if (_android) {
      await _scheduleAndroid(endsAt);
    } else if (_windows) {
      // Desktop: the app is open; a toast plus the system sound at the end of the rest.
      _desktopAlarm = Timer(endsAt.difference(DateTime.now().toUtc()), () async {
        unawaited(SystemSound.play(SystemSoundType.alert));
        await _show();
      });
    }
  }

  Future<void> _onRestCancelled() async {
    _desktopAlarm?.cancel();
    _desktopAlarm = null;
    if (!model.restTimer.isRunning) {
      try {
        if (_timerFile.existsSync()) _timerFile.deleteSync();
      } catch (_) {}
    }
    if (_notificationsReady) {
      try {
        await _notifications.cancel(id: _restId);
      } catch (_) {}
    }
  }

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'rest_timer',
      'Descanso',
      channelDescription: 'Aviso cuando termina el descanso entre series',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
    ),
    windows: WindowsNotificationDetails(),
  );

  Future<void> _show() async {
    try {
      await _notifications.show(
        id: _restId,
        title: 'Descanso terminado',
        body: 'Es momento de la próxima serie.',
        notificationDetails: _details,
      );
    } catch (_) {}
  }

  /// Android 13+: the permission is asked in context (first rest timer), never at launch. Exact
  /// alarms when allowed; otherwise an inexact one (may arrive a little late), never an error.
  Future<void> _scheduleAndroid(DateTime endsAt) async {
    final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      if (!_permissionAsked) {
        _permissionAsked = true;
        await android.requestNotificationsPermission();
      }
      if (await android.areNotificationsEnabled() == false) return;
      final exact = await android.canScheduleExactNotifications() ?? false;
      await _notifications.zonedSchedule(
        id: _restId,
        scheduledDate: tz.TZDateTime.from(endsAt.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Descanso terminado',
        body: 'Es momento de la próxima serie.',
      );
    } catch (e) {
      debugPrint('rest notification not scheduled: $e');
    }
  }

  /// Android 12+: opens the system screen to allow exact alarms (optional, from Profile).
  Future<void> requestExactAlarms() async {
    final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
  }

  bool get supportsExactAlarmSetting => _android;

  // MARK: Screen

  /// Screen stays on during an open session when the user enabled it, never otherwise.
  void updateWakelock({bool appVisible = true}) {
    final on =
        appVisible && model.storeError == null && model.settings.keepScreenOn && model.workout.openSession() != null;
    if (on == _wakelockOn) return;
    _wakelockOn = on;
    WakelockPlus.toggle(enable: on).catchError((Object _) {});
  }
}
