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
