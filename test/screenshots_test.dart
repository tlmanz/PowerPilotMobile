// Renders every tab at the design's width (390), full length, with the real
// fonts and the demo, to compare with the frames in mobile.pen:
//   SCREENSHOTS=/some/folder flutter test test/screenshots_test.dart
// Without SCREENSHOTS it's skipped.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powerpilot/data/pairing.dart';
import 'package:powerpilot/main.dart';
import 'package:powerpilot/state/controllers.dart';

import 'fakes.dart';

final _out = Platform.environment['SCREENSHOTS'];

class _MemoryStore extends PairingStore {
  @override
  Future<Pairing?> load() async => null;
}

Future<void> _fonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('fonts/Inter-$w.ttf'));
  }
  await inter.load();
  await (FontLoader(
    'packages/lucide_icons_flutter/Lucide',
  )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  File('$_out/$name.png').writeAsBytesSync(bytes!);
}

/// With no [scenario], the phone is unpaired: that shoots the Pair screen.
Future<void> _run(WidgetTester tester, String? scenario, List<String> tabs) async {
  await tester.runAsync(_fonts);
  tester.view.physicalSize = Size(390, scenario == null ? 844 : 1320) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  final app = AppController(store: _MemoryStore(), demoScenario: scenario, push: testPush());
  await app.init();
  await tester.pumpWidget(RepaintBoundary(key: key, child: PowerPilotApp(app)));
  final context = tester.element(find.byType(Scaffold).first);
  await tester.runAsync(() async {
    for (final a in ['images/logo.png', 'images/ups-front.png', 'images/ups-flow.png']) {
      await precacheImage(AssetImage(a), context);
    }
  });
  // Let the Events and Trends tabs load their days.
  await tester.pump(const Duration(seconds: 3));

  if (scenario == null) await _shoot(tester, key, 'pair');
  for (final tab in tabs) {
    await tester.tap(find.text(tab).last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await _shoot(tester, key, '$scenario-${tab.toLowerCase()}');
  }
  await tester.pumpWidget(const SizedBox());
  app.dispose();
}

void main() {
  final skip = _out == null ? 'set SCREENSHOTS to a folder to render the screens' : null;

  testWidgets('on mains: every tab', skip: skip != null, (tester) async {
    await _run(tester, 'ac', ['Home', 'Controls', 'Trends', 'Events', 'Settings']);
  });

  testWidgets('on battery: home and controls', skip: skip != null, (tester) async {
    await _run(tester, 'battery', ['Home', 'Controls']);
  });

  testWidgets('unpaired: the Pair screen', skip: skip != null, (tester) async {
    await _run(tester, null, const []);
  });
}
