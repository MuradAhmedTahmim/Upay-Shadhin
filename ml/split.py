"""
The single place where the train / holdout cut is made.

Guideline requirement: "Keep a clean test set that is not used to train the model."

Nothing outside this module is allowed to decide what is training data. Feature
construction, model fitting and hyper-parameter choices all read `TRAIN_END_IDX`
from here, and every number reported in docs/metrics.md is computed on days after it.
"""
from __future__ import annotations

from datetime import date, timedelta

# Mirrors data/generate.py
END_DATE = date(2026, 9, 30)
N_DAYS = 270
HOLDOUT_DAYS = 30
HORIZON = 30                      # the product forecasts 30 days ahead

START_DATE = END_DATE - timedelta(days=N_DAYS - 1)          # 2026-01-04
HOLDOUT_START = END_DATE - timedelta(days=HOLDOUT_DAYS - 1)  # 2026-09-01

# Day indices into the panel (0 = START_DATE)
TRAIN_END_IDX = N_DAYS - HOLDOUT_DAYS - 1     # 239 -> 2026-08-31, last trainable day
EVAL_ASOF_IDX = TRAIN_END_IDX                 # forecast is issued standing on 2026-08-31

# As-of dates used to build training rows. Every one of them satisfies
# as_of + HORIZON <= TRAIN_END_IDX, so no training target ever falls in the holdout.
MIN_ASOF_IDX = 60                             # need history for 30-day rolling features
MAX_ASOF_IDX = TRAIN_END_IDX - HORIZON        # 209 -> 2026-08-01
ASOF_STRIDE = 5

# Conformal calibration needs residuals the model never fitted on. We separate the
# calibration set by USER, not by date.
#
# Separating by date was tried first and calibrated badly: a 30-day target window means
# two as-of dates a fortnight apart overlap almost completely, so any date-based split
# either leaks (interleaved dates share outcomes) or collapses to two or three usable
# dates in one short period - and a margin fitted to one quiet fortnight in July does
# not transfer to September.
#
# Splitting by user keeps calibration residuals spread across the entire history while
# staying genuinely out-of-sample: the model has no user-identity feature, so a held-out
# user is new to it in exactly the way a new customer would be.
CALIB_USER_FRACTION = 0.20
CALIB_USER_SEED = 4242


def asof_indices() -> list[int]:
    """Every as-of date used for training and calibration alike."""
    return list(range(MIN_ASOF_IDX, MAX_ASOF_IDX + 1, ASOF_STRIDE))


# Kept as an alias so callers read naturally; the fit/calibrate split is by user.
train_asof_indices = asof_indices


def calib_user_mask(n_users: int):
    """Boolean mask over users: True = reserved for calibration, never fitted on."""
    import numpy as np

    rng = np.random.default_rng(CALIB_USER_SEED)
    mask = np.zeros(n_users, dtype=bool)
    k = max(int(round(n_users * CALIB_USER_FRACTION)), 1)
    mask[rng.choice(n_users, k, replace=False)] = True
    return mask


def idx_to_date(idx: int) -> date:
    return START_DATE + timedelta(days=idx)


def date_to_idx(d: date) -> int:
    return (d - START_DATE).days


def describe() -> str:
    asof = asof_indices()
    return (
        f"panel        : {START_DATE} .. {END_DATE} ({N_DAYS} days)\n"
        f"train days   : index 0..{TRAIN_END_IDX} (.. {idx_to_date(TRAIN_END_IDX)})\n"
        f"holdout days : index {TRAIN_END_IDX + 1}..{N_DAYS - 1} "
        f"({HOLDOUT_START} .. {END_DATE})\n"
        f"as-of dates  : {len(asof)}, {idx_to_date(asof[0])} .. {idx_to_date(asof[-1])}\n"
        f"calibration  : {CALIB_USER_FRACTION:.0%} of users held out from fitting, "
        f"residuals gathered across all as-of dates\n"
        f"eval as-of   : {idx_to_date(EVAL_ASOF_IDX)}, horizons 1..{HORIZON} "
        f"(all users, holdout outcomes)"
    )


if __name__ == "__main__":
    print(describe())
