enum RecordVisibility { private, friends, public }

/// 식당 방문 기록. (Dart의 `Record` 타입과 이름이 겹치지 않도록 VisitRecord로 둔다.)
class VisitRecord {
  const VisitRecord({
    required this.id,
    required this.userId,
    required this.placeId,
    required this.rating,
    required this.memo,
    required this.visitNo,
    required this.visitedAt,
    this.tags = const [],
    this.visibility = RecordVisibility.friends,
    this.inspiredByRecordId,
  });

  final String id;
  final String userId;
  final String placeId;
  final double rating;
  final String memo;

  /// 같은 식당 방문 회차 (1 = 첫 방문)
  final int visitNo;
  final DateTime visitedAt;
  final List<String> tags;
  final RecordVisibility visibility;

  /// "이 기록 보고 왔어요" — 맛 신뢰 온도 계산의 연결 고리
  final String? inspiredByRecordId;

  factory VisitRecord.fromJson(Map<String, dynamic> json) => VisitRecord(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        placeId: json['place_id'] as String,
        rating: (json['rating'] as num).toDouble(),
        memo: json['memo'] as String? ?? '',
        visitNo: json['visit_no'] as int? ?? 1,
        visitedAt: DateTime.parse(json['visited_at'] as String),
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        visibility: RecordVisibility.values
            .byName(json['visibility'] as String? ?? 'friends'),
        inspiredByRecordId: json['inspired_by_record_id'] as String?,
      );
}
