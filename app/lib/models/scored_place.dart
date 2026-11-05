import 'place.dart';

class ScoredPlace {
  const ScoredPlace(this.place, this.score, {this.reason});
  final Place place;
  final double score;

  /// 추천 이유. 예: "민수님(입맛 94%)이 4번 재방문"
  final String? reason;

  factory ScoredPlace.fromJson(Map<String, dynamic> json) => ScoredPlace(
        Place.fromJson(json['place'] as Map<String, dynamic>),
        (json['score'] as num).toDouble(),
        reason: json['reason'] as String?,
      );
}
