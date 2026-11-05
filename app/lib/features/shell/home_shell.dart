import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

/// 지도 · 파티 모드 · 프로필 탭을 가진 홈 레이아웃.
/// 좁은 화면은 하단 탭, 넓은 화면(PC 웹)은 왼쪽 세로 내비게이션.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = ['/', '/party', '/profile'];
  static const _items = [
    (Icons.map_outlined, '지도'),
    (Icons.groups_outlined, '파티 모드'),
    (Icons.person_outline, '프로필'),
  ];

  @override
  Widget build(BuildContext context) {
    final index = _tabs.indexOf(location).clamp(0, _tabs.length - 1);
    void go(int i) => context.go(_tabs[i]);

    if (isWide(context)) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: Text('먹로그', style: Theme.of(context).textTheme.titleMedium),
            ),
            destinations: [
              for (final (icon, label) in _items)
                NavigationRailDestination(icon: Icon(icon), label: Text(label)),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Palette.hairline),
          Expanded(child: child),
        ]),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: go,
        destinations: [
          for (final (icon, label) in _items) NavigationDestination(icon: Icon(icon), label: label),
        ],
      ),
    );
  }
}
