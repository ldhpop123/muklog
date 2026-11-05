from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_recommend_sorted_with_reason():
    res = client.get("/recommend").json()
    scores = [r["score"] for r in res]
    assert scores == sorted(scores, reverse=True)
    assert res[0]["place"]["name"] == "서교 순댓국"
    assert "민수" in res[0]["reason"]


def test_party_excludes_member_dislikes():
    # 지은(u2)은 국밥을 불호로 등록해 두었다.
    res = client.post("/recommend/party", json={"member_ids": ["u1", "u2"]})
    assert res.status_code == 200
    ids = [r["place"]["id"] for r in res.json()]
    assert "p1" not in ids
    assert len(ids) == 3
    assert all(r["reason"] for r in res.json())


def test_create_record_counts_visit_no():
    body = {"place_id": "p1", "rating": 4.0, "memo": "또 왔다"}
    first = client.post("/records", json=body).json()
    second = client.post("/records", json=body).json()
    assert second["visit_no"] == first["visit_no"] + 1


def test_friend_private_record_is_hidden(monkeypatch):
    from datetime import datetime

    from app import store
    from app.schemas import Record

    secret = Record(id="secret", user_id="u2", place_id="p4", rating=5.0, visit_no=9,
                    visited_at=datetime(2026, 11, 2), visibility="private")
    monkeypatch.setattr(store, "records", [*store.records, secret])

    assert all(r["id"] != "secret" for r in client.get("/places/p4/records").json())
    p4 = next(r for r in client.get("/recommend").json() if r["place"]["id"] == "p4")
    assert p4["reason"] is None


def test_party_rejects_non_friend(monkeypatch):
    from app import store

    monkeypatch.setitem(store.follows, "me", {"u1"})
    res = client.post("/recommend/party", json={"member_ids": ["u2"]})
    assert res.status_code == 403


def test_record_updates_place_and_my_taste():
    from app import store

    before_me = store.users["me"].taste.as_list()
    before_place = store.places["p2"].taste.spiciness
    res = client.post("/records", json={"place_id": "p2", "rating": 5.0, "memo": "얼얼한 마라, 맵부심 자극"})
    assert res.status_code == 201
    rid = res.json()["id"]

    attrs = client.get(f"/records/{rid}/attributes").json()
    assert attrs["spiciness"] > 0.5
    assert attrs["saltiness"] is None
    assert store.places["p2"].revisit_total == 4
    assert store.places["p2"].taste.spiciness != before_place
    # 매운 식당에 5점을 줬으니 내 매운맛 차원이 올라간다.
    after_me = store.users["me"].taste.as_list()
    assert after_me[1] > before_me[1]


def test_inspired_record_raises_recommender_trust():
    from app import store

    before = store.users["u1"].trust_temp
    for _ in range(3):
        res = client.post("/records", json={"place_id": "p1", "rating": 4.5, "inspired_by_record_id": "r1"})
        assert res.status_code == 201
    assert store.users["u1"].trust_temp > before
    assert len(store.trust_events) == 3


def test_disagreeing_visit_lowers_trust():
    from app import store

    before = store.users["u1"].trust_temp
    client.post("/records", json={"place_id": "p1", "rating": 1.0, "inspired_by_record_id": "r1"})
    assert store.users["u1"].trust_temp < before


def test_inspired_record_validation():
    bad_place = client.post("/records", json={"place_id": "p2", "rating": 4, "inspired_by_record_id": "r1"})
    assert bad_place.status_code == 400
    missing = client.post("/records", json={"place_id": "p1", "rating": 4, "inspired_by_record_id": "nope"})
    assert missing.status_code == 400


def test_inspired_by_private_record_is_rejected(monkeypatch):
    from datetime import datetime

    from app import store
    from app.schemas import Record

    secret = Record(id="secret", user_id="u2", place_id="p4", rating=5.0, visit_no=1,
                    visited_at=datetime(2026, 11, 2), visibility="private")
    store.records.append(secret)
    res = client.post("/records", json={"place_id": "p4", "rating": 5, "inspired_by_record_id": "secret"})
    assert res.status_code == 400


def test_couple_with_friend():
    res = client.get("/users/u1/couple").json()
    assert 90 <= res["percent"] <= 100
    assert len(res["dimensions"]) == 5
    assert res["user"]["nickname"] == "민수"
    # 민수는 p1, p3을 4점 이상 줬고 나는 둘 다 안 가 봤다.
    assert {s["place"]["id"] for s in res["suggestions"]} == {"p1", "p3"}


def test_couple_rejects_non_friend(monkeypatch):
    from app import store

    monkeypatch.setitem(store.follows, "me", {"u1"})
    assert client.get("/users/u2/couple").status_code == 403


def test_my_dislikes_filter_recommendations():
    res = client.put("/users/me/dislikes", json=[{"target": "중식", "kind": "불호"}, {"target": "중식"}])
    assert len(res.json()) == 1
    ids = [r["place"]["id"] for r in client.get("/recommend").json()]
    assert "p2" not in ids


def test_recommend_with_location_adds_distance():
    res = client.get("/recommend", params={"lat": 37.5550, "lng": 126.9205}).json()
    assert all("km" in r["reason"] for r in res)
    assert client.get("/recommend", params={"lat": 37.5}).status_code == 422


def test_places_filters():
    assert {p["id"] for p in client.get("/places", params={"tags": "노포"}).json()} == {"p1", "p3"}
    assert {p["id"] for p in client.get("/places", params={"layer": "friends"}).json()} == {"p1", "p2", "p3"}
    assert client.get("/places", params={"layer": "mine"}).json() == []
    box = "37.550,126.915,37.556,126.922"
    assert [p["id"] for p in client.get("/places", params={"bbox": box}).json()] == ["p1"]
    assert client.get("/places", params={"bbox": "1,2"}).status_code == 422


def test_briefing_template():
    res = client.get("/briefing", params={"area": "홍대"}).json()
    assert res["generated_by"] == "template"
    assert res["sentences"][0]["text"].startswith("홍대에서는")
    assert "민수님은 4번이나" in res["sentences"][0]["text"]
    assert {i for s in res["sentences"] for i in s["record_ids"]} <= {"r1", "r2", "r4"}
    assert client.get("/briefing", params={"area": "부산"}).status_code == 404
    empty = client.get("/briefing", params={"area": "성수"}).json()
    assert empty["places"] == []
    assert empty["sentences"][0]["text"] == "아직 성수에 친구 기록이 없어요. 먼저 다녀온 곳을 기록해 보세요."


def test_briefing_drops_unsupported_llm_sentences(monkeypatch):
    from app import llm

    fake = {"sentences": [
        {"text": "근거 있는 문장", "record_ids": ["r1"]},
        {"text": "지어낸 문장", "record_ids": ["r999"]},
    ]}
    monkeypatch.setattr(llm, "complete_json", lambda *a, **k: fake)
    res = client.get("/briefing", params={"area": "홍대"}).json()
    assert res["generated_by"] == "llm"
    assert [s["text"] for s in res["sentences"]] == ["근거 있는 문장"]


def test_ranking():
    res = client.get("/ranking").json()
    assert [e["user"]["id"] for e in res][:2] == ["u1", "u2"]
    assert res[0]["rank"] == 1


def test_all_ranking_hides_non_friend_taste(monkeypatch):
    from app import store

    monkeypatch.setitem(store.follows, "me", {"u1"})
    res = client.get("/ranking", params={"scope": "all"}).json()
    assert "u2" in {e["user"]["id"] for e in res}
    assert all("taste" not in e["user"] for e in res)


def test_private_record_does_not_change_place():
    from app import store

    before = store.places["p2"].taste
    client.post("/records", json={"place_id": "p2", "rating": 5, "memo": "노포 감성 가성비", "visibility": "private"})
    assert store.places["p2"].taste == before


def test_repeated_inspired_records_count_once():
    from app import store

    client.post("/records", json={"place_id": "p1", "rating": 4.5, "inspired_by_record_id": "r1"})
    once = store.users["u1"].trust_temp
    for _ in range(5):
        client.post("/records", json={"place_id": "p1", "rating": 4.5, "inspired_by_record_id": "r1"})
    assert store.users["u1"].trust_temp == once
    assert len(store.counted_trust_events("u1")) == 1


def test_one_user_cannot_drag_place_vector():
    from app import store

    client.post("/records", json={"place_id": "p4", "rating": 5, "memo": "얼얼한 마라"})
    one = store.places["p4"].taste.spiciness
    for _ in range(5):
        client.post("/records", json={"place_id": "p4", "rating": 5, "memo": "얼얼한 마라"})
    assert store.places["p4"].taste.spiciness == one


def test_place_tag_needs_two_distinct_users():
    from app import store

    for _ in range(3):
        client.post("/records", json={"place_id": "p4", "rating": 5, "memo": "혼밥하기 좋음"})
    assert "혼밥" not in store.places["p4"].tags


def test_briefing_strips_id_leak_and_caches(monkeypatch):
    from app import llm
    from app.routers import briefing

    calls = []

    def fake(*a, **k):
        calls.append(1)
        return {"sentences": [{"text": "홍대에서는 '서교 순댓국'이 좋아요. record_ids: [\"r1\"]", "record_ids": ["r1"]}]}

    monkeypatch.setattr(llm, "complete_json", fake)
    monkeypatch.setattr(briefing, "_cache", {})
    first = client.get("/briefing", params={"area": "홍대"}).json()
    second = client.get("/briefing", params={"area": "홍대"}).json()
    assert first["sentences"][0]["text"] == "홍대에서는 '서교 순댓국'이 좋아요."
    assert second == first
    assert len(calls) == 1


def test_briefing_drops_sentence_mixing_places(monkeypatch):
    from app import llm
    from app.routers import briefing

    monkeypatch.setattr(llm, "complete_json", lambda *a, **k: {"sentences": [
        {"text": "순댓국 이야기", "record_ids": ["r1"]},
        {"text": "섞인 문장", "record_ids": ["r4", "r2"]},
    ]})
    monkeypatch.setattr(briefing, "_cache", {})
    res = client.get("/briefing", params={"area": "홍대"}).json()
    assert [s["text"] for s in res["sentences"]] == ["순댓국 이야기"]


def test_nearby_areas_from_map_center():
    # 홍대입구역 근처 지도 가운데
    res = client.get("/areas", params={"lat": 37.5565, "lng": 126.9235, "limit": 5}).json()
    assert res[0]["name"] == "홍대"
    assert [a["distance_km"] for a in res] == sorted(a["distance_km"] for a in res)
    counts = {a["name"]: a["record_count"] for a in res}
    # 친구 기록: 홍대(p1 r1·r2, p3 r4) 3건, 연남(p2 r3) 1건, 상수(p4)는 0건
    assert counts["홍대"] == 3
    assert counts["연남"] == 1
    assert counts.get("상수", 0) == 0
    assert client.get("/areas", params={"lat": 37.5}).status_code == 422


def test_districts_do_not_overlap_in_briefing():
    from app import areas

    # 홍대와 연남은 가깝지만 연남 식당(p2)은 홍대 브리핑에 안 나온다.
    hongdae = client.get("/briefing", params={"area": "홍대"}).json()
    assert "p2" not in {p["place"]["id"] for p in hongdae["places"]}
    assert areas.area_of(37.5612, 126.9248) == "연남"
    assert areas.area_of(37.6542, 127.0568) is None


def test_areas_mix_dong_when_no_district_nearby(monkeypatch):
    from app import naver

    monkeypatch.setattr(naver, "admin_dong", lambda lat, lng: "황학동")
    # 신당·황학 근처: 1km 안 상권 없음, 3km 안에는 동묘·왕십리 등
    res = client.get("/areas", params={"lat": 37.5650, "lng": 127.0250}).json()
    assert res[0] == {"kind": "dong", "name": "황학동", "lat": 37.565, "lng": 127.025,
                      "distance_km": 0.0, "record_count": 0}
    assert all(a["kind"] == "area" and a["distance_km"] <= 3 for a in res[1:])
    assert "동묘" in [a["name"] for a in res]
    assert len(res) <= 5


def test_areas_dong_goes_last_when_district_nearby(monkeypatch):
    from app import naver

    monkeypatch.setattr(naver, "admin_dong", lambda lat, lng: "숭인1동")
    res = client.get("/areas", params={"lat": 37.5732, "lng": 127.0163, "limit": 3}).json()
    assert res[0]["name"] == "동묘"
    assert res[-1]["kind"] == "dong" and res[-1]["name"] == "숭인1동"
    assert len(res) == 3


def test_areas_far_from_everything_and_no_key():
    # 상계동: 3km 안 상권 없음, 역지오코딩 키도 없음 → 빈 목록
    assert client.get("/areas", params={"lat": 37.6542, "lng": 127.0568}).json() == []


def test_dong_briefing_includes_all_places_in_dong():
    res = client.get("/briefing", params={"area": "서교동"}).json()
    assert {p["place"]["id"] for p in res["places"]} == {"p1", "p3"}
    empty = client.get("/briefing", params={"area": "숭인1동"}).json()
    assert empty["sentences"][0]["text"] == "아직 숭인1동에 친구 기록이 없어요. 먼저 다녀온 곳을 기록해 보세요."
    assert client.get("/briefing", params={"area": "강남구"}).status_code == 404
