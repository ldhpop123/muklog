import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 지도 확대·축소 버튼. 세 지도 구현(임시 지도, 네이버 모바일, 네이버 웹)이 같은 모양으로 쓴다.
class ZoomButtons extends StatelessWidget {
  const ZoomButtons({super.key, required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback onTap) => SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            tooltip: tooltip,
            onPressed: onTap,
            padding: EdgeInsets.zero,
            icon: Icon(icon, size: 20, color: Palette.ink),
          ),
        );
    return Material(
      color: Palette.card,
      elevation: 1,
      shadowColor: const Color(0x331F1A15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Palette.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        button(Icons.add, '확대', onZoomIn),
        const SizedBox(width: 24, child: Divider(height: 1)),
        button(Icons.remove, '축소', onZoomOut),
      ]),
    );
  }
}

/// 지도 오른쪽 가운데보다 조금 위. 아래쪽 추천 시트와 "내 위치" 버튼을 피한다.
class ZoomButtonsPosition extends StatelessWidget {
  const ZoomButtonsPosition({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: const Alignment(1, -0.15), child: Padding(padding: const EdgeInsets.only(right: 12), child: child));
}
