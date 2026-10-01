"""
Orchestration layer: ML predictions + business rules + narrative, assembled per user.

Deliberately framework-free so it can be unit-tested and reused. `api/main.py` is a thin
HTTP wrapper over this.

"Today" in the prototype is the evaluation as-of date (2026-08-31) - the last day any
model was allowed to see. Everything the app shows about "the next 30 days" is therefore
a genuine forward forecast over the untouched holdout, not a replay of known data.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from functools import lru_cache

import numpy as np

from ml import categorizer, forecast, panel, split
from nlg import narrator
from rules import leakage, optimizer

FLOOR_INCOME_SHARE = 0.05
FLOOR_MIN = 1000.0
INSIGHT_WINDOW = 90
RECENT_WINDOW = 30


@dataclass
class Engine:
    p: panel.Panel
    ctx: forecast.Context
    model: forecast.Forecaster
    cat: categorizer.Categorizer
    q10: np.ndarray            # (U, H) cumulative net flow, pessimistic
    q50: np.ndarray
    q90: np.ndarray
    asof_idx: int

    @property
    def as_of(self):
        return split.idx_to_date(self.asof_idx)

    @property
    def model_version(self) -> str:
        return self.model.version


@lru_cache(maxsize=1)
def engine() -> Engine:
    """Load models and precompute every user's forecast once, at startup."""
    p = panel.get()
    ctx = forecast.make_context(p, split.TRAIN_END_IDX)
    model = forecast.Forecaster.load()
    cat = categorizer.Categorizer.load()

    t = split.EVAL_ASOF_IDX
    X, _, meta = forecast.build_rows(p, ctx, [t], with_target=False)
    pred = model.predict(X)

    U, H = p.n_users, split.HORIZON
    q = {k: np.zeros((U, H)) for k in (0.10, 0.50, 0.90)}
    for k in q:
        q[k][meta[:, 0], meta[:, 2] - 1] = pred[k]

    return Engine(p=p, ctx=ctx, model=model, cat=cat,
                  q10=q[0.10], q50=q[0.50], q90=q[0.90], asof_idx=t)


# ------------------------------------------------------------------ helpers

def _floor_for(income: float) -> float:
    return max(income * FLOOR_INCOME_SHARE, FLOOR_MIN)


def list_users(limit: int = 50) -> list[dict]:
    e = engine()
    out = []
    for i in range(min(limit, e.p.n_users)):
        u = e.p.users.loc[e.p.user_ids[i]]
        out.append({
            "user_id": str(e.p.user_ids[i]),
            "archetype": u["archetype"],
            "income_band": u["income_band"],
            "area": u["area"],
            "balance": round(float(e.p.balance[i, e.asof_idx]), 2),
        })
    return out


def profile(user_id: str) -> dict:
    e = engine()
    i = e.p.user_index(user_id)
    u = e.p.users.loc[user_id]
    t = e.asof_idx
    inflow_30 = float(e.p.cat_flow["income"][i, t - 29: t + 1].sum())
    return {
        "user_id": user_id,
        "as_of": e.as_of.isoformat(),
        "archetype": u["archetype"],
        "income_band": u["income_band"],
        "area": u["area"],
        "tenure_months": int(u["tenure_months"]),
        "balance": round(float(e.p.balance[i, t]), 2),
        "safety_floor": round(_floor_for(float(u["monthly_income"])), 2),
        "inflow_last_30d": round(inflow_30, 2),
        "outflow_last_30d": round(float(
            sum(e.p.cat_flow[c][i, t - 29: t + 1].sum()
                for c in panel.CATEGORIES if c != "income")), 2),
        "model_version": e.model_version,
    }


def forecast_for(user_id: str) -> dict:
    e = engine()
    i = e.p.user_index(user_id)
    u = e.p.users.loc[user_id]
    floor = _floor_for(float(u["monthly_income"]))
    bal = float(e.p.balance[i, e.asof_idx])

    days = [(e.as_of + timedelta(days=h)).isoformat() for h in range(1, split.HORIZON + 1)]
    path = [
        {
            "date": d,
            "day": h + 1,
            "expected": round(bal + e.q50[i, h], 2),
            "low": round(bal + e.q10[i, h], 2),
            "high": round(bal + e.q90[i, h], 2),
        }
        for h, d in enumerate(days)
    ]

    rw = optimizer.find_risk_window(bal, list(e.q10[i]), floor, e.as_of)
    risk_evidence = {"has_risk": rw is not None, "floor": floor}
    if rw:
        risk_evidence.update(rw.to_dict())

    return {
        "user_id": user_id,
        "as_of": e.as_of.isoformat(),
        "balance_today": round(bal, 2),
        "safety_floor": round(floor, 2),
        "path": path,
        "risk_window": rw.to_dict() if rw else None,
        "narrative": {
            "forecast": narrator.say("forecast_summary", {
                "expected_balance_end": bal + e.q50[i, -1],
                "low_balance_end": bal + e.q10[i, -1],
                "high_balance_end": bal + e.q90[i, -1],
            }),
            "risk": narrator.say("risk_window", risk_evidence),
        },
        "reasons": _forecast_reasons(e, i),
        "model_version": e.model_version,
        "disclaimer": "This is a statistical projection from your own transaction "
                      "history, not financial advice or a guarantee.",
    }


def _forecast_reasons(e: Engine, i: int) -> list[dict]:
    """
    What is driving this user's forecast. Derived from the features the model actually
    consumed, not from a generated explanation.
    """
    t = e.asof_idx
    reasons = []
    payday = int(e.ctx.payday[i])
    reasons.append({
        "code": "payday_pattern",
        "detail": "Your income usually arrives around this day of the month.",
        "evidence": {"typical_payday": payday},
    })
    recurring = {
        c: float(e.p.cat_flow[c][i, t - 29: t + 1].sum())
        for c in ("rent", "utility", "family_support", "mobile_recharge")
    }
    recurring = {k: v for k, v in recurring.items() if v > 0}
    if recurring:
        reasons.append({
            "code": "recurring_commitments",
            "detail": "These payments repeat every month and shape the dip.",
            "evidence": {k: round(v, 2) for k, v in recurring.items()},
        })
    nf30 = e.p.net_flow[i, t - 29: t + 1]
    reasons.append({
        "code": "recent_trend",
        "detail": "Your average daily net flow over the last 30 days.",
        "evidence": {"mean_daily_net_flow": round(float(nf30.mean()), 2),
                     "volatility": round(float(nf30.std()), 2)},
    })
    return reasons


def insights(user_id: str) -> dict:
    e = engine()
    i = e.p.user_index(user_id)
    t = e.asof_idx
    lo90 = t - INSIGHT_WINDOW + 1
    lo30 = t - RECENT_WINDOW + 1

    cats90 = {c: float(e.p.cat_flow[c][i, lo90: t + 1].sum()) for c in panel.CATEGORIES}
    cats30 = {c: float(e.p.cat_flow[c][i, lo30: t + 1].sum()) for c in panel.CATEGORIES}

    amounts = [float(a) for a in e.p.cat_flow["cash_out"][i, lo90: t + 1] if a > 0]
    fees = float(e.p.fees[i, lo90: t + 1].sum())
    rep = leakage.analyse(amounts, fees, cats90, window_days=INSIGHT_WINDOW)

    top = sorted(
        ({"category": c, "category_bn": narrator.CATEGORY_BN.get(c, c), "amount": round(v, 2)}
         for c, v in cats30.items() if c != "income" and v > 0),
        key=lambda d: -d["amount"],
    )

    return {
        "user_id": user_id,
        "as_of": e.as_of.isoformat(),
        "window_days": INSIGHT_WINDOW,
        "top_categories_30d": top,
        "leakage": rep.to_dict(),
        "narrative": {
            "spending": narrator.say("spending", {"top_categories": top}),
            "leakage": narrator.say("leakage", rep.to_dict()),
        },
        "model_version": e.cat.version,
    }


def safe_to_save(user_id: str) -> dict:
    e = engine()
    i = e.p.user_index(user_id)
    u = e.p.users.loc[user_id]
    floor = _floor_for(float(u["monthly_income"]))
    bal = float(e.p.balance[i, e.asof_idx])
    weekly_income = float(e.p.cat_flow["income"][i, e.asof_idx - 29: e.asof_idx + 1].sum()) * 7 / 30

    rec = optimizer.max_safe_weekly_save(bal, list(e.q10[i]), floor, e.as_of,
                                         weekly_income=weekly_income)
    d = rec.to_dict()
    d["narrative"] = narrator.say("safe_to_save", d)
    d["user_id"] = user_id
    d["as_of"] = e.as_of.isoformat()
    d["model_version"] = e.model_version
    d["requires_confirmation"] = True      # never executed automatically
    return d


def simulate_goal(user_id: str, goal_amount: float, deadline_days: int) -> dict:
    e = engine()
    sts = safe_to_save(user_id)
    ins = insights(user_id)
    monthly_avoidable = ins["leakage"]["avoidable_fees_annualised"] / 12.0

    plan = optimizer.plan_goal(goal_amount, deadline_days, sts["weekly_amount"],
                               e.as_of, monthly_avoidable_fees=monthly_avoidable)
    d = plan.to_dict()
    d["weeks"] = max(deadline_days // optimizer.SAVE_INTERVAL_DAYS, 1)
    d["narrative"] = narrator.say("goal", d)
    d["user_id"] = user_id
    d["as_of"] = e.as_of.isoformat()
    d["model_version"] = e.model_version
    d["requires_confirmation"] = True
    return d
