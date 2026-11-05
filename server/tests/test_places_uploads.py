import httpx
from fastapi.testclient import TestClient

from app import naver
from app.main import app

client = TestClient(app)

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 100
ITEMS = [
    {"title": "<b>서교</b> 순댓국 &amp; 국밥", "category": "한식>국밥", "address": "서울특별시 마포구 서교동 400-1",
     "roadAddress": "서울특별시 마포구 와우산로 1", "mapx": "1269205000", "mapy": "375550000"},
    {"title": "망원 <b>순댓국</b>", "category": "한식>순대,순댓국", "address": "서울특별시 마포구 망원동 10",
     "roadAddress": "", "mapx": "1269040000", "mapy": "375560000"},
    {"title": "좌표 없음", "category": "한식", "address": "", "mapx": "", "mapy": ""},
]


class _Res:
    status_code = 200

    def raise_for_status(self):
        pass

    def json(self):
        return {"items": ITEMS}


def _with_naver(monkeypatch, sent=None):
    monkeypatch.setenv("NAVER_SEARCH_CLIENT_ID", "id")
    monkeypatch.setenv("NAVER_SEARCH_CLIENT_SECRET", "secret")

    def fake_get(url, params, headers, timeout):
        if sent is not None:
            sent.update(url=url, params=params, headers=headers)
        return _Res()

    monkeypatch.setattr(httpx, "get", fake_get)


def test_search_calls_api_hub(monkeypatch):
    sent = {}
    _with_naver(monkeypatch, sent)
    client.get("/places/search", params={"query": "순댓국"})
    assert sent["url"] == "https://naverapihub.apigw.ntruss.com/search/v1/local"
    assert sent["params"]["display"] == 5
    assert sent["headers"] == {"X-NCP-APIGW-API-KEY-ID": "id", "X-NCP-APIGW-API-KEY": "secret"}


def test_parse_item_accepts_decimal_degrees():
    p = naver.parse_item({**ITEMS[0], "mapx": "126.9205", "mapy": "37.555"})
    assert (p.lat, p.lng) == (37.555, 126.9205)


def test_parse_item_cleans_title_and_converts_coords():
    p = naver.parse_item(ITEMS[0])
    assert p.name == "서교 순댓국 & 국밥"
    assert p.category == "국밥"
    assert (p.lat, p.lng) == (37.555, 126.9205)
    assert p.external_id == naver.parse_item(ITEMS[0]).external_id
    assert naver.parse_item(ITEMS[2]) is None


def test_search_without_key_is_503(monkeypatch):
    monkeypatch.delenv("NAVER_SEARCH_CLIENT_ID", raising=False)
    monkeypatch.delenv("NAVER_SEARCH_CLIENT_SECRET", raising=False)
    res = client.get("/places/search", params={"query": "순댓국"})
    assert res.status_code == 503
    assert "네이버 검색 API 키" in res.json()["detail"]


def test_search_bad_key_is_503(monkeypatch):
    monkeypatch.setenv("NAVER_SEARCH_CLIENT_ID", "id")
    monkeypatch.setenv("NAVER_SEARCH_CLIENT_SECRET", "bad")
    req = httpx.Request("GET", naver.LOCAL_SEARCH_URL)

    def unauthorized(*a, **k):
        raise httpx.HTTPStatusError("401", request=req, response=httpx.Response(401, request=req))

    monkeypatch.setattr(httpx, "get", unauthorized)
    assert client.get("/places/search", params={"query": "순댓국"}).status_code == 503


def _search(monkeypatch, **params):
    _with_naver(monkeypatch)
    return client.get("/places/search", params={"query": "순댓국", **params}).json()


def _body(candidate):
    return {k: candidate[k] for k in ("external_id", "name", "category", "address", "lat", "lng")}


def test_search_sorts_by_distance_and_marks_registered(monkeypatch):
    # 망원동 근처에서 검색하면 망원 순댓국이 먼저
    res = _search(monkeypatch, lat=37.556, lng=126.904)
    assert [c["name"] for c in res] == ["망원 순댓국", "서교 순댓국 & 국밥"]
    assert all(c["place_id"] is None for c in res)

    created = client.post("/places", json=_body(res[1]))
    assert created.status_code == 201
    again = client.get("/places/search", params={"query": "순댓국"}).json()
    assert {c["name"]: c["place_id"] for c in again}["서교 순댓국 & 국밥"] == created.json()["id"]


def test_search_adds_region_when_location_given(monkeypatch):
    queries = []
    monkeypatch.setenv("NAVER_SEARCH_CLIENT_ID", "id")
    monkeypatch.setenv("NAVER_SEARCH_CLIENT_SECRET", "secret")
    monkeypatch.setattr(naver, "reverse_geocode", lambda lat, lng: "서교동")

    def fake_get(url, params, headers, timeout):
        queries.append(params["query"])
        return _Res()

    monkeypatch.setattr(httpx, "get", fake_get)
    res = client.get("/places/search", params={"query": "칼국수", "lat": 37.5568, "lng": 126.9236}).json()
    assert queries == ["서교동 칼국수", "칼국수"]
    assert len(res) == 2  # 두 검색 결과가 같아서 중복 제거

    queries.clear()
    client.get("/places/search", params={"query": "합정역 칼국수", "lat": 37.5568, "lng": 126.9236})
    assert queries == ["합정역 칼국수"]
    queries.clear()
    client.get("/places/search", params={"query": "칼국수"})
    assert queries == ["칼국수"]


def test_search_falls_back_to_nearest_demo_area(monkeypatch):
    queries = []
    monkeypatch.setenv("NAVER_SEARCH_CLIENT_ID", "id")
    monkeypatch.setenv("NAVER_SEARCH_CLIENT_SECRET", "secret")
    monkeypatch.delenv("NAVER_MAP_CLIENT_ID", raising=False)
    monkeypatch.setattr(httpx, "get", lambda url, params, headers, timeout: queries.append(params["query"]) or _Res())
    client.get("/places/search", params={"query": "칼국수", "lat": 37.5545, "lng": 126.9220})
    assert queries[0] == "홍대 칼국수"


def test_reverse_geocode_parses_area3(monkeypatch):
    monkeypatch.setenv("NAVER_MAP_CLIENT_ID", "id")
    monkeypatch.setenv("NAVER_MAP_CLIENT_SECRET", "secret")
    sent = {}

    class R:
        def raise_for_status(self):
            pass

        def json(self):
            return {"results": [{"name": "legalcode", "region": {"area2": {"name": "마포구"},
                                                                  "area3": {"name": "서교동"}}}]}

    def fake_get(url, params, headers, timeout):
        sent.update(params=params, headers=headers)
        return R()

    monkeypatch.setattr(httpx, "get", fake_get)
    assert naver.reverse_geocode(37.5568, 126.9236) == "서교동"
    assert sent["params"]["coords"] == "126.9236,37.5568"
    assert "x-ncp-apigw-api-key-id" in sent["headers"]


def test_create_place_uses_server_search_data(monkeypatch):
    res = _search(monkeypatch)
    seogyo = next(c for c in res if c["name"].startswith("서교"))
    forged = {**_body(seogyo), "name": "가짜 맛집", "lat": 35.1, "lng": 129.0}
    created = client.post("/places", json=forged)
    assert created.status_code == 201
    assert created.json()["name"] == "서교 순댓국 & 국밥"
    assert created.json()["area"] == "홍대"
    assert client.post("/places", json=forged).status_code == 200

    unknown = {**_body(seogyo), "external_id": "naver:madeup"}
    assert client.post("/places", json=unknown).status_code == 400


def test_create_place_area_from_district(monkeypatch):
    res = _search(monkeypatch)
    mangwon = next(c for c in res if c["name"].startswith("망원"))
    place = client.post("/places", json=_body(mangwon)).json()
    assert place["area"] == "망원"
    # 새 식당에 기록을 남길 수 있다.
    assert client.post("/records", json={"place_id": place["id"], "rating": 4, "memo": "가성비 좋음"}).status_code == 201


def test_upload_and_attach_photo():
    up = client.post("/uploads", files={"file": ("a.jpg", JPEG, "image/jpeg")})
    assert up.status_code == 201
    url = up.json()["url"]
    assert url.startswith("/uploads/") and url.endswith(".jpg")
    assert client.get(url).content == JPEG

    rec = client.post("/records", json={"place_id": "p1", "rating": 4, "photo_urls": [url, url]})
    assert rec.status_code == 201
    assert rec.json()["photo_urls"] == [url]
    listed = client.get("/places/p1/records").json()
    assert any(r["photo_urls"] == [url] for r in listed)


def test_upload_rejects_non_image_and_large():
    assert client.post("/uploads", files={"file": ("x.jpg", b"not an image", "image/jpeg")}).status_code == 415
    big = JPEG + b"\x00" * (10 * 1024 * 1024)
    res = client.post("/uploads", files={"file": ("big.jpg", big, "image/jpeg")})
    assert res.status_code == 413
    assert "10MB" in res.json()["detail"]


def test_upload_limit_without_content_length():
    """Content-Length 없이(청크 전송) 보내도 받는 도중에 끊긴다."""
    def chunks():
        yield b"--b\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.jpg\"\r\n\r\n" + JPEG
        for _ in range(12):
            yield b"\x00" * (1024 * 1024)
        yield b"\r\n--b--\r\n"

    res = client.post("/uploads", content=chunks(), headers={"content-type": "multipart/form-data; boundary=b"})
    assert res.status_code == 413


def test_record_rejects_foreign_or_missing_photos():
    for urls in (["https://evil.example/a.jpg"], ["/uploads/../secret.jpg"], ["/uploads/" + "0" * 32 + ".jpg"],
                 ["/uploads/" + "a" * 32 + ".jpg"] * 1 + ["/uploads/" + "b" * 32 + ".jpg"] * 4):
        res = client.post("/records", json={"place_id": "p1", "rating": 4, "photo_urls": urls})
        assert res.status_code in (400, 422), urls


def test_search_region_detection():
    assert naver.has_region("서교동 칼국수")
    assert naver.has_region("홍대 국밥")
    assert naver.has_region("합정역 파스타")
    assert not naver.has_region("칼국수")
    assert not naver.has_region("순대국")


def test_dislike_matches_comma_category():
    from app.routers.recommend import excluded_by
    from app.schemas import Dislike, Place, TasteVector

    place = Place(id="x", name="홍대순대국", lat=37.55, lng=126.92, area="홍대", category="순대,순댓국",
                  taste=TasteVector.from_list([0.0] * 5))
    assert excluded_by(place, [Dislike(target="순댓국")])
    assert not excluded_by(place, [Dislike(target="마라")])


def test_create_place_sets_admin_dong(monkeypatch):
    res = _search(monkeypatch)
    monkeypatch.setattr(naver, "admin_dong", lambda lat, lng: "서교동")
    place = client.post("/places", json=_body(res[0])).json()
    assert place["dong"] == "서교동"


def test_area_falls_back_to_dong_outside_districts():
    from app import store

    # 노원구 상계동: 상권 목록 밖
    assert store.area_for(37.6542, 127.0568, "서울특별시 노원구 상계동 1") == "상계동"
    assert store.area_for(37.6542, 127.0568, "") == "기타"
