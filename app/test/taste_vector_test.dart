import 'package:flutter_test/flutter_test.dart';
import 'package:muklog/models/taste_vector.dart';

void main() {
  const a = TasteVector(saltiness: -0.5, spiciness: 0.2, ambience: -0.8, value: 0.6, cuisine: -0.6);

  test('같은 입맛이면 커플링 100%', () {
    expect(a.couplePercent(a), 100);
  });

  test('정반대 입맛이면 커플링 0%', () {
    final opposite = TasteVector.fromList(a.toList().map((v) => -v).toList());
    expect(a.couplePercent(opposite), 0);
  });

  test('영벡터와는 50% (판단 불가)', () {
    expect(a.couplePercent(TasteVector.zero), 50);
  });
}
