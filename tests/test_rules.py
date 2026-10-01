"""
Tests for the deterministic business-rules layer.

The safety property is the one that matters: the optimiser must never propose a
savings amount that pushes the pessimistic balance path below the customer's floor.
A budgeting app that causes the shortfall it promised to prevent is worse than no app.
"""
from __future__ import annotations

from datetime import date

import numpy as np
import pytest

from rules import leakage, optimizer

AS_OF = date(2026, 8, 31)
HORIZON = 30


def flat_path(daily: float, n: int = HORIZON) -> list[float]:
    """Cumulative path for a constant daily net flow."""
    return list(np.cumsum([daily] * n))


# ---------------------------------------------------------------- safety property

@pytest.mark.parametrize("seed", range(40))
def test_proposed_save_never_breaches_floor(seed: int) -> None:
    rng = np.random.default_rng(seed)
    balance = float(rng.uniform(500, 60_000))
    floor = float(rng.uniform(0, 8_000))
    daily = rng.normal(rng.uniform(-400, 600), 500, HORIZON)
    # a rent-sized shock somewhere in the month, which is usually what binds
    daily[rng.integers(0, HORIZON)] -= rng.uniform(0, 15_000)
    path = list(np.cumsum(daily))

    rec = optimizer.max_safe_weekly_save(balance, path, floor, AS_OF)
    with_plan = optimizer.simulate_plan(balance, path, floor, rec.weekly_amount)
    no_plan = optimizer.simulate_plan(balance, path, floor, 0.0)

    if no_plan["breached"]:
        # The customer is forecast to go short on their own. The optimiser cannot fix
        # that by saving less than nothing - it must simply refuse to make it worse.
        assert rec.weekly_amount == 0.0, (
            f"seed={seed} proposed {rec.weekly_amount} even though the forecast "
            f"already dips to {no_plan['min_balance']} below floor {floor}"
        )
    else:
        assert not with_plan["breached"], (
            f"seed={seed} proposed {rec.weekly_amount} but the plan pushed the path "
            f"to {with_plan['min_balance']} against floor {floor}"
        )


def test_zero_when_already_below_floor() -> None:
    rec = optimizer.max_safe_weekly_save(1_000, flat_path(100), floor=5_000, as_of=AS_OF)
    assert rec.weekly_amount == 0.0
    assert rec.reasons[0]["code"] == "below_floor_today"


def test_comfortable_user_gets_a_meaningful_amount() -> None:
    # 50k in the wallet, steadily positive flow, modest floor
    rec = optimizer.max_safe_weekly_save(50_000, flat_path(300), floor=5_000, as_of=AS_OF)
    assert rec.weekly_amount > 0
    assert rec.weekly_amount % optimizer.ROUNDING == 0, "amounts shown to users are rounded"
    assert rec.binding_day is not None


def test_a_mid_month_shock_lowers_the_recommendation() -> None:
    """
    A large bill on day 10 must shrink the proposed amount for the whole month.

    Note the binding day lands *after* the shock rather than on it: by day 28 four
    weekly transfers have already left the wallet, so the cumulative drain is what
    actually binds. This is why the optimiser scans every day instead of only the
    obvious shock day.
    """
    smooth = [200.0] * HORIZON
    shocked = list(smooth)
    shocked[9] = -20_000.0

    rec_smooth = optimizer.max_safe_weekly_save(25_000, list(np.cumsum(smooth)), 2_000, AS_OF)
    rec_shock = optimizer.max_safe_weekly_save(25_000, list(np.cumsum(shocked)), 2_000, AS_OF)

    assert rec_shock.weekly_amount < rec_smooth.weekly_amount
    assert rec_shock.binding_day >= 10, "the shock must be felt from day 10 onwards"
    assert not optimizer.simulate_plan(
        25_000, list(np.cumsum(shocked)), 2_000, rec_shock.weekly_amount
    )["breached"]


def test_more_headroom_never_lowers_the_recommendation() -> None:
    path = flat_path(100)
    poorer = optimizer.max_safe_weekly_save(20_000, path, 3_000, AS_OF).weekly_amount
    richer = optimizer.max_safe_weekly_save(40_000, path, 3_000, AS_OF).weekly_amount
    assert richer >= poorer


# ---------------------------------------------------------------- risk window

def test_risk_window_found_and_dated() -> None:
    daily = [100.0] * HORIZON
    for d in range(20, 25):
        daily[d] = -6_000.0
    path = list(np.cumsum(daily))

    rw = optimizer.find_risk_window(10_000, path, floor=1_000, as_of=AS_OF)
    assert rw is not None
    assert 20 <= rw.start_day <= 25
    assert rw.shortfall > 0
    assert rw.start_date > AS_OF.isoformat()


def test_no_risk_window_when_comfortable() -> None:
    assert optimizer.find_risk_window(80_000, flat_path(500), 1_000, AS_OF) is None


# ---------------------------------------------------------------- goal planning

def test_feasible_goal() -> None:
    plan = optimizer.plan_goal(20_000, deadline_days=180, safe_weekly=1_000, as_of=AS_OF)
    assert plan.verdict == "feasible"
    assert plan.projected_total >= plan.goal_amount


def test_infeasible_goal_offers_a_longer_deadline() -> None:
    plan = optimizer.plan_goal(30_000, deadline_days=180, safe_weekly=500, as_of=AS_OF)
    assert plan.verdict == "not_feasible"
    codes = {a["code"] for a in plan.alternatives}
    assert "extend_deadline" in codes
    ext = next(a for a in plan.alternatives if a["code"] == "extend_deadline")
    assert ext["new_deadline_days"] > plan.deadline_days


def test_fee_redirection_is_offered_as_a_trade_off() -> None:
    plan = optimizer.plan_goal(30_000, 180, safe_weekly=1_100, as_of=AS_OF,
                               monthly_avoidable_fees=400)
    codes = {a["code"] for a in plan.alternatives}
    assert "redirect_cash_out_fees" in codes


def test_goal_verdict_is_honest_not_encouraging() -> None:
    """An app that always says yes is not helping. Coverage must drive the verdict."""
    tight = optimizer.plan_goal(10_000, 70, safe_weekly=950, as_of=AS_OF)
    assert tight.verdict in ("tight", "not_feasible")
    assert tight.coverage < 1.0


# ---------------------------------------------------------------- leakage

def test_leakage_annualises_and_bounds_the_claim() -> None:
    rep = leakage.analyse(
        cash_out_amounts=[5_000] * 6 + [2_000, 3_500],
        fees_paid=700.0,
        category_totals={"food_grocery": 9_000, "transport": 2_000, "rent": 15_000},
        window_days=90,
    )
    assert rep.fees_annualised == pytest.approx(700 * 365 / 90, rel=1e-6)
    assert 0 <= rep.replaceable_share <= leakage.MAX_REPLACEABLE_SHARE
    assert rep.avoidable_fees_annualised <= rep.fees_annualised
    # the repeated 5,000 withdrawal is the habit to surface first
    assert rep.habitual_amounts[0]["amount"] == 5_000
    assert rep.habitual_amounts[0]["times"] == 6


def test_leakage_claims_nothing_without_digital_behaviour() -> None:
    """No digital spend means no demonstrated substitute, so no avoidability claim."""
    rep = leakage.analyse([5_000, 5_000, 5_000], 300.0, {"rent": 12_000}, 90)
    assert rep.replaceable_share == 0.0
    assert rep.avoidable_fees_annualised == 0.0


def test_leakage_handles_a_user_with_no_cash_outs() -> None:
    rep = leakage.analyse([], 0.0, {"food_grocery": 5_000}, 90)
    assert rep.cash_out_count == 0
    assert rep.fees_annualised == 0.0
    assert rep.replaceable_share == 0.0
