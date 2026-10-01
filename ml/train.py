"""
Train both models. Nothing here touches the holdout window (see ml/split.py).

    python -m ml.train
"""
from __future__ import annotations

import time

import numpy as np
import pandas as pd

from . import categorizer, forecast, panel, split

DATA = panel.DATA


def train_forecaster() -> None:
    print("\n=== cash-flow forecaster ===")
    p = panel.get()
    ctx = forecast.make_context(p, split.TRAIN_END_IDX)

    asof = split.asof_indices()
    t0 = time.time()
    X, y, meta = forecast.build_rows(p, ctx, asof)
    print(f"  rows: {X.shape[0]:,} x {X.shape[1]} features "
          f"({time.time() - t0:.1f}s to build)")
    assert (meta[:, 1] + meta[:, 2]).max() <= split.TRAIN_END_IDX, "holdout leaked into training"

    # Split by user: the calibration fold is never fitted on, so its residuals are
    # genuine out-of-sample residuals gathered across the whole history.
    calib_users = split.calib_user_mask(p.n_users)
    is_calib = calib_users[meta[:, 0]]
    print(f"  fit fold: {(~is_calib).sum():,} rows from {(~calib_users).sum()} users | "
          f"calibration fold: {is_calib.sum():,} rows from {calib_users.sum()} users")

    t0 = time.time()
    model = forecast.Forecaster.fit(X[~is_calib], y[~is_calib])
    print(f"  trained in {time.time() - t0:.1f}s")

    cal = model.calibrate(X[is_calib], y[is_calib], meta[is_calib])
    print(f"  conformal lower margin: h=1 -{cal[1][0]:,.0f}  "
          f"h=15 -{cal[15][0]:,.0f}  h=30 -{cal[30][0]:,.0f}")

    model.save()
    print(f"  saved -> {forecast.MODEL_PATH.name}")


def train_categorizer() -> None:
    print("\n=== transaction categoriser ===")
    tx = pd.read_csv(DATA / "transactions.csv", parse_dates=["date"])
    train = tx[tx["date"].dt.date <= split.idx_to_date(split.TRAIN_END_IDX)]
    rng = np.random.default_rng(11)
    if len(train) > 150_000:
        train = train.iloc[rng.choice(len(train), 150_000, replace=False)]
    print(f"  training rows: {len(train):,}")

    t0 = time.time()
    model = categorizer.Categorizer.fit(train)
    model.save()
    print(f"  trained in {time.time() - t0:.1f}s -> {categorizer.MODEL_PATH.name}")


if __name__ == "__main__":
    print(split.describe())
    train_categorizer()
    train_forecaster()
    print("\nDone. Run `python -m ml.evaluate` for holdout metrics.")
