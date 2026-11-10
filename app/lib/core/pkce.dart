import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE 확인값 (RFC 7636). 로그인을 시작한 앱만 교환을 마칠 수 있게 묶는다.
class Pkce {
  Pkce._(this.verifier, this.challenge);

  /// 앱만 아는 값. 교환(POST /auth/exchange) 때 보낸다.
  final String verifier;

  /// verifier의 SHA-256 해시. 시작(GET /auth/naver/start) 때 보낸다.
  final String challenge;

  factory Pkce.generate() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final verifier = _b64url(bytes); // 43자
    return Pkce._(verifier, challengeOf(verifier));
  }

  static String challengeOf(String verifier) => _b64url(sha256.convert(ascii.encode(verifier)).bytes);

  static String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}
