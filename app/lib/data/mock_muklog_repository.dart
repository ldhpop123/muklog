import 'dart:math' as math;

import '../models/place.dart';
import '../models/social.dart';
import '../models/taste_vector.dart';
import '../models/user_profile.dart';
import '../models/visit_record.dart';
import 'muklog_repository.dart';

/// 서버 없이 UI·시연을 진행하기 위한 홍대 일대 목 데이터.
/// 시드 값과 규칙(불호 제외, 볼 수 있는 기록, 400 조건 등)은 server/app/store.py와 맞춘다.
class MockMuklogRepository implements MuklogRepository {
  UserProfile _me = const UserProfile(
    id: 'me',
    nickname: '나',
    avatarUrl: 'https://api.dicebear.com/9.x/thumbs/png?seed=me',
    taste: TasteVector(
        saltiness: -0.4,
        spiciness: 0.3,
        ambience: -0.6,
        value: 0.7,
        cuisine: -0.5),
  );

  final _friends = const [
    UserProfile(
      id: 'u1',
      nickname: '민수',
      avatarUrl: 'https://api.dicebear.com/9.x/thumbs/png?seed=minsu',
      taste: TasteVector(
          saltiness: -0.5,
          spiciness: 0.2,
          ambience: -0.8,
          value: 0.6,
          cuisine: -0.6),
      trustTemp: 42.1,
      level: '지역 감별사',
      title: '홍대 국밥 감별사',
    ),
    UserProfile(
      id: 'u2',
      nickname: '지은',
      avatarUrl: 'https://api.dicebear.com/9.x/thumbs/png?seed=jieun',
      taste: TasteVector(
          saltiness: 0.3,
          spiciness: 0.8,
          ambience: 0.5,
          value: -0.2,
          cuisine: 0.4),
      trustTemp: 38.4,
      level: '동네 맛잘알',
    ),
    UserProfile(
      id: 'u3',
      nickname: '현우',
      avatarUrl: 'https://api.dicebear.com/9.x/thumbs/png?seed=hyunwoo',
      taste: TasteVector(
          saltiness: 0.1,
          spiciness: -0.3,
          ambience: -0.2,
          value: 0.9,
          cuisine: -0.3),
      trustTemp: 36.9,
      level: '동네 맛잘알',
    ),
  ];

  final _places = const [
    Place(
      id: 'p1',
      name: '서교 순댓국',
      location: LatLng(37.5550, 126.9205),
      area: '홍대',
      category: '국밥',
      taste: TasteVector(
          saltiness: -0.5,
          spiciness: 0.0,
          ambience: -0.9,
          value: 0.8,
          cuisine: -0.9),
      tags: ['노포', '아재입맛', '혼밥'],
      revisitTotal: 11,
    ),
    Place(
      id: 'p2',
      name: '연남 마라공방',
      location: LatLng(37.5612, 126.9248),
      area: '연남',
      category: '중식',
      taste: TasteVector(
          saltiness: 0.6,
          spiciness: 0.9,
          ambience: 0.3,
          value: 0.2,
          cuisine: 0.5),
      tags: ['매운맛', '데이트'],
      revisitTotal: 3,
    ),
    Place(
      id: 'p3',
      name: '홍대 골목포차',
      location: LatLng(37.5534, 126.9241),
      area: '홍대',
      category: '주점',
      taste: TasteVector(
          saltiness: 0.2,
          spiciness: 0.3,
          ambience: -0.4,
          value: 0.6,
          cuisine: -0.4),
      tags: ['안주맛집', '노포'],
      revisitTotal: 7,
    ),
    Place(
      id: 'p4',
      name: '상수 파스타랩',
      location: LatLng(37.5478, 126.9227),
      area: '상수',
      category: '양식',
      taste: TasteVector(
          saltiness: 0.0,
          spiciness: -0.4,
          ambience: 0.9,
          value: -0.5,
          cuisine: 0.9),
      tags: ['데이트', '감성'],
      revisitTotal: 2,
    ),
  ];

  final _records = <VisitRecord>[
    VisitRecord(
      id: 'r1',
      userId: 'u1',
      placeId: 'p1',
      rating: 4.5,
      visitNo: 4,
      memo: '간이 슴슴해서 매일 먹어도 질리지 않음. 오래된 노포 느낌 그대로.',
      visitedAt: DateTime(2026, 10, 28),
      tags: ['노포', '아재입맛'],
    ),
    VisitRecord(
      id: 'r2',
      userId: 'u3',
      placeId: 'p1',
      rating: 4.0,
      visitNo: 2,
      memo: '이 가격에 이 양이면 무조건 재방문.',
      visitedAt: DateTime(2026, 10, 15),
      tags: ['가성비'],
    ),
    VisitRecord(
      id: 'r3',
      userId: 'u2',
      placeId: 'p2',
      rating: 5.0,
      visitNo: 1,
      memo: '맵부심 자극하는 맛. 얼얼함이 오래 감.',
      visitedAt: DateTime(2026, 11, 1),
      tags: ['매운맛'],
    ),
    VisitRecord(
      id: 'r4',
      userId: 'u1',
      placeId: 'p3',
      rating: 4.0,
      visitNo: 3,
      memo: '분위기 좋은 안주 맛집. 계란말이 필수.',
      visitedAt: DateTime(2026, 10, 20),
      tags: ['안주맛집'],
    ),
  ];

  final _dislikes = <String, List<Dislike>>{
    'u2': [const Dislike('국밥')],
    'u3': [const Dislike('갑각류', kind: DislikeKind.allergy)],
  };

  UserProfile? _friend(String id) =>
      _friends.where((f) => f.id == id).firstOrNull;

  bool _excluded(Place p, Iterable<Dislike> ds) => ds.any((d) =>
      d.target == p.category ||
      p.tags.contains(d.target) ||
      p.name.contains(d.target));

  /// 내가 볼 수 있는 기록: 내 기록 전부 + 친구의 비공개 아닌 기록.
  bool _canSee(VisitRecord r) =>
      r.userId == _me.id ||
      (_friend(r.userId) != null && r.visibility != RecordVisibility.private);

  Iterable<VisitRecord> get _visible => _records.where(_canSee);

  @override
  Future<UserProfile> me() async => _me;

  @override
  Future<List<UserProfile>> friends() async => _friends;

  @override
  Future<List<Place>> places({
    List<String> tags = const [],
    MapLayer layer = MapLayer.all,
    LatLng? near,
    double radiusKm = 3,
  }) async {
    final authors = switch (layer) {
      MapLayer.all => null,
      MapLayer.friends => _friends.map((f) => f.id).toSet(),
      MapLayer.mine => {_me.id},
    };
    final allowed = authors == null
        ? null
        : _visible
            .where((r) => authors.contains(r.userId))
            .map((r) => r.placeId)
            .toSet();
    return _places
        .where((p) => tags.isEmpty || p.tags.any(tags.contains))
        .where((p) => allowed == null || allowed.contains(p.id))
        .where((p) => near == null || p.location.distanceKm(near) <= radiusKm)
        .toList();
  }

  @override
  Future<List<VisitRecord>> recordsForPlace(String placeId) async =>
      _visible.where((r) => r.placeId == placeId).toList();

  @override
  Future<List<ScoredPlace>> recommend({LatLng? near}) async {
    // README 6.4의 Score(u, i). Context 보정은 서버와 같은 거리 감쇠(1.5km에서 절반). 내 불호 식당은 뺀다.
    final mine = _dislikes[_me.id] ?? const [];
    final scored = _places.where((p) => !_excluded(p, mine)).map((p) {
      var friendSignal = 0.0;
      String? reason;
      for (final r in _visible.where((r) => r.placeId == p.id)) {
        final f = _friend(r.userId);
        if (f == null) continue; // 내 기록은 친구 신호에서 제외
        final sim = math.max(0.0, _me.taste.cosine(f.taste));
        final trust = ((f.trustTemp - 30) / 20).clamp(0.0, 1.0);
        friendSignal += sim * trust * r.visitNo;
        reason ??=
            '${f.nickname}님(입맛 ${_me.taste.couplePercent(f.taste)}%)이 ${r.visitNo}번 방문';
      }
      final km = near == null ? null : p.location.distanceKm(near);
      if (km != null) {
        final d = '${km.toStringAsFixed(1)}km';
        reason = reason == null ? d : '$reason · $d';
      }
      final context = km == null ? 1.0 : 1 / (1 + km / 1.5);
      final score = _me.taste.cosine(p.taste) *
          (1 + math.log(1 + friendSignal)) *
          context;
      return ScoredPlace(p, score, reason: reason);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  @override
  Future<List<ScoredPlace>> partyRecommend(List<String> memberIds) async {
    // README 6.5: 0.7 × 평균 만족 + 0.3 × 최소 만족. 구성원 누구든 불호인 식당은 뺀다.
    final members = [_me, ..._friends.where((f) => memberIds.contains(f.id))];
    final groupDislikes =
        members.expand((m) => _dislikes[m.id] ?? const <Dislike>[]);
    final scored = _places.where((p) => !_excluded(p, groupDislikes)).map((p) {
      final sats = members.map((m) => m.taste.cosine(p.taste)).toList();
      final avg = sats.reduce((a, b) => a + b) / sats.length;
      final min = sats.reduce(math.min);
      return ScoredPlace(p, 0.7 * avg + 0.3 * min,
          // 커플링 지수와 같은 0~100% 척도로 보여 준다.
          reason: '${members.length}명 평균 적합도 ${(50 * (1 + avg)).round()}%');
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  @override
  Future<void> saveOnboarding(TasteVector taste) async =>
      _me = _me.copyWith(taste: taste);

  @override
  Future<void> createRecord(VisitRecord record) async {
    // 서버 POST /records의 400 조건과 같다.
    final sourceId = record.inspiredByRecordId;
    if (sourceId != null) {
      final source = _visible.where((r) => r.id == sourceId).firstOrNull;
      if (source == null) throw const MuklogException('보고 온 기록을 찾을 수 없습니다');
      if (source.userId == _me.id) {
        throw const MuklogException('내 기록을 보고 왔다고 표시할 수 없습니다');
      }
      if (source.placeId != record.placeId) {
        throw const MuklogException('보고 온 기록과 다른 식당입니다');
      }
    }
    final visitNo = 1 +
        _records
            .where(
                (r) => r.userId == record.userId && r.placeId == record.placeId)
            .length;
    _records.add(VisitRecord(
      id: record.id,
      userId: record.userId,
      placeId: record.placeId,
      rating: record.rating,
      memo: record.memo,
      visitNo: visitNo,
      visitedAt: record.visitedAt,
      tags: record.tags,
      visibility: record.visibility,
      inspiredByRecordId: record.inspiredByRecordId,
    ));
  }

  @override
  Future<Coupling> couple(String friendId) async {
    final them = _friend(friendId);
    if (them == null) throw const MuklogException('친구의 입맛만 비교할 수 있습니다');
    final mineV = _me.taste.toList(), theirV = them.taste.toList();
    final myPlaces =
        _visible.where((r) => r.userId == _me.id).map((r) => r.placeId).toSet();
    final theirGood = <String, double>{
      for (final r in _visible.where((r) => r.userId == friendId))
        r.placeId: r.rating,
    };
    final suggestions = [
      for (final e in theirGood.entries)
        if (!myPlaces.contains(e.key) && e.value >= 4)
          () {
            final p = _places.firstWhere((p) => p.id == e.key);
            return ScoredPlace(p, _me.taste.cosine(p.taste),
                reason: '${them.nickname}님 평점 ${e.value.toStringAsFixed(1)}');
          }(),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return Coupling(
      user: them,
      percent: _me.taste.couplePercent(them.taste),
      dimensions: [
        for (var i = 0; i < mineV.length; i++)
          DimensionDiff(
              label: TasteVector.labels[i], me: mineV[i], them: theirV[i]),
      ],
      sharedPlaceCount: myPlaces.intersection(theirGood.keys.toSet()).length,
      suggestions: suggestions.take(3).toList(),
    );
  }

  @override
  Future<Briefing> briefing(String area) async {
    if (!briefingAreas.contains(area)) {
      throw MuklogException('지원하지 않는 지역입니다. 가능한 지역: $briefingAreas');
    }
    final top = (await recommend())
        .where((s) => s.place.area == area && s.reason != null)
        .take(3)
        .toList();
    if (top.isEmpty) {
      return Briefing(
          area: area,
          sentences: ['아직 $area에 친구 기록이 없어요. 먼저 다녀온 곳을 기록해 보세요.'],
          places: const [],
          byLlm: false);
    }
    return Briefing(
      area: area,
      sentences: [
        for (final s in top)
          "'${s.place.name}'은 ${s.reason?.replaceFirst('방문', '다녀간')} 곳이에요. #${s.place.tags.join(' #')}",
      ],
      places: top,
      byLlm: false,
    );
  }

  @override
  Future<List<RankingEntry>> ranking(RankingScope scope) async {
    // 목 데이터에는 친구 외 유저가 없어 두 범위가 같다.
    final users = [_me, ..._friends]
      ..sort((a, b) => b.trustTemp.compareTo(a.trustTemp));
    return [
      for (var i = 0; i < users.length; i++)
        RankingEntry(i + 1, PublicUser.fromProfile(users[i]))
    ];
  }

  @override
  Future<List<Dislike>> dislikes() async => _dislikes[_me.id] ?? const [];

  @override
  Future<List<Dislike>> saveDislikes(List<Dislike> items) async {
    final unique = <(String, DislikeKind), Dislike>{
      for (final d in items)
        (d.target.trim(), d.kind): Dislike(d.target.trim(), kind: d.kind),
    };
    return _dislikes[_me.id] = unique.values.toList();
  }
}
