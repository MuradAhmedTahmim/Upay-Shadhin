"""
Data preparation layer: turns the raw transaction stream into dense
(user x day) matrices.

Deliberately separate from model inference (guideline: "Separate data preparation
from model inference where possible"). Nothing in this module knows about models.
"""
from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import numpy as np
import pandas as pd

from . import split

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
CACHE = ROOT / "ml" / "_panel_cache.npz"

CATEGORIES = [
    "income", "rent", "utility", "mobile_recharge", "family_support",
    "food_grocery", "transport", "cash_out", "other_retail",
]


@dataclass
class Panel:
    user_ids: np.ndarray            # (U,)
    dates: np.ndarray               # (D,) datetime64[D]
    net_flow: np.ndarray            # (U, D)   credits - debits
    balance: np.ndarray             # (U, D)   end-of-day balance
    cat_flow: dict                  # category -> (U, D) absolute amount that day
    fees: np.ndarray                # (U, D)   cash-out fees only
    users: pd.DataFrame             # static attributes, indexed by user_id

    @property
    def n_users(self) -> int:
        return len(self.user_ids)

    @property
    def n_days(self) -> int:
        return len(self.dates)

    def user_index(self, user_id: str) -> int:
        hit = np.where(self.user_ids == user_id)[0]
        if not len(hit):
            raise KeyError(user_id)
        return int(hit[0])


def build(force: bool = False) -> Panel:
    """Build the panel from CSV, caching the dense matrices to .npz."""
    users = pd.read_csv(DATA / "users.csv")
    if CACHE.exists() and not force:
        z = np.load(CACHE, allow_pickle=True)
        return Panel(
            user_ids=z["user_ids"],
            dates=z["dates"],
            net_flow=z["net_flow"],
            balance=z["balance"],
            cat_flow={c: z[f"cat_{c}"] for c in CATEGORIES},
            fees=z["fees"],
            users=users.set_index("user_id"),
        )

    tx = pd.read_csv(DATA / "transactions.csv", parse_dates=["date"])
    tx["signed"] = np.where(tx["direction"] == "credit", tx["amount"], -tx["amount"])
    tx["is_fee"] = tx["counterparty"].str.upper().str.startswith("FEE")

    user_ids = np.array(sorted(tx["user_id"].unique()))
    dates = pd.date_range(split.START_DATE, split.END_DATE, freq="D")
    uidx = {u: i for i, u in enumerate(user_ids)}
    didx = {d: i for i, d in enumerate(dates)}

    U, D = len(user_ids), len(dates)
    ui = tx["user_id"].map(uidx).to_numpy()
    di = tx["date"].map(didx).to_numpy()
    flat = ui * D + di

    net_flow = np.bincount(flat, weights=tx["signed"].to_numpy(), minlength=U * D).reshape(U, D)
    fees = np.bincount(flat[tx["is_fee"].to_numpy()],
                       weights=tx.loc[tx["is_fee"], "amount"].to_numpy(),
                       minlength=U * D).reshape(U, D)

    cat_flow = {}
    for c in CATEGORIES:
        m = (tx["category"] == c).to_numpy()
        cat_flow[c] = np.bincount(flat[m], weights=tx.loc[m, "amount"].to_numpy(),
                                  minlength=U * D).reshape(U, D)

    opening = users.set_index("user_id").loc[user_ids, "opening_balance"].to_numpy()
    balance = opening[:, None] + np.cumsum(net_flow, axis=1)

    np.savez_compressed(
        CACHE,
        user_ids=user_ids,
        dates=dates.values.astype("datetime64[D]"),
        net_flow=net_flow,
        balance=balance,
        fees=fees,
        **{f"cat_{c}": v for c, v in cat_flow.items()},
    )

    return Panel(user_ids=user_ids, dates=dates.values.astype("datetime64[D]"),
                 net_flow=net_flow, balance=balance, cat_flow=cat_flow, fees=fees,
                 users=users.set_index("user_id"))


@lru_cache(maxsize=1)
def get() -> Panel:
    return build()


# --- calendar helpers, shared by features and baseline ---------------------

def calendar() -> dict:
    d = pd.to_datetime(pd.date_range(split.START_DATE, split.END_DATE, freq="D"))
    return {
        "dom": d.day.to_numpy(),
        "dow": d.dayofweek.to_numpy(),
        "is_weekend": np.isin(d.dayofweek.to_numpy(), (4, 5)).astype(float),  # Fri/Sat
        "days_in_month": d.days_in_month.to_numpy(),
    }


def dom_profile(p: Panel, upto_idx: int) -> np.ndarray:
    """
    Per-user mean net flow by day-of-month, computed on TRAINING DAYS ONLY.

    This is the naive seasonal baseline the forecaster must beat, and is also fed
    to the model as a feature so the model can only improve on it, never lose to it.
    Returns (U, 32); index 0 unused.
    """
    cal = calendar()
    dom = cal["dom"][: upto_idx + 1]
    nf = p.net_flow[:, : upto_idx + 1]
    out = np.zeros((p.n_users, 32))
    for d in range(1, 32):
        m = dom == d
        if m.any():
            out[:, d] = nf[:, m].mean(axis=1)
    return out


def dom_profile_series(p: Panel, prof: np.ndarray) -> np.ndarray:
    """Expand a (U,32) day-of-month profile back onto the full (U, D) calendar."""
    dom = calendar()["dom"]
    return prof[:, dom]


if __name__ == "__main__":
    p = build(force=True)
    print(f"panel: {p.n_users} users x {p.n_days} days")
    print(f"net_flow mean {p.net_flow.mean():.1f}, balance mean {p.balance.mean():.0f}")
    print(f"cash-out fees total {p.fees.sum():,.0f}")
