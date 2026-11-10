import 'package:flutter/material.dart';

import '../../core/widgets.dart';

/// 저장된 세션을 확인하는 짧은 순간에만 보이는 시작 화면.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: BrandLogo(size: 40)));
  }
}
