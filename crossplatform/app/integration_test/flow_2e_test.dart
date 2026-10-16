import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/flow_2e.dart';

/// Same 2.E flow on a real device/desktop build (Windows runner in CI; Android emulator if
/// available), with the real SQLite library bundled in the app.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('2.E end-to-end flow with persistence and reload', (tester) async {
    final dir = Directory.systemTemp.createTempSync('gym_2e_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await run2EFlow(tester, '${dir.path}${Platform.pathSeparator}gym.sqlite');
  });
}
