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
              child: Column(children: [
                const BrandLogo(size: 36, showName: false),
                const SizedBox(height: 6),
                const Wordmark(size: 15),
                const SizedBox(height: 20),
                const _RailRecordButton(),
                const SizedBox(height: 12),
                const SizedBox(width: 48, child: Divider(height: 1)),
              ]),
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

/// 넓은 화면 왼쪽 내비게이션의 "기록하기" 버튼. 앱에서 가장 중요한 행동이라 강조색을 쓴다.
class _RailRecordButton extends StatefulWidget {
  const _RailRecordButton();

  @override
  State<_RailRecordButton> createState() => _RailRecordButtonState();
}

class _RailRecordButtonState extends State<_RailRecordButton> {
  var _hover = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Tooltip(
      message: '다녀온 곳 기록하기',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: () => context.push('/record/search'),
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: motionFast,
            curve: motionCurve,
            child: Column(children: [
              AnimatedContainer(
                duration: motionFast,
                curve: motionCurve,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _hover ? const Color(0xFFAB3D16) : Palette.ember,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Color(0x261F1A15), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: const Icon(Icons.edit_outlined, size: 22, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text('기록하기', style: text.labelMedium!.copyWith(color: Palette.ember)),
            ]),
          ),
        ),
      ),
    );
  }
}
