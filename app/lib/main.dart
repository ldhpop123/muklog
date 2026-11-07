import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'app.dart';
import 'core/config.dart';
import 'features/map/widgets/muk_map.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMukMap();
  if (AppConfig.hasKakao) {
    KakaoSdk.init(
      nativeAppKey: AppConfig.kakaoNativeAppKey.isEmpty ? null : AppConfig.kakaoNativeAppKey,
      javaScriptAppKey: AppConfig.kakaoJsAppKey.isEmpty ? null : AppConfig.kakaoJsAppKey,
    );
  }
  runApp(const ProviderScope(child: MuklogApp()));
}
