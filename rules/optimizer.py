"""
Safe-to-save optimiser and risk-window detection.

This module is **deterministic business logic, not machine learning**. The guideline
asks that business rules stay distinct from model predictions, so everything here is
pure Python over arrays the forecaster hands in. There is no model, no randomness and
no hidden state: given the same forecast you get the same recommendation, and every
line of the reasoning can be read by an auditor.

The one idea the product rests on:

    Do not ask a customer how much they can save. Compute it from the pessimistic
    end of their own forecast, and never propose an amount that would push them
    below the floor they chose.

So the optimiser consumes the **P10** path, not the median. If the forecast is wrong
in the customer's favour they simply end the month with more than expected; if it is
wrong against them, the 10th-percentile assumption has already absorbed it.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field, asdict
from datetime import date, timedelta

SAVE_INTERVAL_DAYS = 7          # auto-save runs weekly
ROUNDING = 50.0                 # propose round taka amounts


def _floor_to(x: float, step: float = ROUNDING) -> float:
    return math.floor(x / step) * step if x > 0 else 0.0


# --------------------------------------------------------------- risk window

@dataclass
class RiskWindow:
    start_day: int                 # 1-based horizon day
    end_day: int
    start_date: str
    end_date: str
    lowest_balance: float
    lowest_day: int
    shortfall: float               # how far below the floor, at the worst point

    def to_dict(self) -> dict:
        return asdict(self)


def find_risk_window(balance_today: float, p10_cum: list[float], floor: float,
                     as_of: date) -> RiskWindow | None:
    """
    First stretch of days where the pessimistic balance path drops below the floor.

    This is what the Home screen marks in red. It is deliberately computed on P10:
    we want to warn about a shortfall that is *plausible*, not only one that is
    more likely than not.
    """
    # Inputs often arrive as numpy scalars from the forecaster; coerce once here so
    # every value this module returns is a plain float and serialises as JSON.
    balance_today = float(balance_today)
    floor = float(floor)
    path = [balance_today + float(c) for c in p10_cum]
    below = [i for i, b in enumerate(path) if b < floor]
    if not below:
        return None

    start = below[0]
    end = start
    for i in below[1:]:
        if i == end + 1:
            end = i
        else:
            break

    seg = path[start:end + 1]
    low_rel = min(range(len(seg)), key=lambda i: seg[i])
    return RiskWindow(
        start_day=start + 1,
        end_day=end + 1,
        start_date=(as_of + timedelta(days=start + 1)).isoformat(),
        end_date=(as_of + timedelta(days=end + 1)).isoformat(),
        lowest_balance=round(float(seg[low_rel]), 2),
        lowest_day=start + low_rel + 1,
        shortfall=round(float(floor - seg[low_rel]), 2),
    )


# --------------------------------------------------------------- safe to save

@dataclass
class SafeToSave:
    weekly_amount: float
    monthly_equivalent: float
    horizon_total: float            # what the plan accumulates over the horizon
    binding_day: int | None         # the day that limits the amount
    binding_date: str | None
    floor: float
    reasons: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


def max_safe_weekly_save(balance_today: float, p10_cum: list[float], floor: float,
                         as_of: date, weekly_income: float | None = None,
                         income_cap_share: float = 0.40) -> SafeToSave:
    """
    Largest weekly auto-save that never takes the P10 balance path below `floor`.

    A second, product-level constraint applies on top of the safety one: the plan is
    capped at `income_cap_share` of the customer's weekly income. Without it the
    optimiser happily proposes sweeping a large idle wallet balance into savings, which
    is arithmetically safe but is not a savings habit - it is a one-off transfer that
    the customer cannot repeat next month. A plan should be fundable from income.

    Saving `s` every 7 days means that by horizon day d the customer has moved
    `s * (d // 7)` out of the wallet. The constraint is therefore

        balance_today + p10_cum[d] - s * (d // 7)  >=  floor      for every d

    which rearranges to a closed-form bound per day; the answer is the tightest one.
    Scanning every day (rather than only the save days) matters, because the day that
    binds is usually a rent or bill day in between two transfers.
    """
    horizon = len(p10_cum)
    balance_today = float(balance_today)
    floor = float(floor)
    p10_cum = [float(c) for c in p10_cum]
    reasons: list[dict] = []

    if balance_today < floor:
        return SafeToSave(
            weekly_amount=0.0, monthly_equivalent=0.0, horizon_total=0.0,
            binding_day=None, binding_date=None, floor=floor,
            reasons=[{
                "code": "below_floor_today",
                "detail": "Current balance is already below the safety floor.",
                "evidence": {"balance_today": round(balance_today, 2), "floor": floor},
            }],
        )

    best = math.inf
    binding_day = None
    for d in range(1, horizon + 1):
        saves = d // SAVE_INTERVAL_DAYS
        if saves == 0:
            continue
        headroom = balance_today + p10_cum[d - 1] - floor
        bound = headroom / saves
        if bound < best:
            best = bound
            binding_day = d

    weekly = _floor_to(max(best, 0.0)) if best is not math.inf else 0.0
    n_saves = horizon // SAVE_INTERVAL_DAYS

    if weekly_income and weekly_income > 0:
        cap = _floor_to(weekly_income * income_cap_share)
        if cap < weekly:
            reasons.append({
                "code": "income_cap",
                "detail": "Capped so the plan is fundable from income rather than by "
                          "draining the existing wallet balance.",
                "evidence": {
                    "safe_by_forecast": weekly,
                    "weekly_income": round(weekly_income, 2),
                    "cap_share": income_cap_share,
                    "capped_to": cap,
                },
            })
            weekly = cap

    if weekly <= 0:
        reasons.append({
            "code": "no_headroom",
            "detail": "The pessimistic forecast leaves no room above the safety floor.",
            "evidence": {
                "tightest_day": binding_day,
                "projected_balance": round(balance_today + p10_cum[binding_day - 1], 2)
                if binding_day else None,
                "floor": floor,
            },
        })
    else:
        reasons.append({
            "code": "binding_day",
            "detail": "This is the tightest day in the next 30 days; the amount is "
                      "sized so the balance still clears the floor on that day.",
            "evidence": {
                "day": binding_day,
                "date": (as_of + timedelta(days=binding_day)).isoformat(),
                "projected_balance_p10": round(balance_today + p10_cum[binding_day - 1], 2),
                "floor": floor,
            },
        })
        reasons.append({
            "code": "pessimistic_basis",
            "detail": "Computed on the 10th-percentile forecast, so a worse-than-"
                      "expected month is already absorbed.",
            "evidence": {"quantile": 0.10},
        })

    return SafeToSave(
        weekly_amount=weekly,
        monthly_equivalent=round(weekly * 52 / 12, 2),
        horizon_total=round(weekly * n_saves, 2),
        binding_day=binding_day,
        binding_date=(as_of + timedelta(days=binding_day)).isoformat() if binding_day else None,
        floor=floor,
        reasons=reasons,
    )


def simulate_plan(balance_today: float, cum_path: list[float], floor: float,
                  weekly_amount: float) -> dict:
    """
    Replay a savings plan against a forecast path. Used by the tests and by the
    evaluation to check that a proposed plan never breaches the floor.
    """
    balance_today = float(balance_today)
    floor = float(floor)
    cum_path = [float(c) for c in cum_path]
    balance, saved, min_balance, breaches = balance_today, 0.0, math.inf, 0
    for d in range(1, len(cum_path) + 1):
        bal = balance_today + cum_path[d - 1] - weekly_amount * (d // SAVE_INTERVAL_DAYS)
        saved = weekly_amount * (d // SAVE_INTERVAL_DAYS)
        min_balance = min(min_balance, bal)
        if bal < floor:
            breaches += 1
        balance = bal
    return {
        "final_balance": round(balance, 2),
        "total_saved": round(saved, 2),
        "min_balance": round(min_balance, 2),
        "days_below_floor": breaches,
        "breached": breaches > 0,
    }


# --------------------------------------------------------------- goal planning

@dataclass
class GoalPlan:
    goal_amount: float
    deadline_days: int
    verdict: str                   # feasible | tight | not_feasible
    safe_weekly: float
    required_weekly: float
    projected_total: float
    coverage: float                # projected / goal
    alternatives: list[dict] = field(default_factory=list)
    reasons: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


def plan_goal(goal_amount: float, deadline_days: int, safe_weekly: float,
              as_of: date, monthly_avoidable_fees: float = 0.0) -> GoalPlan:
    """
    Turn a customer goal into an honest verdict plus trade-offs.

    The guideline's own worked example is "I need to save BDT 30,000 in six months" ->
    "build a target plan, identify feasible monthly contributions, and show trade-offs".
    Showing the trade-off is the point: an app that always says yes is not helping.
    """
    weeks = max(deadline_days // SAVE_INTERVAL_DAYS, 1)
    projected = safe_weekly * weeks
    required = goal_amount / weeks
    coverage = projected / goal_amount if goal_amount > 0 else 1.0

    if coverage >= 1.0:
        verdict = "feasible"
    elif coverage >= 0.85:
        verdict = "tight"
    else:
        verdict = "not_feasible"

    reasons = [{
        "code": "capacity_vs_requirement",
        "detail": "Compares what the forecast says is safely available against what "
                  "the goal demands.",
        "evidence": {
            "safe_weekly": safe_weekly,
            "required_weekly": round(required, 2),
            "weeks_available": weeks,
            "projected_total": round(projected, 2),
            "goal_amount": goal_amount,
        },
    }]

    alternatives: list[dict] = []
    if verdict != "feasible" and safe_weekly > 0:
        weeks_needed = math.ceil(goal_amount / safe_weekly)
        extra_weeks = weeks_needed - weeks
        alternatives.append({
            "code": "extend_deadline",
            "detail": "Keep the same weekly amount and move the target date.",
            "new_deadline_days": weeks_needed * SAVE_INTERVAL_DAYS,
            "new_deadline_date": (as_of + timedelta(days=weeks_needed * SAVE_INTERVAL_DAYS)).isoformat(),
            "extra_weeks": extra_weeks,
        })

    if monthly_avoidable_fees > 0:
        extra_weekly = monthly_avoidable_fees * 12 / 52
        combined = (safe_weekly + extra_weekly) * weeks
        alternatives.append({
            "code": "redirect_cash_out_fees",
            "detail": "Replace avoidable cash-outs with digital payments and redirect "
                      "the fee saved into the goal.",
            "extra_weekly": round(extra_weekly, 2),
            "new_projected_total": round(combined, 2),
            "closes_gap": combined >= goal_amount,
        })

    if verdict == "not_feasible" and safe_weekly <= 0:
        alternatives.append({
            "code": "lower_floor_or_reduce_outflow",
            "detail": "There is no safe capacity at the current safety floor. Either "
                      "lower the floor deliberately, or reduce a recurring outflow.",
        })

    return GoalPlan(
        goal_amount=goal_amount,
        deadline_days=deadline_days,
        verdict=verdict,
        safe_weekly=safe_weekly,
        required_weekly=round(required, 2),
        projected_total=round(projected, 2),
        coverage=round(coverage, 4),
        alternatives=alternatives,
        reasons=reasons,
    )
