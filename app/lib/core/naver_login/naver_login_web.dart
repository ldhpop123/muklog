import 'package:web/web.dart' as web;

import '../../data/muklog_repository.dart';
import '../pkce.dart';
import 'naver_login.dart';

const _verifierKey = 'muklog.naver.verifier';

/// 웹: 페이지 전체를 네이버 로그인으로 보낸다. verifier는 이 탭의 sessionStorage에만 둔다.
Future<(String, String)?> startNaverLogin() async {
  final pkce = Pkce.generate();
  web.window.sessionStorage.setItem(_verifierKey, pkce.verifier);
  final here = Uri.base;
  final redirect = here.replace(queryParameters: const {}, fragment: '').toString().replaceAll('?', '');
  await ensureNaverLoginReady(redirect, pkce);
  web.window.location.assign(naverStartUrl(redirect, pkce));
  return null;
}

/// 네이버에서 돌아온 주소의 login_code(또는 login_error)를 꺼내고, 주소창에서는 지운다.
(String, String)? takePendingNaverLogin() {
  final q = Uri.base.queryParameters;
  final code = q['login_code'], error = q['login_error'];
  if (code == null && error == null) return null;
  final clean = Uri.base.replace(queryParameters: const {}).toString().replaceAll('?', '');
  web.window.history.replaceState(null, '', clean);
  final verifier = web.window.sessionStorage.getItem(_verifierKey);
  web.window.sessionStorage.removeItem(_verifierKey);
  if (error != null) throw MuklogException(error);
  if (verifier == null) throw const MuklogException('로그인을 시작한 창이 아니에요. 다시 로그인해 주세요');
  return (code!, verifier);
}
