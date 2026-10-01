"""
Cash-flow forecaster - the core model.

Predicts, for a user standing on day `t`, the CUMULATIVE net cash flow over the next
h = 1..30 days, at three quantiles (P10 / P50 / P90).

Cumulative (not per-day) is a deliberate product choice: the app needs a balance
*path* with an honest uncertainty band, and summing independent per-day quantiles
would compound into a nonsense band. Predicting the cumulative directly gives

    balance_path_q[h] = balance_today + cum_q[h]

which is exactly what the "risk window" and the safe-to-save optimiser consume.

Baseline: per-user mean net flow by day-of-month (see panel.dom_profile), accumulated
over the same horizon. That baseline is also supplied to the model as a feature, so
the model is structurally able to match it and is only rewarded for improving on it.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import joblib
import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor

from . import panel, split

MODEL_DIR = Path(__file__).resolve().parent / "artifacts"
MODEL_DIR.mkdir(exist_ok=True)
MODEL_PATH = MODEL_DIR / "forecaster.joblib"
MODEL_VERSION = "forecast-1.0.0"

QUANTILES = (0.10, 0.50, 0.90)

ROLL_CATS = ["income", "food_grocery", "cash_out", "rent", "utility",
             "family_support", "transport"]

FEATURE_NAMES = (
    ["horizon", "tgt_dom", "tgt_dow", "tgt_is_weekend", "tgt_month_progress",
     "baseline_cum", "baseline_dom_mean", "days_to_payday"]
    + ["nf_lag1", "nf_lag2", "nf_lag3", "nf_lag7",
       "nf_roll7", "nf_roll14", "nf_roll30", "nf_std7", "nf_std30",
       "balance_today", "balance_roll30",
       "days_since_inflow", "n_inflow_30", "mean_inflow_30", "income_30",
       "cashout_rate_30", "fee_30", "recurring_share_30"]
    + [f"roll30_{c}" for c in ROLL_CATS]
    + ["archetype", "income_band", "area"]
)
CATEGORICAL_IDX = [FEATURE_NAMES.index(c) for c in ("archetype", "income_band", "area")]

ARCHETYPES = ["gig", "remittance", "salaried", "trader"]
INCOME_BANDS = ["high", "low", "mid"]
AREAS = ["rural", "urban"]


# ---------------------------------------------------------------- features

@dataclass
class Context:
    """Everything derived from the training window, reused at predict time."""
    prof: np.ndarray            # (U, 32) day-of-month mean net flow
    cumprof: np.ndarray         # (U, D+1) cumulative of the dom profile
    cumnf: np.ndarray           # (U, D+1) cumulative actual net flow
    payday: np.ndarray          # (U,) modal day-of-month of largest inflow
    cal: dict
    static: np.ndarray          # (U, 3) encoded archetype / income_band / area


def make_context(p: panel.Panel, upto_idx: int) -> Context:
    prof = panel.dom_profile(p, upto_idx)
    profser = panel.dom_profile_series(p, prof)
    cumprof = np.concatenate([np.zeros((p.n_users, 1)), np.cumsum(profser, axis=1)], axis=1)
    cumnf = np.concatenate([np.zeros((p.n_users, 1)), np.cumsum(p.net_flow, axis=1)], axis=1)

    # payday = day-of-month with the largest mean inflow, learned from history only
    cal = panel.calendar()
    dom = cal["dom"][: upto_idx + 1]
    inc = p.cat_flow["income"][:, : upto_idx + 1]
    by_dom = np.zeros((p.n_users, 32))
    for d in range(1, 32):
        m = dom == d
        if m.any():
            by_dom[:, d] = inc[:, m].mean(axis=1)
    payday = by_dom[:, 1:].argmax(axis=1) + 1

    u = p.users.loc[p.user_ids]
    static = np.column_stack([
        u["archetype"].map({v: i for i, v in enumerate(ARCHETYPES)}).to_numpy(),
        u["income_band"].map({v: i for i, v in enumerate(INCOME_BANDS)}).to_numpy(),
        u["area"].map({v: i for i, v in enumerate(AREAS)}).to_numpy(),
    ]).astype(float)

    return Context(prof=prof, cumprof=cumprof, cumnf=cumnf, payday=payday,
                   cal=cal, static=static)


def _state_features(p: panel.Panel, ctx: Context, t: int) -> np.ndarray:
    """Per-user features describing the state as of day t. Shape (U, n_state)."""
    nf = p.net_flow
    w30 = nf[:, t - 29: t + 1]
    w7 = nf[:, t - 6: t + 1]

    inc = p.cat_flow["income"][:, t - 29: t + 1]
    had_inflow = inc > 0
    # days since last inflow (30 = none in the last 30 days)
    rev = had_inflow[:, ::-1]
    any_inf = rev.any(axis=1)
    days_since = np.where(any_inf, rev.argmax(axis=1), 30).astype(float)

    n_inflow = had_inflow.sum(axis=1).astype(float)
    income_30 = inc.sum(axis=1)
    mean_inflow = np.divide(income_30, n_inflow, out=np.zeros_like(income_30),
                            where=n_inflow > 0)
    cash_30 = p.cat_flow["cash_out"][:, t - 29: t + 1].sum(axis=1)
    fee_30 = p.fees[:, t - 29: t + 1].sum(axis=1)
    recurring_30 = sum(p.cat_flow[c][:, t - 29: t + 1].sum(axis=1)
                       for c in ("rent", "utility", "family_support", "mobile_recharge"))
    denom = np.where(income_30 > 0, income_30, 1.0)

    cols = [
        nf[:, t], nf[:, t - 1], nf[:, t - 2], nf[:, t - 6],
        w7.mean(axis=1), nf[:, t - 13: t + 1].mean(axis=1), w30.mean(axis=1),
        w7.std(axis=1), w30.std(axis=1),
        p.balance[:, t], p.balance[:, t - 29: t + 1].mean(axis=1),
        days_since, n_inflow, mean_inflow, income_30,
        cash_30 / denom, fee_30, recurring_30 / denom,
    ]
    cols += [p.cat_flow[c][:, t - 29: t + 1].mean(axis=1) for c in ROLL_CATS]
    return np.column_stack(cols)


def build_rows(p: panel.Panel, ctx: Context, asof_indices: list[int],
               horizon: int = split.HORIZON, with_target: bool = True):
    """Return X, y, meta for every (user, as-of, horizon) combination."""
    U = p.n_users
    cal = ctx.cal
    Xs, ys, metas = [], [], []

    for t in asof_indices:
        state = _state_features(p, ctx, t)                      # (U, S)
        base_dom_mean = ctx.prof[np.arange(U), cal["dom"][t]]    # scalar per user

        for h in range(1, horizon + 1):
            tgt = t + h
            base_cum = ctx.cumprof[:, tgt + 1] - ctx.cumprof[:, t + 1]
            dom_t = cal["dom"][tgt]
            days_to_payday = (ctx.payday - dom_t) % 31

            head = np.column_stack([
                np.full(U, h, dtype=float),
                np.full(U, dom_t, dtype=float),
                np.full(U, cal["dow"][tgt], dtype=float),
                np.full(U, cal["is_weekend"][tgt]),
                np.full(U, dom_t / cal["days_in_month"][tgt]),
                base_cum,
                base_dom_mean,
                days_to_payday.astype(float),
            ])
            Xs.append(np.hstack([head, state, ctx.static]))
            if with_target:
                ys.append(ctx.cumnf[:, tgt + 1] - ctx.cumnf[:, t + 1])
            metas.append(np.column_stack([np.arange(U), np.full(U, t), np.full(U, h)]))

    X = np.vstack(Xs)
    y = np.concatenate(ys) if with_target else None
    meta = np.vstack(metas)
    return X, y, meta


# ---------------------------------------------------------------- model

class Forecaster:
    def __init__(self, models: dict, version: str = MODEL_VERSION):
        self.models = models                      # quantile -> regressor
        self.version = version

    @classmethod
    def fit(cls, X: np.ndarray, y: np.ndarray, verbose: bool = True) -> "Forecaster":
        models = {}
        for q in QUANTILES:
            m = HistGradientBoostingRegressor(
                loss="quantile", quantile=q,
                max_iter=350, learning_rate=0.08, max_depth=7,
                min_samples_leaf=40, l2_regularization=1.0,
                categorical_features=CATEGORICAL_IDX,
                random_state=7,
            )
            m.fit(X, y)
            if verbose:
                print(f"  fitted quantile {q:.2f}  ({m.n_iter_} iterations)")
            models[q] = m
        return cls(models)

    def predict(self, X: np.ndarray) -> dict:
        out = {q: self.models[q].predict(X) for q in QUANTILES}
        # Quantile models are fitted independently and can cross; enforce monotonicity
        # so the band shown to a customer is never inverted.
        lo, mid, hi = out[0.10], out[0.50], out[0.90]
        lo, hi = np.minimum(lo, hi), np.maximum(lo, hi)
        mid = np.clip(mid, lo, hi)
        return {0.10: lo, 0.50: mid, 0.90: hi}

    def save(self, path: Path = MODEL_PATH) -> None:
        joblib.dump({"models": self.models, "version": self.version}, path)

    @classmethod
    def load(cls, path: Path = MODEL_PATH) -> "Forecaster":
        blob = joblib.load(path)
        return cls(blob["models"], blob["version"])


def baseline_predict(ctx: Context, meta: np.ndarray) -> np.ndarray:
    """Naive seasonal baseline: accumulate the per-user day-of-month mean."""
    u, t, h = meta[:, 0], meta[:, 1], meta[:, 2]
    return ctx.cumprof[u, t + h + 1] - ctx.cumprof[u, t + 1]
