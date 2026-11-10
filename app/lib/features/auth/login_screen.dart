import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth.dart';
import '../../core/config.dart';
import '../../core/google_login/google_button.dart';
import '../../core/widgets.dart';
import '../../models/auth.dart';

/// 로그인 = 회원가입. 카카오 · 네이버 · 구글 소셜 계정으로만 시작한다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  SocialProvider? _busy;

  /// 웹은 구글이 그려 주는 버튼을 쓴다. 준비(initialize)가 끝나야 그릴 수 있다.
  static final _googleOnWeb = kIsWeb && !AppConfig.useMock && AppConfig.hasGoogle;
  Future<void>? _googleReady;
  StreamSubscription<String>? _googleTokens;

  @override
  void initState() {
    super.initState();
    if (_googleOnWeb) {
      _googleReady = initGoogleSignIn();
      _googleTokens = googleWebIdTokens().listen(
        (token) => _run(SocialProvider.google, () => ref.read(authProvider.notifier).loginWithGoogleIdToken(token)),
        onError: (Object e) => _showError('구글 로그인을 하지 못했어요 ($e)'),
      );
    }
  }

  @override
  void dispose() {
    _googleTokens?.cancel();
    super.dispose();
  }

  Future<void> _login(SocialProvider p) => _run(p, () => ref.read(authProvider.notifier).login(p));

  Future<void> _run(SocialProvider p, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = p);
    await action();
    if (!mounted) return;
    setState(() => _busy = null);
    final error = ref.read(authProvider).error;
    if (error != null) _showError('$error');
    // 성공하면 router의 redirect가 온보딩이나 지도로 보낸다
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Spacer(flex: 3),
                Center(child: Image.asset('assets/brand/mark.png', height: 120)),
                const SizedBox(height: 24),
                const Center(child: Wordmark(size: 40)),
                const SizedBox(height: 16),
                Text('친구가 다녀온 곳만 보여 주는 미식 지도',
                    textAlign: TextAlign.center, style: text.titleMedium),
                const SizedBox(height: 6),
                Text('광고 없이, 입맛 맞는 친구의 기록으로 골라요',
                    textAlign: TextAlign.center, style: text.bodyMedium),
                const Spacer(flex: 4),
                _SocialButton(
                  provider: SocialProvider.kakao,
                  busy: _busy == SocialProvider.kakao,
                  onTap: () => _login(SocialProvider.kakao),
                ),
                const SizedBox(height: 10),
                _SocialButton(
                  provider: SocialProvider.naver,
                  busy: _busy == SocialProvider.naver,
                  onTap: () => _login(SocialProvider.naver),
                ),
                const SizedBox(height: 10),
                if (_googleOnWeb)
                  SizedBox(
                    height: 52,
                    child: _busy == SocialProvider.google
                        ? const Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        : FutureBuilder(
                            future: _googleReady,
                            builder: (context, snap) => snap.connectionState != ConnectionState.done
                                ? const SizedBox.shrink()
                                : LayoutBuilder(
                                    builder: (context, c) =>
                                        Center(child: googleWebButton(math.min(c.maxWidth, 400)))),
                          ),
                  )
                else
                  _SocialButton(
                    provider: SocialProvider.google,
                    busy: _busy == SocialProvider.google,
                    onTap: () => _login(SocialProvider.google),
                  ),
                const SizedBox(height: 20),
                Text('처음이면 고른 계정으로 바로 가입돼요. 닉네임과 프로필 사진만 가져와요',
                    textAlign: TextAlign.center, style: text.bodySmall),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// 각 회사의 로그인 버튼 안내(색·문구)를 따른 버튼.
class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.provider, required this.busy, required this.onTap});

  final SocialProvider provider;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border, label, Widget icon) = switch (provider) {
      SocialProvider.kakao => (
          const Color(0xFFFEE500),
          const Color(0xD9000000), // 검정 85%
          null,
          '카카오로 시작하기',
          const CustomPaint(size: Size(18, 18), painter: _KakaoSymbol()),
        ),
      SocialProvider.naver => (
          const Color(0xFF03C75A),
          Colors.white,
          null,
          '네이버로 시작하기',
          const CustomPaint(size: Size(16, 16), painter: _NaverSymbol()),
        ),
      SocialProvider.google => (
          Colors.white,
          const Color(0xFF1F1F1F),
          const Color(0xFF747775),
          'Google로 시작하기',
          const CustomPaint(size: Size(18, 18), painter: _GoogleSymbol()),
        ),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: border == null ? BorderSide.none : BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: SizedBox(
          height: 52,
          child: Row(children: [
            const SizedBox(width: 20),
            SizedBox(width: 20, child: Center(child: icon)),
            Expanded(
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                      )
                    : Text(label,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: fg, height: 1)),
              ),
            ),
            const SizedBox(width: 40),
          ]),
        ),
      ),
    );
  }
}

/// 카카오 말풍선 심볼
class _KakaoSymbol extends CustomPainter {
  const _KakaoSymbol();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF000000);
    final w = size.width, h = size.height;
    canvas.drawOval(Rect.fromLTWH(0, 0, w, h * 0.82), p);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.24, h * 0.62)
          ..lineTo(w * 0.18, h * 0.98)
          ..lineTo(w * 0.48, h * 0.74)
          ..close(),
        p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 네이버 N 심볼
class _NaverSymbol extends CustomPainter {
  const _NaverSymbol();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(w * 0.36, 0)
          ..lineTo(w * 0.64, h * 0.44)
          ..lineTo(w * 0.64, 0)
          ..lineTo(w, 0)
          ..lineTo(w, h)
          ..lineTo(w * 0.64, h)
          ..lineTo(w * 0.36, h * 0.56)
          ..lineTo(w * 0.36, h)
          ..lineTo(0, h)
          ..close(),
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 구글 G 심볼 (네 가지 색)
class _GoogleSymbol extends CustomPainter {
  const _GoogleSymbol();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s - stroke, s - stroke);
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    double deg(double d) => d * math.pi / 180;
    canvas.drawArc(rect, deg(-40), deg(-95), false, arc(const Color(0xFFEA4335))); // 빨강 (위)
    canvas.drawArc(rect, deg(-135), deg(-90), false, arc(const Color(0xFFFBBC05))); // 노랑 (왼쪽)
    canvas.drawArc(rect, deg(-225), deg(-90), false, arc(const Color(0xFF34A853))); // 초록 (아래)
    canvas.drawArc(rect, deg(-315), deg(-45), false, arc(const Color(0xFF4285F4))); // 파랑 (오른쪽 아래)
    canvas.drawRect(Rect.fromLTWH(s * 0.5, s * 0.42, s * 0.5, stroke), Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
