import pytest

from app import taste

A = [-0.5, 0.2, -0.8, 0.6, -0.6]


def test_couple_same_is_100():
    assert taste.couple_percent(A, A) == 100


def test_couple_opposite_is_0():
    assert taste.couple_percent(A, [-x for x in A]) == 0


def test_zero_vector_is_neutral():
    assert taste.couple_percent(A, [0] * 5) == 50


def test_friend_revisits_raise_score():
    place = [-0.5, 0.0, -0.9, 0.8, -0.9]
    alone = taste.score(A, place, [])
    with_friend = taste.score(A, place, [(A, 42.0, 4)])
    assert with_friend > alone


def test_opposite_friend_adds_nothing():
    place = [-0.5, 0.0, -0.9, 0.8, -0.9]
    opposite = [-x for x in A]
    assert taste.score(A, place, [(opposite, 50.0, 10)]) == pytest.approx(taste.score(A, place, []))


def test_party_penalizes_one_unhappy_member():
    place = [1, 1, 1, 1, 1]
    happy, unhappy = [1, 1, 1, 1, 1], [-1, -1, -1, -1, -1]
    assert taste.party_score([happy, happy], place) > taste.party_score([happy, unhappy], place)


def test_onboarding_weight_halves_at_five_records():
    assert taste.onboarding_weight(0) == 1
    assert taste.onboarding_weight(5) == 0.5


def test_user_vector_moves_toward_liked_place():
    onboarding = [0.0] * 5
    liked = [1.0, 0.0, 0.0, 0.0, 0.0]
    v = taste.user_vector(onboarding, [(liked, 5.0, 1)])
    assert v[0] > 0
    assert taste.user_vector(onboarding, [(liked, 1.0, 1)])[0] < 0
    assert taste.user_vector(onboarding, []) == onboarding


def test_place_vector_ignores_null_dims():
    prior = [0.0] * 5
    v = taste.place_vector(prior, [[1.0, None, None, None, None]])
    assert v == [0.5, 0.0, 0.0, 0.0, 0.0]


def test_trust_temperature_bayesian():
    assert taste.trust_temperature(36.5, []) == 36.5
    one = taste.trust_temperature(36.5, [(1.0, 1)])
    many = taste.trust_temperature(36.5, [(1.0, 1)] * 20)
    assert 36.5 < one < many
    assert taste.trust_temperature(36.5, [(0.0, 1)]) < 36.5


def test_far_taste_satisfaction_gets_bonus():
    assert taste.trust_event_score(1.0, 20) > taste.trust_event_score(1.0, 90)
    assert taste.trust_event_score(0.4, 20) == 0.4


def test_trust_levels():
    assert taste.trust_level(36.0) == "새내기 먹로거"
    assert taste.trust_level(38.0) == "동네 맛잘알"
    assert taste.trust_level(42.0) == "지역 감별사"
    assert taste.trust_level(46.0) == "먹로그 마스터"


def test_pearson_needs_three():
    assert taste.pearson([1, 2], [1, 2]) is None
    assert taste.pearson([1, 2, 3], [1, 2, 3]) == pytest.approx(1.0)
