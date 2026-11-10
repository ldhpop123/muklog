import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

/// 웹: 구글은 웹에서 자기 버튼(Google Identity Services)으로만 로그인을 시작하게 한다.
/// 누르면 결과가 GoogleSignIn.instance.authenticationEvents로 온다.
Widget googleWebButton(double width) => gsi.renderButton(
      configuration: gsi.GSIButtonConfiguration(
        theme: gsi.GSIButtonTheme.outline,
        size: gsi.GSIButtonSize.large,
        text: gsi.GSIButtonText.continueWith,
        shape: gsi.GSIButtonShape.rectangular,
        minimumWidth: width,
        locale: 'ko',
      ),
    );
