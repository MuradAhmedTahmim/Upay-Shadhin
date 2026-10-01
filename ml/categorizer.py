"""
Transaction categoriser.

Maps a raw transaction (counterparty string + amount + hour + direction) to one of
nine spending categories. This is what turns an unreadable statement into the
plain-language categories the Insights screen and the leakage detector depend on.

Model: character n-gram TF-IDF + logistic regression. A gradient-boosted tree was
the first choice but TF-IDF output is sparse, which HistGradientBoosting does not
accept; a linear model over character n-grams is the right tool for short, noisy
merchant strings anyway.

Baseline: hand-written keyword rules (`rule_predict`), which is what a team would
ship without ML. The evaluation reports macro-F1 of both.
"""
from __future__ import annotations

import re
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from scipy import sparse
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

MODEL_DIR = Path(__file__).resolve().parent / "artifacts"
MODEL_DIR.mkdir(exist_ok=True)
MODEL_PATH = MODEL_DIR / "categorizer.joblib"
MODEL_VERSION = "categorizer-1.0.0"

CATEGORIES = [
    "income", "rent", "utility", "mobile_recharge", "family_support",
    "food_grocery", "transport", "cash_out", "other_retail",
]

# --- rule baseline --------------------------------------------------------
RULES = [
    ("cash_out", r"CASH\s*-?\s*OUT|CASHOUT|WITHDRAW|\bATM\b|\bCO AGENT\b"),
    ("income", r"SALARY|PAYROLL|MONTHLY PAY|DISB|PAYMENT RECV|FREELANCE|SETTLEMENT|REMIT"),
    ("rent", r"BHARA|RENT|LANDLORD|VARA"),
    ("utility", r"DESCO|DPDC|NESCO|TITAS|WASA|BIDYUT|ELEC|BTCL|BILL"),
    ("mobile_recharge", r"RECHARGE|TOPUP|FLEXILOAD|AMAR OFFER|RCHRG|INTERNET PACK"),
    ("family_support", r"SEND\s*MONEY|SENDMONEY|SEND MNY|P2P|TRANSFER TO|FAMILY TRF"),
    ("food_grocery", r"SHWAPNO|MEENA|AGORA|FOODPANDA|KACHA|GROCERY|CHALDAL|HOTEL|SHOPPING"),
    ("transport", r"UBER|PATHAO|CNG|BUS TICKET|RAPIDO|FUEL|TRAIN|LAUNCH"),
    ("other_retail", r"DARAZ|PHARMACY|APOLLO|SCHOOL FEE|CLOTH|BATA|SALON|BOOK|ELECTRONICS"),
]
_COMPILED = [(c, re.compile(p)) for c, p in RULES]


def rule_predict(counterparty: pd.Series, direction: pd.Series) -> np.ndarray:
    text = counterparty.str.upper().str.replace(r"[^A-Z0-9 ]", " ", regex=True)
    out = np.full(len(text), "other_retail", dtype=object)
    assigned = np.zeros(len(text), dtype=bool)
    for cat, rx in _COMPILED:
        hit = text.str.contains(rx, regex=True).to_numpy() & ~assigned
        out[hit] = cat
        assigned |= hit
    # a credit that matched nothing is almost certainly income
    out[~assigned & (direction.to_numpy() == "credit")] = "income"
    return out


# --- learned model --------------------------------------------------------

def _numeric(df: pd.DataFrame) -> np.ndarray:
    amt = df["amount"].to_numpy(dtype=float)
    return np.column_stack([
        np.log1p(amt),
        df["hour"].to_numpy(dtype=float),
        (df["direction"].to_numpy() == "credit").astype(float),
        (np.mod(amt, 500) == 0).astype(float),      # round withdrawals
        (np.mod(amt, 1) == 0).astype(float),
        df.get("is_recurring", pd.Series(np.zeros(len(df)))).to_numpy(dtype=float),
    ])


class Categorizer:
    def __init__(self, vec: TfidfVectorizer, scaler: StandardScaler,
                 clf: LogisticRegression, version: str = MODEL_VERSION):
        self.vec, self.scaler, self.clf, self.version = vec, scaler, clf, version

    def _design(self, df: pd.DataFrame, fit: bool = False):
        text = df["counterparty"].str.upper()
        Xt = self.vec.fit_transform(text) if fit else self.vec.transform(text)
        num = _numeric(df)
        Xn = self.scaler.fit_transform(num) if fit else self.scaler.transform(num)
        return sparse.hstack([Xt, sparse.csr_matrix(Xn)], format="csr")

    @classmethod
    def fit(cls, df: pd.DataFrame) -> "Categorizer":
        self = cls(
            TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 4),
                            min_df=5, max_features=60_000, sublinear_tf=True),
            StandardScaler(),
            LogisticRegression(C=6.0, max_iter=600),
        )
        X = self._design(df, fit=True)
        self.clf.fit(X, df["category"].to_numpy())
        return self

    def predict(self, df: pd.DataFrame) -> np.ndarray:
        return self.clf.predict(self._design(df))

    def predict_proba(self, df: pd.DataFrame):
        return self.clf.classes_, self.clf.predict_proba(self._design(df))

    def save(self, path: Path = MODEL_PATH) -> None:
        joblib.dump({"vec": self.vec, "scaler": self.scaler,
                     "clf": self.clf, "version": self.version}, path)

    @classmethod
    def load(cls, path: Path = MODEL_PATH) -> "Categorizer":
        b = joblib.load(path)
        return cls(b["vec"], b["scaler"], b["clf"], b["version"])
