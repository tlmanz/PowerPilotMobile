import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powerpilot/data/pairing.dart';
import 'package:powerpilot/main.dart';
import 'package:powerpilot/state/controllers.dart';
import 'package:powerpilot/ui/widgets.dart';

/// Keeps the pairing in memory instead of the Keychain.
class _MemoryStore extends PairingStore {
  _MemoryStore([this.saved]);

  Pairing? saved;

  @override
  Future<Pairing?> load() async => saved;

  @override
  Future<void> save(Pairing p) async => saved = p;

  @override
  Future<void> clear() async => saved = null;
}

Future<AppController> _launch(WidgetTester tester, {Pairing? paired}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final app = AppController(store: _MemoryStore(paired));
  await app.init();
  await tester.pumpWidget(PowerPilotApp(app));
  await tester.pump(const Duration(milliseconds: 100));
  return app;
}

/// The demo's timer and the power-flow animation must stop before the test
/// ends: the binding checks for pending timers before any tear-down runs.
Future<void> _close(WidgetTester tester, AppController app) async {
  await tester.pumpWidget(const SizedBox());
  app.dispose();
}

void main() {
  testWidgets('an unpaired phone can start the demo', (tester) async {
    final app = await _launch(tester);
    expect(find.text('Pair this phone'), findsOneWidget);
    expect(find.text('Scan QR code'), findsOneWidget);
    expect(find.text('Paste a pairing link'), findsOneWidget);

    await tester.ensureVisible(find.text('Try with demo data'));
    await tester.tap(find.text('Try with demo data'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(app.phase, AppPhase.ready);
    expect(app.pairing!.demo, isTrue);
    expect(find.text('Prolink PRO2000SFCU'), findsOneWidget);
    await _close(tester, app);
  });

  // Android draws the first frame zero wide. A layout that went negative there
  // broke the tree for good: every tab stayed blank.
  testWidgets('a zero-size first frame leaves every screen drawable', (tester) async {
    for (final paired in [null, const Pairing.demo()]) {
      tester.view.physicalSize = Size.zero;
      tester.view.devicePixelRatio = 3;
      final app = AppController(store: _MemoryStore(paired));
      await app.init();
      await tester.pumpWidget(PowerPilotApp(app));
      await tester.pump();
      tester.view.physicalSize = const Size(390, 844) * 3;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text(paired == null ? 'Pair this phone' : 'Power Flow'), findsOneWidget);
      await _close(tester, app);
    }
    tester.view.reset();
  });

  testWidgets('home shows the demo UPS, and every tab opens', (tester) async {
    final app = await _launch(tester, paired: const Pairing.demo());

    expect(find.text('Connected · Demo data'), findsOneWidget);
    expect(find.text('Power Flow'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);

    await tester.tap(find.text('Controls'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Graceful shutdown'), findsOneWidget);
    expect(find.text('Start test'), findsOneWidget);

    await tester.tap(find.text('Trends'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Input voltage'), findsOneWidget);
    // The PRO2000SFCU reports no temperature, so there's no chart for it.
    expect(find.text('Temperature'), findsNothing);

    // Tapping a bar reads it out in place of its card's Min/Max; tapping it
    // again puts Min/Max back.
    final minMax = find.textContaining('Min ');
    final cards = tester.widgetList(minMax).length;
    final newest = tester.getBottomRight(find.byType(BarChart).first) - const Offset(3, 10);
    await tester.tapAt(newest);
    await tester.pump();
    expect(tester.widgetList(minMax).length, cards - 1);
    await tester.tapAt(newest);
    await tester.pump();
    expect(tester.widgetList(minMax).length, cards);

    await tester.tap(find.text('Events'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('CSV'), findsOneWidget);
    expect(find.text('Peak load'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Push notifications'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    await _close(tester, app);
  });
}
