import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 하단 탭(지도 · 파티 모드 · 프로필)을 가진 홈 레이아웃.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = ['/', '/party', '/profile'];

  @override
  Widget build(BuildContext context) {
    final index = _tabs.indexOf(location).clamp(0, _tabs.length - 1);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), label: '지도'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined), label: '파티 모드'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '프로필'),
        ],
      ),
    );
  }
}
