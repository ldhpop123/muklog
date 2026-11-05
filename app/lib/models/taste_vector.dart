import 'dart:math' as math;

/// 5대 미식 차원. 각 값은 -1 ~ +1 (README 6.1).
class TasteVector {
  const TasteVector({
    required this.saltiness,
    required this.spiciness,
    required this.ambience,
    required this.value,
    required this.cuisine,
  });

  /// 간의 세기: -1 슴슴함 ↔ +1 자극적
  final double saltiness;

  /// 매운맛 선호: -1 안 매운 맛 ↔ +1 아주 매운 맛
  final double spiciness;

  /// 분위기: -1 노포·서민 ↔ +1 모던·감성
  final double ambience;

  /// 가성비 민감도: -1 가격 무관 ↔ +1 가성비 중시
  final double value;

  /// 메뉴 지향성: -1 한식·토속 ↔ +1 양식·이국
  final double cuisine;

  static const zero = TasteVector(
      saltiness: 0, spiciness: 0, ambience: 0, value: 0, cuisine: 0);

  static const labels = ['간의 세기', '매운맛', '분위기', '가성비', '메뉴'];

  /// 각 차원의 (-1 쪽, +1 쪽) 설명. 서버 taste.DIMENSION_LABELS와 같은 말을 쓴다.
  static const poles = [
    ('슴슴한 맛', '자극적인 맛'),
    ('순한 맛', '매운맛'),
    ('노포', '감성 공간'),
    ('분위기·품질', '가성비'),
    ('한식', '양식·이국 요리'),
  ];

  List<double> toList() => [saltiness, spiciness, ambience, value, cuisine];

  factory TasteVector.fromList(List<double> v) => TasteVector(
      saltiness: v[0],
      spiciness: v[1],
      ambience: v[2],
      value: v[3],
      cuisine: v[4]);

  factory TasteVector.fromJson(Map<String, dynamic> json) => TasteVector(
        saltiness: (json['saltiness'] as num).toDouble(),
        spiciness: (json['spiciness'] as num).toDouble(),
        ambience: (json['ambience'] as num).toDouble(),
        value: (json['value'] as num).toDouble(),
        cuisine: (json['cuisine'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'saltiness': saltiness,
        'spiciness': spiciness,
        'ambience': ambience,
        'value': value,
        'cuisine': cuisine,
      };

  /// 코사인 유사도 (-1 ~ 1). 영벡터가 끼면 0.
  double cosine(TasteVector other) {
    final a = toList(), b = other.toList();
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  /// 입맛 커플링 지수 (0 ~ 100%). 서버 `taste.couple_percent`와 같은 식.
  int couplePercent(TasteVector other) => (50 * (1 + cosine(other))).round();
}
