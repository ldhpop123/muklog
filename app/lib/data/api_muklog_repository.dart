import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../models/place.dart';
import '../models/social.dart';
import '../models/taste_vector.dart';
import '../models/user_profile.dart';
import '../models/visit_record.dart';
import 'muklog_repository.dart';

/// FastAPI 서버(`server/`)와 통신하는 구현.
class ApiMuklogRepository implements MuklogRepository {
  ApiMuklogRepository(this._dio);
  final Dio _dio;

  /// 서버가 준 오류 detail(한국어 문장)을 [MuklogException]으로 바꿔 화면에 그대로 띄울 수 있게 한다.
  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] : null;
      if (detail is String) throw MuklogException(detail);
      if (e.type == DioExceptionType.receiveTimeout) {
        throw const MuklogException('서버 응답이 너무 늦어요. 잠시 후 다시 시도해 주세요');
      }
      throw MuklogException(
          '서버와 통신하지 못했어요 (${e.response?.statusCode ?? e.type.name})');
    }
  }

  Future<List<Map<String, dynamic>>> _getList(String path,
          {Map<String, dynamic>? query}) =>
      _call(() async {
        final res = await _dio.get<List<dynamic>>(path, queryParameters: query);
        return res.data!.cast<Map<String, dynamic>>();
      });

  Future<Map<String, dynamic>> _getMap(String path,
          {Map<String, dynamic>? query, Duration? receiveTimeout}) =>
      _call(() async {
        final res = await _dio.get<Map<String, dynamic>>(path,
            queryParameters: query,
            options: receiveTimeout == null
                ? null
                : Options(receiveTimeout: receiveTimeout));
        return res.data!;
      });

  List<ScoredPlace> _scored(List<Map<String, dynamic>> rows) =>
      rows.map(ScoredPlace.fromJson).toList();

  @override
  Future<UserProfile> me() async =>
      UserProfile.fromJson(await _getMap('/users/me'));

  @override
  Future<List<UserProfile>> friends() async =>
      (await _getList('/users/me/friends')).map(UserProfile.fromJson).toList();

  @override
  Future<List<Place>> places({
    List<String> tags = const [],
    MapLayer layer = MapLayer.all,
    LatLng? near,
    double radiusKm = 3,
  }) async {
    String? bbox;
    if (near != null) {
      // 반경을 감싸는 사각형. 위도 1도 ≈ 111km
      final dLat = radiusKm / 111;
      final dLng = radiusKm / (111 * math.cos(near.lat * math.pi / 180));
      bbox = [near.lat - dLat, near.lng - dLng, near.lat + dLat, near.lng + dLng].join(',');
    }
    final rows = await _getList('/places', query: {
      if (tags.isNotEmpty) 'tags': tags,
      'layer': layer.name,
      if (bbox != null) 'bbox': bbox,
    });
    final places = rows.map(Place.fromJson);
    // 사각형 모서리 쪽을 잘라 원형 반경으로 맞춘다.
    return near == null
        ? places.toList()
        : places.where((p) => p.location.distanceKm(near) <= radiusKm).toList();
  }

  @override
  Future<List<VisitRecord>> recordsForPlace(String placeId) async =>
      (await _getList('/places/$placeId/records'))
          .map(VisitRecord.fromJson)
          .toList();

  @override
  Future<List<ScoredPlace>> recommend({LatLng? near}) async =>
      _scored(await _getList('/recommend',
          query: near == null ? null : {'lat': near.lat, 'lng': near.lng}));

  @override
  Future<List<ScoredPlace>> partyRecommend(List<String> memberIds) =>
      _call(() async {
        final res = await _dio.post<List<dynamic>>('/recommend/party',
            data: {'member_ids': memberIds});
        return _scored(res.data!.cast<Map<String, dynamic>>());
      });

  @override
  Future<void> saveOnboarding(TasteVector taste) =>
      _call(() => _dio.put('/users/me/taste', data: taste.toJson()));

  @override
  Future<void> createRecord(VisitRecord record) =>
      _call(() => _dio.post('/records', data: {
            'place_id': record.placeId,
            'rating': record.rating,
            'memo': record.memo,
            'tags': record.tags,
            'visibility': record.visibility.name,
            'inspired_by_record_id': record.inspiredByRecordId,
          }));

  @override
  Future<Coupling> couple(String friendId) async =>
      Coupling.fromJson(await _getMap('/users/$friendId/couple'));

  @override
  Future<Briefing> briefing(String area) async =>
      // 서버가 LLM(MUKLOG_LLM=ollama|claude)으로 요약하면 10초 넘게 걸릴 수 있다.
      Briefing.fromJson(await _getMap('/briefing',
          query: {'area': area}, receiveTimeout: const Duration(seconds: 30)));

  @override
  Future<List<RankingEntry>> ranking(RankingScope scope) async =>
      (await _getList('/ranking', query: {'scope': scope.name}))
          .map(RankingEntry.fromJson)
          .toList();

  @override
  Future<List<Dislike>> dislikes() async =>
      (await _getList('/users/me/dislikes')).map(Dislike.fromJson).toList();

  @override
  Future<List<Dislike>> saveDislikes(List<Dislike> items) => _call(() async {
        final res = await _dio.put<List<dynamic>>('/users/me/dislikes',
            data: items.map((d) => d.toJson()).toList());
        return res.data!
            .cast<Map<String, dynamic>>()
            .map(Dislike.fromJson)
            .toList();
      });
}
