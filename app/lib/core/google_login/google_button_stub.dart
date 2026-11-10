import 'package:flutter/widgets.dart';

/// 모바일은 앱이 그린 버튼으로 [GoogleSignIn.authenticate]를 부르므로 쓰지 않는다.
Widget googleWebButton(double width) => const SizedBox.shrink();
