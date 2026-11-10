import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../data/muklog_repository.dart';
import '../config.dart';
import '../pkce.dart';
import 'naver_login_stub.dart'
    if (dart.library.io) 'naver_login_io.dart'
    if (dart.library.js_interop) 'naver_login_web.dart' as platform;

/// 네이버 로그인은 보안상 서버가 대신 처리한다 (앱에 Client Secret을 두지 않고, 다른 앱 토큰 재사용을 막기 위해).
/// 서버 /auth/naver/start → 네이버 → 서버 콜백 → 1회용 login_code → 앱이 PKCE verifier와 함께 교환.
String naverStartUrl(String redirect, Pkce pkce) => Uri.parse('${AppConfig.apiBaseUrl}/auth/naver/start')
    .replace(queryParameters: {'redirect': redirect, 'code_challenge': pkce.challenge})
    .toString();

/// 브라우저를 열기 전에 서버가 네이버 로그인을 처리할 수 있는지 확인한다.
/// (키가 없으면 서버가 503을 주는데, 그대로 브라우저로 열면 오류 글자만 보이기 때문)
Future<void> ensureNaverLoginReady(String redirect, Pkce pkce) async {
  final dio = Dio(BaseOptions(
    followRedirects: false,
    validateStatus: (s) => s != null && s < 600,
    connectTimeout: const Duration(seconds: 5),
  ));
  try {
    final res = await dio.get<dynamic>(naverStartUrl(redirect, pkce));
    if (res.statusCode == 302 || res.statusCode == 307) return;
    final detail = res.data is Map ? (res.data as Map)['detail'] : null;
    throw MuklogException(detail is String ? detail : '네이버 로그인을 시작하지 못했어요 (${res.statusCode})');
  } on DioException catch (e) {
    // 웹 브라우저는 302를 막을 수 없어 네이버까지 따라가고, 네이버가 CORS를 막아 응답 없이 실패한다.
    // 이때는 서버가 살아 있으면 302를 준 것으로 본다.
    if (kIsWeb && e.response == null && await _serverUp(dio)) return;
    throw const MuklogException('서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요');
  }
}

Future<bool> _serverUp(Dio dio) async {
  try {
    return (await dio.get<dynamic>('${AppConfig.apiBaseUrl}/health')).statusCode == 200;
  } on DioException {
    return false;
  }
}

/// 결과 (login_code, verifier). 웹은 페이지가 네이버로 넘어가므로 null을 돌려주고,
/// 돌아온 뒤 [takePendingNaverLogin]이 결과를 건넨다.
Future<(String, String)?> startNaverLogin() => platform.startNaverLogin();

/// 웹: 네이버에서 돌아온 주소(?login_code=…)가 있으면 꺼내고 주소에서 지운다. 모바일은 항상 null.
(String, String)? takePendingNaverLogin() => platform.takePendingNaverLogin();
