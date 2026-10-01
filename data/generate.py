"""
upay Shadhin - synthetic MFS data generator.

Produces a clearly-synthetic but behaviourally realistic mobile-financial-services
dataset: users with income archetypes, and their daily transaction stream with
deliberately injected, documented patterns (salary cycles, recurring bills,
month-end dips, cash-out habits, festival spikes, weekend effects).

No real personally identifiable information is used anywhere. Names, merchants and
numbers are generated from fixed vocabularies with a fixed random seed.

Every assumption encoded here is documented in data/ASSUMPTIONS.md.

Usage:
    python data/generate.py [--users 800] [--days 270] [--seed 20260101]
"""
from __future__ import annotations

import argparse
import csv
from datetime import date, timedelta
from pathlib import Path

import numpy as np

DATA_DIR = Path(__file__).resolve().parent

# --- Calendar -------------------------------------------------------------
END_DATE = date(2026, 9, 30)          # last day of generated history
HOLDOUT_DAYS = 30                     # never used for training (see ml/split.py)

# Festival dates inside the generated window (approximate, synthetic).
FESTIVALS = {
    date(2026, 3, 20): ("eid_ul_fitr", 2.6),
    date(2026, 4, 14): ("pohela_boishakh", 1.5),
    date(2026, 5, 27): ("eid_ul_adha", 2.2),
}
FESTIVAL_LEAD_DAYS = 6                # spending ramps up before the day itself

# --- Categories -----------------------------------------------------------
CATEGORIES = [
    "income",
    "rent",
    "utility",
    "mobile_recharge",
    "family_support",
    "food_grocery",
    "transport",
    "cash_out",
    "other_retail",
]

# Merchant / counterparty vocabularies. Intentionally messy (casing, spacing,
# abbreviations, trailing codes) so that a learned categoriser has something to
# do that a keyword rule cannot fully capture.
MERCHANTS = {
    "income": [
        "SALARY CREDIT {co}", "PAYROLL-{co}", "{co} MONTHLY PAY",
        "DISB {co} LTD", "PAYMENT RECV {co}", "FREELANCE PAYOUT {co}",
        "ORDER SETTLEMENT {co}", "REMIT IN {co}", "FOREIGN REMIT-{co}",
    ],
    "rent": [
        "BARI BHARA {ref}", "HOUSE RENT {ref}", "LANDLORD PAY {ref}",
        "FLAT RENT-{ref}", "RENT TRF {ref}", "BASHA VARA {ref}",
    ],
    "utility": [
        "DESCO BILL {ref}", "DPDC POSTPAID {ref}", "NESCO PREPAID {ref}",
        "TITAS GAS {ref}", "WASA BILL {ref}", "PALLI BIDYUT {ref}",
        "ELEC BILL PAY {ref}", "BTCL BILL {ref}",
    ],
    "mobile_recharge": [
        "GP RECHARGE {msisdn}", "ROBI TOPUP {msisdn}", "BL AMAR OFFER {msisdn}",
        "AIRTEL RCHRG {msisdn}", "TELETALK TOPUP {msisdn}", "MOBILE TOPUP {msisdn}",
        "GP FLEXILOAD {msisdn}", "INTERNET PACK {msisdn}",
    ],
    "family_support": [
        "SEND MONEY {msisdn}", "P2P TRF {msisdn}", "SENDMONEY-{msisdn}",
        "TRANSFER TO {msisdn}", "FAMILY TRF {msisdn}", "SEND MNY {msisdn}",
    ],
    "food_grocery": [
        "SHWAPNO SUPERSHOP {ref}", "MEENA BAZAR {ref}", "AGORA {ref}",
        "DAILY SHOPPING {ref}", "FOODPANDA BD {ref}", "KACHA BAZAR {ref}",
        "HOTEL {ref} REST", "CHALDAL ONLINE {ref}", "GROCERY MART {ref}",
    ],
    "transport": [
        "UBER BD {ref}", "PATHAO RIDE {ref}", "CNG FARE {ref}",
        "BUS TICKET {ref}", "RAPIDO BD {ref}", "FUEL PUMP {ref}",
        "TRAIN TKT {ref}", "LAUNCH TKT {ref}",
    ],
    "cash_out": [
        "CASH OUT AGENT {agent}", "AGENT CASHOUT-{agent}", "CO AGENT {agent}",
        "WITHDRAW AGENT {agent}", "CASH-OUT {agent}", "ATM CASHOUT {agent}",
    ],
    "other_retail": [
        "DARAZ BD {ref}", "PHARMACY {ref}", "APOLLO DIAG {ref}",
        "SCHOOL FEE {ref}", "CLOTH STORE {ref}", "BATA SHOE {ref}",
        "SALON {ref}", "BOOK SHOP {ref}", "ELECTRONICS {ref}",
    ],
}

EMPLOYERS = [
    "ACME TEXTILES", "BENGAL SOFT", "DHAKA LOGISTICS", "RMG UNIT 7",
    "GREENFIELD LTD", "CITY TRADERS", "NEXT IT", "PADMA FOODS",
    "SOUTHERN GARMENTS", "BRIGHT PHARMA", "UTTARA MOTORS", "DELTA AGRO",
]

ARCHETYPES = ("salaried", "gig", "trader", "remittance")
ARCHETYPE_P = (0.40, 0.25, 0.20, 0.15)

# upay-like cash-out fee (synthetic assumption, see ASSUMPTIONS.md)
CASH_OUT_FEE_RATE = 0.0149


def _rand_name(rng: np.random.Generator, template: str) -> str:
    out = template
    if "{co}" in out:
        out = out.replace("{co}", EMPLOYERS[rng.integers(len(EMPLOYERS))])
    if "{ref}" in out:
        out = out.replace("{ref}", f"{rng.integers(1000, 9999)}")
    if "{msisdn}" in out:
        out = out.replace("{msisdn}", f"01{rng.integers(3, 10)}XXXXX{rng.integers(100, 999)}")
    if "{agent}" in out:
        out = out.replace("{agent}", f"AG{rng.integers(10000, 99999)}")
    # light textual noise so the task is not trivially keyword-separable
    r = rng.random()
    if r < 0.08:
        out = out.lower()
    elif r < 0.14:
        out = out.replace(" ", "")
    elif r < 0.18:
        out = out + " BD"
    return out


def build_users(rng: np.random.Generator, n_users: int) -> list[dict]:
    users = []
    for i in range(n_users):
        archetype = ARCHETYPES[rng.choice(len(ARCHETYPES), p=ARCHETYPE_P)]

        if archetype == "salaried":
            monthly_income = float(rng.normal(32000, 13000))
        elif archetype == "gig":
            monthly_income = float(rng.normal(26000, 11000))
        elif archetype == "trader":
            monthly_income = float(rng.normal(38000, 18000))
        else:  # remittance
            monthly_income = float(rng.normal(30000, 14000))
        monthly_income = float(np.clip(monthly_income, 9000, 140000))

        area = "urban" if rng.random() < (0.72 if archetype != "remittance" else 0.45) else "rural"
        if area == "rural":
            monthly_income *= 0.78

        income_band = "low" if monthly_income < 20000 else ("mid" if monthly_income < 45000 else "high")

        users.append({
            "user_id": f"U{100000 + i}",
            "archetype": archetype,
            "monthly_income": round(monthly_income, 2),
            "income_band": income_band,
            "area": area,
            "gender": "female" if rng.random() < 0.41 else "male",
            "age_band": ("18-25", "26-35", "36-50", "50+")[rng.choice(4, p=(0.24, 0.38, 0.27, 0.11))],
            "tenure_months": int(rng.integers(3, 61)),
            # behavioural dials
            "salary_day": int(rng.integers(1, 8)),              # payday anchor
            "rent_day": int(rng.integers(1, 7)),
            "utility_day": int(rng.integers(8, 20)),
            "support_day": int(rng.integers(5, 15)),
            "rent_amount": round(float(monthly_income * rng.uniform(0.16, 0.33)), 2),
            "support_amount": round(float(monthly_income * rng.uniform(0.0, 0.18)), 2),
            "cashout_propensity": float(np.clip(rng.beta(2, 3) * (1.35 if area == "rural" else 1.0), 0, 1)),
            "discretionary_rate": float(np.clip(rng.normal(0.34, 0.09), 0.12, 0.62)),
            "month_end_dip": int(rng.random() < 0.63),          # spends early, runs short late
            "volatility": float(np.clip(rng.normal(0.28, 0.10), 0.08, 0.65)),
            "opening_balance": round(float(monthly_income * rng.uniform(0.05, 0.55)), 2),
        })
    return users


def festival_multiplier(day: date) -> float:
    mult = 1.0
    for fday, (_, peak) in FESTIVALS.items():
        delta = (fday - day).days
        if 0 <= delta <= FESTIVAL_LEAD_DAYS:
            mult = max(mult, 1.0 + (peak - 1.0) * (1 - delta / (FESTIVAL_LEAD_DAYS + 1)))
    return mult


def _days_in_month(day: date) -> int:
    nxt = date(day.year + (day.month == 12), (day.month % 12) + 1, 1)
    return (nxt - timedelta(days=1)).day


def generate(n_users: int, n_days: int, seed: int) -> None:
    rng = np.random.default_rng(seed)
    users = build_users(rng, n_users)
    start = END_DATE - timedelta(days=n_days - 1)

    tx_path = DATA_DIR / "transactions.csv"
    users_path = DATA_DIR / "users.csv"

    with users_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(users[0].keys()))
        w.writeheader()
        w.writerows(users)

    n_tx = 0
    with tx_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow([
            "txn_id", "user_id", "date", "hour", "direction", "amount",
            "category", "counterparty", "channel", "is_recurring", "balance_after",
        ])

        for u in users:
            balance = u["opening_balance"]
            monthly = u["monthly_income"]
            daily_disc = monthly * u["discretionary_rate"] / 30.0

            for d in range(n_days):
                day = start + timedelta(days=d)
                dom = day.day
                dow = day.weekday()                     # 0=Mon .. 4=Fri, 5=Sat
                is_weekend = dow in (4, 5)              # BD weekend: Fri, Sat
                fest = festival_multiplier(day)
                month_progress = dom / _days_in_month(day)

                events: list[tuple[str, str, float]] = []   # (direction, category, amount)

                # ---------------- inflows ----------------
                if u["archetype"] == "salaried":
                    if dom == u["salary_day"]:
                        events.append(("credit", "income", monthly * rng.normal(1.0, 0.03)))
                elif u["archetype"] == "gig":
                    if rng.random() < 0.42:
                        events.append(("credit", "income", monthly / 12.6 * rng.lognormal(0, 0.55)))
                elif u["archetype"] == "trader":
                    if not (dow == 4 and rng.random() < 0.5):
                        events.append(("credit", "income", monthly / 26.0 * rng.lognormal(0, 0.42) * fest))
                else:  # remittance
                    if dom in (u["salary_day"], u["salary_day"] + 14) and rng.random() < 0.85:
                        events.append(("credit", "income", monthly / 2 * rng.normal(1.0, 0.18)))

                # ---------------- recurring outflows ----------------
                if dom == u["rent_day"] and u["rent_amount"] > 0:
                    events.append(("debit", "rent", u["rent_amount"] * rng.normal(1.0, 0.01)))
                if dom == u["utility_day"]:
                    events.append(("debit", "utility", monthly * rng.uniform(0.018, 0.055)))
                if dom == u["support_day"] and u["support_amount"] > 500:
                    events.append(("debit", "family_support", u["support_amount"] * rng.normal(1.0, 0.08)))
                if dom % 10 == u["salary_day"] % 10:
                    events.append(("debit", "mobile_recharge", float(rng.choice([29, 48, 97, 148, 199, 298, 398]))))

                # ---------------- discretionary outflows ----------------
                dip = 1.0
                if u["month_end_dip"]:
                    dip = 1.30 if month_progress < 0.45 else 0.68   # front-loaded spending

                base = daily_disc * dip * fest * (1.25 if is_weekend else 1.0)

                n_food = rng.poisson(1.1 * (1.3 if is_weekend else 1.0))
                for _ in range(int(n_food)):
                    events.append(("debit", "food_grocery", base * rng.lognormal(-0.6, u["volatility"] + 0.3)))

                if rng.random() < (0.55 if is_weekend else 0.42):
                    events.append(("debit", "transport", base * rng.lognormal(-1.4, 0.5)))

                if rng.random() < 0.13 * fest:
                    events.append(("debit", "other_retail", base * rng.lognormal(0.1, 0.8)))

                # ---------------- cash-out habit ----------------
                # Concentrated on days with an inflow, scaled by propensity.
                recent_inflow = any(e[1] == "income" for e in events)
                p_cashout = u["cashout_propensity"] * (0.55 if recent_inflow else 0.10)
                if rng.random() < p_cashout:
                    amt = float(np.clip(monthly * rng.uniform(0.05, 0.30), 500, 25000))
                    amt = round(amt / 500) * 500 or 500          # people withdraw round amounts
                    events.append(("debit", "cash_out", amt))
                    events.append(("debit", "__fee__", amt * CASH_OUT_FEE_RATE))

                # ---------------- emit ----------------
                for direction, category, amount in events:
                    is_fee = category == "__fee__"
                    if is_fee:
                        category = "cash_out"
                    amount = float(max(round(amount, 2), 1.0))
                    if direction == "debit":
                        amount = min(amount, max(balance, 0.0) + monthly * 0.02)  # soft overdraft guard
                        if amount < 1.0:
                            continue
                        balance -= amount
                    else:
                        balance += amount

                    tmpl = MERCHANTS[category][rng.integers(len(MERCHANTS[category]))]
                    name = _rand_name(rng, tmpl)
                    if is_fee:
                        name = "FEE " + name

                    n_tx += 1
                    w.writerow([
                        f"T{n_tx:08d}", u["user_id"], day.isoformat(),
                        int(np.clip(rng.normal(14, 4), 0, 23)),
                        direction, round(amount, 2), category, name,
                        "app" if rng.random() < 0.78 else "ussd",
                        int(category in ("rent", "utility", "family_support", "mobile_recharge")
                            or (category == "income" and u["archetype"] in ("salaried", "remittance"))),
                        round(balance, 2),
                    ])

    print(f"users       : {len(users):,}  -> {users_path}")
    print(f"transactions: {n_tx:,}  -> {tx_path}")
    print(f"window      : {start} .. {END_DATE}  ({n_days} days)")
    print(f"holdout     : last {HOLDOUT_DAYS} days "
          f"({END_DATE - timedelta(days=HOLDOUT_DAYS - 1)} .. {END_DATE})")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--users", type=int, default=800)
    ap.add_argument("--days", type=int, default=270)
    ap.add_argument("--seed", type=int, default=20260101)
    a = ap.parse_args()
    generate(a.users, a.days, a.seed)
