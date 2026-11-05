import '../models/place.dart';
import '../models/scored_place.dart';
import '../models/social.dart';
import '../models/taste_vector.dart';
import '../models/user_profile.dart';
import '../models/visit_record.dart';

export '../models/scored_place.dart';

/// 앱이 서버와 주고받는 모든 데이터의 창구.
/// 목 구현([MockMuklogRepository])과 API 구현([ApiMuklogRepository])을 `AppConfig.useMock`으로 바꿔 끼운다.
/// API 계약은 README "서버 (FastAPI)" 섹션의 엔드포인트 표를 따른다.
abstract class MuklogRepository {
  Future<UserProfile> me();
  Future<List<UserProfile>> friends();

  /// tags: 하나라도 가진 식당. layer: 친구/내 기록이 있는 곳만.
  /// near: 주면 그 지점에서 [radiusKm] 안의 식당만.
  Future<List<Place>> places({
    List<String> tags = const [],
    MapLayer layer = MapLayer.all,
    LatLng? near,
    double radiusKm = 3,
  });
  Future<List<VisitRecord>> recordsForPlace(String placeId);

  /// near: 주면 가까울수록 점수를 더 주고 추천 이유에 거리를 붙인다 (README 6.4 Context 보정).
  Future<List<ScoredPlace>> recommend({LatLng? near});
  Future<List<ScoredPlace>> partyRecommend(List<String> memberIds);
  Future<void> saveOnboarding(TasteVector taste);

  /// 실패 시 [MuklogException] (예: 볼 수 없는 기록을 "보고 왔어요"로 지정).
  Future<void> createRecord(VisitRecord record);

  Future<Coupling> couple(String friendId);
  Future<Briefing> briefing(String area);
  Future<List<RankingEntry>> ranking(RankingScope scope);
  Future<List<Dislike>> dislikes();
  Future<List<Dislike>> saveDislikes(List<Dislike> items);
}

/// 사용자에게 그대로 보여 줄 수 있는 메시지를 담은 오류.
class MuklogException implements Exception {
  const MuklogException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 브리핑을 지원하는 지역. 서버 시드 데이터의 Place.area와 같다.
const briefingAreas = ['홍대', '연남', '상수'];
