/// 빌드 시 `--dart-define`으로 주입하는 설정값.
///
/// 예: flutter run --dart-define=API_BASE_URL=http://localhost:8010 --dart-define=USE_MOCK=false
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://localhost:8010');

  /// true면 서버 없이 목 데이터로 동작한다. 시연·UI 작업용.
  static const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);

  /// 네이버 클라우드 플랫폼 Maps Client ID. 비어 있으면 임시 지도(PreviewMap)로 동작한다.
  /// 콘솔에 Android 패키지명, iOS Bundle ID, 웹 서비스 URL을 모두 등록해야 한다.
  static const naverMapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

  static bool get hasNaverMap => naverMapClientId.isNotEmpty;

  /// 웹 전용: 네이버 지도 Style Editor에서 POI(장소 라벨)를 끈 커스텀 스타일의 Metadata ID.
  /// 웹 기본 지도는 장소 이름이 타일에 박혀 있어, 친구 핀만 보이게 하려면 이 스타일이 필요하다.
  static const naverMapStyleId = String.fromEnvironment('NAVER_MAP_STYLE_ID');

  /// 카카오 로그인 (developers.kakao.com > 앱 키). 앱에 넣어도 되는 공개 키다.
  static const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
  static const kakaoJsAppKey = String.fromEnvironment('KAKAO_JS_APP_KEY');
  static bool get hasKakao => kakaoNativeAppKey.isNotEmpty || kakaoJsAppKey.isNotEmpty;

  /// 구글 로그인 (Cloud Console > OAuth 클라이언트 ID). 웹 클라이언트 ID는 웹 로그인과,
  /// Android·iOS에서 서버가 검증할 ID 토큰의 대상(serverClientId)으로 쓴다.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static bool get hasGoogle => googleWebClientId.isNotEmpty;
}
