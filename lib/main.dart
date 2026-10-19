// PowerPilot for phones: watch and control a UPS through powerpilot-server.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/screens/pair_screen.dart';
import 'state/controllers.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// `flutter run --dart-define=DEMO=battery` opens the demo straight away in
/// one scenario (cycle, ac, battery, bypass or fault), as the dashboard's
/// ?source=mock&scenario= does.
const _demo = String.fromEnvironment('DEMO');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  final app = AppController(demoScenario: _demo.isEmpty ? null : _demo)..init();
  runApp(PowerPilotApp(app));
}

class PowerPilotApp extends StatelessWidget {
  const PowerPilotApp(this.app, {super.key});

  final AppController app;

  @override
  Widget build(BuildContext context) => AppScope(
    notifier: app,
    child: MaterialApp(
      title: 'PowerPilot',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      themeMode: ThemeMode.light,
      // The design is laid out at fixed sizes: follow the system's text
      // size, up to a point.
      builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
      home: const _Root(),
    ),
  );
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return switch (app.phase) {
      AppPhase.loading => const Scaffold(body: SizedBox()),
      AppPhase.unpaired => const PairScreen(),
      // A new pairing starts every tab afresh.
      AppPhase.ready => UpsScope(
        notifier: app.ups!,
        child: KeyedSubtree(key: ObjectKey(app.ups), child: const Shell()),
      ),
    };
  }
}
