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


def test_search_sorts_by_distance_and_marks_registered(monkeypatch):
    _with_naver(monkeypatch)
    # 망원동 근처에서 검색하면 망원 순댓국이 먼저
    res = client.get("/places/search", params={"query": "순댓국", "lat": 37.556, "lng": 126.904}).json()
    assert [c["name"] for c in res] == ["망원 순댓국", "서교 순댓국 & 국밥"]
    assert all(c["place_id"] is None for c in res)

    created = client.post("/places", json={k: res[1][k] for k in
                                           ("external_id", "name", "category", "address", "lat", "lng")})
    assert created.status_code == 201
    again = client.get("/places/search", params={"query": "순댓국"}).json()
    assert {c["name"]: c["place_id"] for c in again}["서교 순댓국 & 국밥"] == created.json()["id"]


def test_create_place_dedup_and_area(monkeypatch):
    body = {"external_id": "naver:abc", "name": "새 국밥", "category": "국밥",
            "address": "서울특별시 마포구 서교동 1", "lat": 37.5552, "lng": 126.9210}
    first = client.post("/places", json=body)
    second = client.post("/places", json=body)
    assert first.status_code == 201 and second.status_code == 200
    assert first.json()["id"] == second.json()["id"]
    assert first.json()["area"] == "홍대"

    far = {**body, "external_id": "naver:far", "address": "서울특별시 마포구 망원동 10", "lat": 37.556, "lng": 126.904}
    assert client.post("/places", json=far).json()["area"] == "망원동"

    # 새 식당에 기록을 남길 수 있고, 지도·브리핑 지역에도 잡힌다.
    rec = client.post("/records", json={"place_id": first.json()["id"], "rating": 4, "memo": "가성비 좋음"})
    assert rec.status_code == 201


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
    assert client.post("/uploads", files={"file": ("big.jpg", big, "image/jpeg")}).status_code == 413


def test_record_rejects_foreign_or_missing_photos():
    for urls in (["https://evil.example/a.jpg"], ["/uploads/../secret.jpg"], ["/uploads/" + "0" * 32 + ".jpg"],
                 ["/uploads/" + "a" * 32 + ".jpg"] * 1 + ["/uploads/" + "b" * 32 + ".jpg"] * 4):
        res = client.post("/records", json={"place_id": "p1", "rating": 4, "photo_urls": urls})
        assert res.status_code in (400, 422), urls


def test_dislike_matches_comma_category():
    from app.routers.recommend import excluded_by
    from app.schemas import Dislike, Place, TasteVector

    place = Place(id="x", name="홍대순대국", lat=37.55, lng=126.92, area="홍대", category="순대,순댓국",
                  taste=TasteVector.from_list([0.0] * 5))
    assert excluded_by(place, [Dislike(target="순댓국")])
    assert not excluded_by(place, [Dislike(target="마라")])
