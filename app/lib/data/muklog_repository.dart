import '../models/auth.dart';
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
  /// 소셜 로그인 SDK가 준 토큰(카카오·네이버: 액세스 토큰, 구글: ID 토큰)을 서버에서 검증하고 먹로그 세션을 받는다.
  Future<AuthResult> login(SocialProvider provider, String providerToken);

  /// 네이버 로그인: 서버 콜백이 돌려준 1회용 코드를, 시작할 때 만든 PKCE verifier와 함께 세션으로 바꾼다.
  Future<AuthResult> exchangeLoginCode(String loginCode, String codeVerifier);

  Future<void> logout();

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
  /// 지도 화면 가운데에서 가까운 상권 (기록이 없어도 포함), 가까운 순.
  Future<List<AreaInfo>> nearbyAreas(LatLng center, {int limit = 5});

  /// [area]는 [nearbyAreas]가 준 상권 이름.
  Future<Briefing> briefing(String area);
  Future<List<RankingEntry>> ranking(RankingScope scope);
  Future<List<Dislike>> dislikes();
  Future<List<Dislike>> saveDislikes(List<Dislike> items);

  /// 식당 검색 (서버가 네이버 지역 검색을 대신 호출). near를 주면 가까운 순.
  Future<List<PlaceCandidate>> searchPlaces(String query, {LatLng? near});

  /// 검색 결과를 먹로그 식당으로 등록한다. 이미 있으면 기존 식당을 돌려준다.
  Future<Place> createPlace(PlaceCandidate candidate);

  /// 사진 한 장을 올리고 기록에 담을 주소를 돌려준다.
  Future<String> uploadPhoto(List<int> bytes, String filename);
}

/// 사용자에게 그대로 보여 줄 수 있는 메시지를 담은 오류.
class MuklogException implements Exception {
  const MuklogException(this.message, {this.statusCode});
  final String message;

  /// 서버 응답 코드 (401이면 세션 만료로 보고 로그인 화면으로 보낸다)
  final int? statusCode;

  @override
  String toString() => message;
}
