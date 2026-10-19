// The five tabs, under the design's Tab Bar.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'screens/controls_screen.dart';
import 'screens/events_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/trends_screen.dart';
import 'theme.dart';

enum AppTab {
  home('Home', LucideIcons.house),
  controls('Controls', LucideIcons.slidersHorizontal),
  trends('Trends', LucideIcons.chartLine),
  events('Events', LucideIcons.list),
  settings('Settings', LucideIcons.settings);

  const AppTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Lets a screen switch tabs ("View all" on Home opens Events).
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.go, required super.child});

  final ValueChanged<AppTab> go;

  static ShellScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>()!;

  @override
  bool updateShouldNotify(ShellScope old) => false;
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  AppTab _tab = AppTab.home;

  void _go(AppTab t) => setState(() => _tab = t);

  @override
  Widget build(BuildContext context) => ShellScope(
    go: _go,
    child: Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _tab.index,
        children: const [HomeScreen(), ControlsScreen(), TrendsScreen(), EventsScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: _TabBar(current: _tab, onTap: _go),
    ),
  );
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onTap});

  final AppTab current;
  final ValueChanged<AppTab> onTap;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xF2FFFFFF),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: EdgeInsets.fromLTRB(8, 6, 8, MediaQuery.paddingOf(context).bottom + 4),
        child: Row(
          children: [
            for (final t in AppTab.values)
              Expanded(
                child: Semantics(
                  selected: t == current,
                  button: true,
                  label: t.label,
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: () => onTap(t),
                    radius: 32,
                    child: SizedBox(
                      height: 48,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(t.icon, size: 22, color: t == current ? AppColors.primary : AppColors.ink3),
                          const SizedBox(height: 3),
                          Text(
                            t.label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: text(
                              10,
                              weight: t == current ? FontWeight.w600 : FontWeight.w500,
                              color: t == current ? AppColors.primary : AppColors.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A tab's scrolling page: the design's content padding, clear of the status
/// bar and the tab bar.
class TabPage extends StatelessWidget {
  const TabPage({super.key, required this.children, this.gap = 16, this.onRefresh});

  final List<Widget> children;
  final double gap;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final list = ListView(
      padding: EdgeInsets.fromLTRB(16, pad.top + 4, 16, pad.bottom + 84 + 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
      ],
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, edgeOffset: pad.top, child: list);
  }
}
