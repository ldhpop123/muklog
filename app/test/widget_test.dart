import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muklog/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('로그인 전에는 소셜 로그인 화면으로 시작한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: MuklogApp()));
    await tester.pumpAndSettle();
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.text('네이버로 시작하기'), findsOneWidget);
    expect(find.text('Google로 시작하기'), findsOneWidget);
  });

  testWidgets('목 로그인하면 밸런스 게임으로 이어진다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: MuklogApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();
    expect(find.text('둘 중 하나만 고른다면'), findsOneWidget);
  });
}
