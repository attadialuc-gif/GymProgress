import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';
import 'package:path_provider/path_provider.dart';

import 'app_model.dart';
import 'services/platform_services.dart';
import 'shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final model = await openAppModel();
  runApp(GymProgressApp(model: model));
}

/// IANA zone of the device; falls back to a fixed-offset zone when the platform name is unknown
/// to the embedded tz database (days are still counted in local time).
Future<String> deviceTimeZone() async {
  try {
    final id = (await FlutterTimezone.getLocalTimezone()).identifier;
    TrainingCalendar(timeZone: id);
    return id;
  } catch (_) {
    final hours = DateTime.now().timeZoneOffset.inHours;
    // Etc/GMT signs are inverted (Etc/GMT+3 = UTC−3).
    return hours == 0 ? 'UTC' : 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
  }
}

/// Opens the persistent store in the app's private data folder (Android: app files;
/// Windows: %APPDATA%\com.gymprogress\GymProgress). Never falls back silently to a temporary store.
Future<AppModel> openAppModel() async {
  final zone = await deviceTimeZone();
  try {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final repo = SqliteGymRepository.open('${dir.path}${Platform.pathSeparator}gymprogress.sqlite');
    final model = AppModel(repo, timeZone: zone);
    model.seedCatalog();
    model.platform = PlatformServices(model, dataDir: dir.path);
    await model.platform!.start();
    return model;
  } catch (e) {
    // Block the UI and explain; an in-memory store only backs the error screen.
    return AppModel(
      SqliteGymRepository.open(),
      timeZone: zone,
      storeError:
          'No se pudo abrir la base de datos de la app. Tus datos no se modificaron. Cerrá la app y volvé a abrirla; '
          'si el problema sigue, no registres entrenamientos hasta resolverlo.\n\nDetalle: $e',
    );
  }
}

class GymProgressApp extends StatefulWidget {
  const GymProgressApp({super.key, required this.model});
  final AppModel model;

  @override
  State<GymProgressApp> createState() => _GymProgressAppState();
}

class _GymProgressAppState extends State<GymProgressApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The device time zone may change while the app sleeps (travel, DST rules): re-read on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.model.platform?.updateWakelock(appVisible: state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      deviceTimeZone().then((zone) {
        if (zone != widget.model.timeZone) {
          widget.model.timeZone = zone;
          widget.model.perform(() {});
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      model: widget.model,
      child: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) => MaterialApp(
          title: 'GymProgress',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: widget.model.storeError != null ? ThemeMode.dark : themeMode(widget.model.settings.theme),
          locale: const Locale('es', 'AR'),
          supportedLocales: const [Locale('es', 'AR'), Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: widget.model.storeError != null ? _StoreErrorScreen(message: widget.model.storeError!) : const Shell(),
        ),
      ),
    );
  }
}

class _StoreErrorScreen extends StatelessWidget {
  const _StoreErrorScreen({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: EmptyState(
            icon: Icons.sd_card_alert_outlined,
            title: 'No se pudieron abrir tus datos',
            message: message,
          ),
        ),
      ),
    ),
  );
}
