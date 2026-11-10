import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../data/muklog_repository.dart';
import '../pkce.dart';
import 'naver_login.dart';

const _callback = 'muklog://auth';

/// 모바일: 시스템 브라우저(Android Custom Tabs, iOS ASWebAuthenticationSession)로 로그인하고 muklog://auth로 돌아온다.
Future<(String, String)?> startNaverLogin() async {
  final pkce = Pkce.generate();
  await ensureNaverLoginReady(_callback, pkce);
  final String result;
  try {
    result = await FlutterWebAuth2.authenticate(url: naverStartUrl(_callback, pkce), callbackUrlScheme: 'muklog');
  } on PlatformException catch (e) {
    if (e.code == 'CANCELED') throw const MuklogException('네이버 로그인을 취소했어요');
    throw MuklogException('네이버 로그인 화면을 열지 못했어요 (${e.code})');
  }
  final q = Uri.parse(result).queryParameters;
  final error = q['login_error'];
  if (error != null) throw MuklogException(error);
  final code = q['login_code'];
  if (code == null) throw const MuklogException('네이버 로그인 결과를 받지 못했어요. 다시 시도해 주세요');
  return (code, pkce.verifier);
}

(String, String)? takePendingNaverLogin() => null;
