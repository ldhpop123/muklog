import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muklog/app.dart';

void main() {
  testWidgets('앱이 온보딩 화면으로 시작한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MuklogApp()));
    await tester.pumpAndSettle();
    expect(find.text('둘 중 하나만 고른다면'), findsOneWidget);
  });
}
