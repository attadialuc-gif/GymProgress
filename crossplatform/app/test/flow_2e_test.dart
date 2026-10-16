import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flow_2e.dart';

void main() {
  testWidgets('2.E end-to-end flow with persistence and reload (phone layout)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 800)); // a real phone screen
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('gym_2e_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await run2EFlow(tester, '${dir.path}/gym.sqlite');
  });

  testWidgets('2.E end-to-end flow on a wide window (side navigation)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('gym_2e_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await run2EFlow(tester, '${dir.path}/gym.sqlite');
  });
}
