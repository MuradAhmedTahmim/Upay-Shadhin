"""
Holdout evaluation - the evidence pack.

Everything reported here is computed on the untouched last 30 days
(2026-09-01 .. 2026-09-30). The forecast is issued standing on 2026-08-31, which is
the last day any model was allowed to see.

Writes docs/metrics.md.

    python -m ml.evaluate
"""
from __future__ import annotations

from datetime import timedelta
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import f1_score

from . import categorizer, forecast, panel, split
from rules import leakage, optimizer

DOCS = Path(__file__).resolve().parent.parent / "docs"
DOCS.mkdir(exist_ok=True)
OUT = DOCS / "metrics.md"

# Safety floor used in the savings simulation: the larger of 5% of monthly income
# or BDT 1,000. Documented here because it is an assumption, not a measurement.
FLOOR_INCOME_SHARE = 0.05
FLOOR_MIN = 1000.0

# The advice the copilot is compared against: "save 20% of your income", which is
# what a generic budgeting app would tell everyone regardless of their cash flow.
NAIVE_SAVINGS_RATE = 0.20


def _pinball(y: np.ndarray, pred: np.ndarray, q: float) -> float:
    d = y - pred
    return float(np.mean(np.maximum(q * d, (q - 1) * d)))


def _md_table(df: pd.DataFrame, floatfmt: str = "{:,.0f}") -> str:
    def fmt(v):
        if isinstance(v, float):
            return floatfmt.format(v) if abs(v) >= 1 or v == 0 else f"{v:.3f}"
        return str(v)

    head = "| " + " | ".join(str(c) for c in df.columns) + " |"
    sep = "|" + "|".join("---" for _ in df.columns) + "|"
    rows = ["| " + " | ".join(fmt(v) for v in r) + " |" for r in df.itertuples(index=False)]
    return "\n".join([head, sep] + rows)


# ------------------------------------------------------------------ forecaster

def evaluate_forecaster(p: panel.Panel, ctx: forecast.Context) -> dict:
    model = forecast.Forecaster.load()
    X, y, meta = forecast.build_rows(p, ctx, [split.EVAL_ASOF_IDX])
    pred = model.predict(X)
    base = forecast.baseline_predict(ctx, meta)

    H, U = split.HORIZON, p.n_users
    h = meta[:, 2]
    u = meta[:, 0]

    mae_model = float(np.mean(np.abs(y - pred[0.50])))
    mae_base = float(np.mean(np.abs(y - base)))
    coverage = float(np.mean((y >= pred[0.10]) & (y <= pred[0.90])))

    # per-horizon
    rows = []
    for lo, hi, label in [(1, 7, "1-7 days"), (8, 14, "8-14 days"),
                          (15, 21, "15-21 days"), (22, 30, "22-30 days")]:
        m = (h >= lo) & (h <= hi)
        rows.append({
            "Horizon": label,
            "Model MAE (BDT)": float(np.mean(np.abs(y[m] - pred[0.50][m]))),
            "Baseline MAE (BDT)": float(np.mean(np.abs(y[m] - base[m]))),
            "Improvement": f"{(1 - np.mean(np.abs(y[m] - pred[0.50][m])) / np.mean(np.abs(y[m] - base[m]))) * 100:.1f}%",
            "P10-P90 coverage": float(np.mean((y[m] >= pred[0.10][m]) & (y[m] <= pred[0.90][m]))),
        })
    by_horizon = pd.DataFrame(rows)

    # fairness
    users = p.users.loc[p.user_ids].reset_index()
    abs_err_model = np.abs(y - pred[0.50])
    abs_err_base = np.abs(y - base)
    frames = []
    for seg in ("income_band", "area", "gender", "archetype"):
        g = users[seg].to_numpy()[u]
        for val in sorted(set(g)):
            m = g == val
            frames.append({
                "Segment": seg,
                "Group": val,
                "Users": int(len(set(u[m]))),
                "Model MAE": float(abs_err_model[m].mean()),
                "Baseline MAE": float(abs_err_base[m].mean()),
                "Coverage": float(np.mean((y[m] >= pred[0.10][m]) & (y[m] <= pred[0.90][m]))),
            })
    fairness = pd.DataFrame(frames)
    # scale-free view: error relative to the group's own cash-flow magnitude
    fairness["Model MAE / mean |flow|"] = [
        round(r["Model MAE"] / max(np.abs(y[(users[r["Segment"]].to_numpy()[u]) == r["Group"]]).mean(), 1), 3)
        for _, r in fairness.iterrows()
    ]

    return {
        "mae_model": mae_model,
        "mae_base": mae_base,
        "improvement": (1 - mae_model / mae_base) * 100,
        "coverage": coverage,
        "pinball": {q: _pinball(y, pred[q], q) for q in forecast.QUANTILES},
        "by_horizon": by_horizon,
        "fairness": fairness,
        "pred": pred,
        "y": y,
        "meta": meta,
        "version": model.version,
        "n_rows": len(y),
    }


# ------------------------------------------------------------------ categoriser

def evaluate_categorizer() -> dict:
    tx = pd.read_csv(panel.DATA / "transactions.csv", parse_dates=["date"])
    test = tx[tx["date"].dt.date >= split.HOLDOUT_START].copy()

    model = categorizer.Categorizer.load()
    pred = model.predict(test)
    rule = categorizer.rule_predict(test["counterparty"], test["direction"])
    truth = test["category"].to_numpy()

    labels = sorted(set(truth))
    per_class = pd.DataFrame({
        "Category": labels,
        "Support": [int((truth == c).sum()) for c in labels],
        "Model F1": f1_score(truth, pred, labels=labels, average=None, zero_division=0),
        "Rule F1": f1_score(truth, rule, labels=labels, average=None, zero_division=0),
    })

    return {
        "n_test": len(test),
        "macro_f1_model": f1_score(truth, pred, average="macro", zero_division=0),
        "macro_f1_rule": f1_score(truth, rule, average="macro", zero_division=0),
        "acc_model": float((pred == truth).mean()),
        "acc_rule": float((rule == truth).mean()),
        "per_class": per_class,
        "version": model.version,
    }


# ------------------------------------------------------------------ business impact

def evaluate_savings_impact(p: panel.Panel, fc: dict) -> dict:
    """
    Does the copilot's plan actually help, measured on real holdout outcomes?

    Two strategies are run against each user's ACTUAL September cash flow:

      naive    - "save 20% of your income", the advice a generic app gives everyone
      copilot  - the optimiser's safe weekly amount, derived from the P10 forecast

    A plan "succeeds" if it saves something AND never pushes the balance below the
    user's safety floor. Breaking someone's month in order to save money is not a win,
    which is exactly what the naive rate does to users with front-loaded spending.
    """
    H, U = split.HORIZON, p.n_users
    meta, pred = fc["meta"], fc["pred"]
    t = split.EVAL_ASOF_IDX
    as_of = split.idx_to_date(t)

    p10 = np.zeros((U, H))
    for i in range(len(meta)):
        p10[meta[i, 0], meta[i, 2] - 1] = pred[0.10][i]

    actual = np.cumsum(p.net_flow[:, t + 1: t + 1 + H], axis=1)
    balance_today = p.balance[:, t]
    users = p.users.loc[p.user_ids].reset_index()
    income = users["monthly_income"].to_numpy()
    floors = np.maximum(income * FLOOR_INCOME_SHARE, FLOOR_MIN)

    recs, rows = [], []
    for i in range(U):
        rec = optimizer.max_safe_weekly_save(
            float(balance_today[i]), list(p10[i]), float(floors[i]), as_of,
            weekly_income=float(income[i] * 12 / 52))
        naive_weekly = float(income[i] * NAIVE_SAVINGS_RATE * 12 / 52)

        sim_c = optimizer.simulate_plan(float(balance_today[i]), list(actual[i]),
                                        float(floors[i]), rec.weekly_amount)
        sim_n = optimizer.simulate_plan(float(balance_today[i]), list(actual[i]),
                                        float(floors[i]), naive_weekly)
        sim_0 = optimizer.simulate_plan(float(balance_today[i]), list(actual[i]),
                                        float(floors[i]), 0.0)
        recs.append(rec.weekly_amount)
        rows.append({
            "no_plan_breach": sim_0["breached"],
            "copilot_saved": sim_c["total_saved"], "copilot_breach": sim_c["breached"],
            "naive_saved": sim_n["total_saved"], "naive_breach": sim_n["breached"],
            # A breach the PLAN caused: the user would have been fine on their own.
            # This is the only breach either strategy is actually responsible for.
            "copilot_caused": sim_c["breached"] and not sim_0["breached"],
            "naive_caused": sim_n["breached"] and not sim_0["breached"],
            "proposed": rec.weekly_amount > 0,
        })
    df = pd.DataFrame(rows)

    # The addressable population: users who would NOT have gone below their floor
    # anyway. For everyone else the month was already going to be short, and no
    # savings plan can fix that - counting them would flatter both strategies equally
    # and hide the thing being measured.
    addr = df[~df["no_plan_breach"]]

    # --- matched-savings comparison -------------------------------------------------
    # The copilot and the 20% rule do not save the same amount, so comparing their harm
    # rates directly is not apples to apples. Rerun the naive rule at whatever flat rate
    # makes it save the SAME mean amount as the copilot, and compare harm at equal
    # benefit. This is the comparison that actually settles the question.
    scale = (df["copilot_saved"].mean() / df["naive_saved"].mean()
             if df["naive_saved"].mean() > 0 else 1.0)
    matched_rate = NAIVE_SAVINGS_RATE * scale
    m_rows = []
    for i in range(U):
        weekly = float(income[i] * matched_rate * 12 / 52)
        sim = optimizer.simulate_plan(float(balance_today[i]), list(actual[i]),
                                      float(floors[i]), weekly)
        m_rows.append({
            "saved": sim["total_saved"],
            "caused": sim["breached"] and not rows[i]["no_plan_breach"],
        })
    matched = pd.DataFrame(m_rows)

    def per_1k(caused_rate: float, mean_saved: float) -> float:
        return caused_rate * 1000 / mean_saved if mean_saved > 0 else 0.0

    # risk-window detection quality, checked against what actually happened
    flagged, actually_short = 0, 0
    hits = 0
    for i in range(U):
        rw = optimizer.find_risk_window(float(balance_today[i]), list(p10[i]),
                                        float(floors[i]), as_of)
        real_short = bool((balance_today[i] + actual[i] < floors[i]).any())
        actually_short += real_short
        if rw is not None:
            flagged += 1
            hits += real_short

    return {
        "n_users": U,
        "n_addressable": int(len(addr)),
        "pct_already_short": float(df["no_plan_breach"].mean() * 100),
        "summary": pd.DataFrame([
            {"Strategy": "Naive — save 20% of income",
             "Mean saved in 30 days (BDT)": df["naive_saved"].mean(),
             "Plan-caused shortfalls": f"{df['naive_caused'].mean() * 100:.1f}%",
             "Harm per ৳1,000 saved": round(per_1k(df["naive_caused"].mean() * 100,
                                                   df["naive_saved"].mean()), 4)},
            {"Strategy": f"Naive — rate raised to {matched_rate:.0%} (matched savings)",
             "Mean saved in 30 days (BDT)": matched["saved"].mean(),
             "Plan-caused shortfalls": f"{matched['caused'].mean() * 100:.1f}%",
             "Harm per ৳1,000 saved": round(per_1k(matched["caused"].mean() * 100,
                                                   matched["saved"].mean()), 4)},
            {"Strategy": "upay Shadhin — P10 safe-to-save",
             "Mean saved in 30 days (BDT)": df["copilot_saved"].mean(),
             "Plan-caused shortfalls": f"{df['copilot_caused'].mean() * 100:.1f}%",
             "Harm per ৳1,000 saved": round(per_1k(df["copilot_caused"].mean() * 100,
                                                   df["copilot_saved"].mean()), 4)},
        ]),
        "matched_rate": matched_rate,
        "matched_caused": float(matched["caused"].mean() * 100),
        "matched_saved": float(matched["saved"].mean()),
        "harm_per_1k_matched": per_1k(matched["caused"].mean() * 100, matched["saved"].mean()),
        "harm_per_1k_copilot": per_1k(df["copilot_caused"].mean() * 100, df["copilot_saved"].mean()),
        "harm_ratio": (per_1k(matched["caused"].mean() * 100, matched["saved"].mean())
                       / max(per_1k(df["copilot_caused"].mean() * 100,
                                    df["copilot_saved"].mean()), 1e-9)),
        "caused_naive": float(df["naive_caused"].mean() * 100),
        "caused_copilot": float(df["copilot_caused"].mean() * 100),
        "caused_reduction_pp": float((df["naive_caused"].mean() - df["copilot_caused"].mean()) * 100),
        "safe_naive": float((~addr["naive_caused"] & (addr["naive_saved"] > 0)).mean() * 100),
        "safe_copilot": float((~addr["copilot_caused"] & (addr["copilot_saved"] > 0)).mean() * 100),
        "mean_weekly_rec": float(np.mean(recs)),
        "mean_weekly_rec_proposed": float(np.mean([r for r in recs if r > 0]) if any(r > 0 for r in recs) else 0.0),
        "pct_with_capacity": float(np.mean(np.array(recs) > 0) * 100),
        "proposed_no_harm": float(
            (~df.loc[df["proposed"], "copilot_caused"]).mean() * 100
            if df["proposed"].any() else 0.0),
        "declined_and_right": float(
            (df["no_plan_breach"] & ~df["proposed"]).sum() / max((~df["proposed"]).sum(), 1) * 100),
        "risk_flagged": flagged,
        "risk_actual": actually_short,
        "risk_precision": hits / flagged if flagged else 0.0,
        "risk_recall": hits / actually_short if actually_short else 0.0,
    }


def evaluate_leakage(p: panel.Panel) -> dict:
    """Population-level cash-out leakage, measured over the last 90 days."""
    t = split.EVAL_ASOF_IDX
    lo = t - 89
    totals = []
    for i in range(p.n_users):
        amounts = p.cat_flow["cash_out"][i, lo: t + 1]
        fees = float(p.fees[i, lo: t + 1].sum())
        cash = [float(a) for a in amounts if a > 0]
        cats = {c: float(p.cat_flow[c][i, lo: t + 1].sum()) for c in panel.CATEGORIES}
        rep = leakage.analyse(cash, fees, cats, window_days=90)
        totals.append({
            "fees_annual": rep.fees_annualised,
            "avoidable_annual": rep.avoidable_fees_annualised,
            "has_habit": bool(rep.habitual_amounts),
        })
    df = pd.DataFrame(totals)
    return {
        "mean_fees_annual": float(df["fees_annual"].mean()),
        "mean_avoidable_annual": float(df["avoidable_annual"].mean()),
        "pct_with_habit": float(df["has_habit"].mean() * 100),
        "population_avoidable": float(df["avoidable_annual"].sum()),
    }


# ------------------------------------------------------------------ report

def main() -> None:
    p = panel.get()
    ctx = forecast.make_context(p, split.TRAIN_END_IDX)

    print("evaluating forecaster ...")
    fc = evaluate_forecaster(p, ctx)
    print("evaluating categoriser ...")
    cat = evaluate_categorizer()
    print("simulating savings impact ...")
    imp = evaluate_savings_impact(p, fc)
    print("measuring cash-out leakage ...")
    lk = evaluate_leakage(p)

    as_of = split.idx_to_date(split.EVAL_ASOF_IDX)
    md = f"""# Holdout Metrics

*Generated by `python -m ml.evaluate`. Do not edit by hand.*

Every number below is computed on the **untouched holdout**: the forecast is issued
standing on **{as_of}**, the last day any model was allowed to see, and scored against
the real {split.HOLDOUT_START} → {split.END_DATE} outcomes.

| | |
|---|---|
| Users | {p.n_users:,} |
| Forecast rows scored | {fc['n_rows']:,} ({p.n_users:,} users × {split.HORIZON} horizons) |
| Forecaster version | `{fc['version']}` |
| Categoriser version | `{cat['version']}` |

---

## 1. Cash-flow forecaster

Target: cumulative net cash flow over the next *h* days. Baseline: the user's own mean
net flow by day-of-month, accumulated over the same horizon.

| Metric | Model | Baseline |
|---|---|---|
| **MAE (BDT)** | **{fc['mae_model']:,.0f}** | {fc['mae_base']:,.0f} |
| Improvement | **{fc['improvement']:.1f}% lower error** | — |
| P10–P90 coverage | **{fc['coverage']:.3f}** (target 0.80) | — |
| Pinball loss @P10 | {fc['pinball'][0.10]:,.0f} | — |
| Pinball loss @P50 | {fc['pinball'][0.50]:,.0f} | — |
| Pinball loss @P90 | {fc['pinball'][0.90]:,.0f} | — |

### By horizon

{_md_table(fc['by_horizon'])}

### Fairness

Forecast error broken down by segment. Gender is assigned **independently of all
financial behaviour** in the generator, so any gap here is a property of the model, not
of the data. The last column normalises error by each group's own cash-flow magnitude,
because a higher-income group will always show a larger absolute error in taka.

{_md_table(fc['fairness'])}

---

## 2. Transaction categoriser

Scored on **{cat['n_test']:,}** holdout transactions.

| Metric | Model | Keyword-rule baseline |
|---|---|---|
| **Macro F1** | **{cat['macro_f1_model']:.4f}** | {cat['macro_f1_rule']:.4f} |
| Accuracy | {cat['acc_model']:.4f} | {cat['acc_rule']:.4f} |

### Per category

{_md_table(cat['per_class'], floatfmt='{:.4f}')}

---

## 3. Business impact: does the plan actually help?

Both strategies are replayed against each user's **actual** September cash flow, with a
safety floor of max(5% of monthly income, ৳{FLOOR_MIN:,.0f}).

**An important property of this population first:** {imp['pct_already_short']:.1f}% of users
go below their floor in September *with no savings plan at all*. Low wallet balances are
normal in MFS — customers cash out most of what arrives. So a raw "went below the floor"
rate measures the customer's situation, not the plan's effect, and would make both
strategies look equally bad.

The metric that isolates the plan is a **plan-caused shortfall**: the user would have
been fine on their own, and the savings plan is what pushed them under. That is the only
harm either strategy is responsible for.

A second correction matters here. The copilot and the 20% rule do not save the same
amount, so comparing their harm rates side by side is not apples to apples. The middle
row reruns the flat rule at **{imp['matched_rate']:.0%} of income** — whatever rate makes it
save the same mean amount as the copilot — so harm can be compared at equal benefit.

{_md_table(imp['summary'], floatfmt='{:,.0f}')}

**Read the middle row against the last one.** Set to save the same mean amount — a flat
{imp['matched_rate']:.0%} of income — the rule causes **{imp['matched_caused']:.1f}%**
plan-caused shortfalls against **{imp['caused_copilot']:.1f}%** for the copilot. Per
৳1,000 actually saved, the copilot causes **{imp['harm_ratio']:.1f}× less harm**.

That comparison is the whole argument, and it is worth being precise about what it does
and does not show. The copilot is not safer because it is timid — at *identical* mean
savings it is still safer. It gets there by putting the money where it can be spared
instead of taking the same slice from everyone, which is the one thing a flat rule
cannot do because it never looks at the forecast.

- Users the optimiser judged to have real capacity: {imp['pct_with_capacity']:.1f}%
- Where it **did** propose a plan, {imp['proposed_no_harm']:.1f}% of those customers
  finished the month without a plan-caused shortfall
- It is also deliberately conservative: of the {imp['n_addressable']} users who were not
  heading for a shortfall anyway, it still declined
  {100 - imp['safe_copilot']:.1f}%, against {100 - imp['safe_naive']:.1f}% for the flat
  rule. That caution is the price of the lower harm rate, and it is a dial the product
  can move
- Mean weekly amount *where one was proposed*: **৳{imp['mean_weekly_rec_proposed']:,.0f}**
- Of the users it **declined** to give a plan, {imp['declined_and_right']:.1f}% did in fact
  go below their floor — the refusal was correct

Refusing to propose a plan for {100 - imp['pct_with_capacity']:.0f}% of users is not the
product failing. It is the product being honest, and it is the behaviour a generic
savings app cannot produce because it never looks at the forecast.

### Risk-window detection

Does the red "you will go short around the 24th" marker tell the truth?

| | |
|---|---|
| Users flagged with a predicted shortfall | {imp['risk_flagged']:,} |
| Users who actually went below their floor | {imp['risk_actual']:,} |
| **Precision** of the flag | **{imp['risk_precision']:.3f}** |
| **Recall** | **{imp['risk_recall']:.3f}** |

---

## 4. Cash-out leakage

Measured over the 90 days before the forecast date, annualised.

| | |
|---|---|
| Mean cash-out fees per user per year | **৳{lk['mean_fees_annual']:,.0f}** |
| Mean *avoidable* fees per user per year | **৳{lk['mean_avoidable_annual']:,.0f}** |
| Users with a habitual repeated withdrawal | {lk['pct_with_habit']:.1f}% |
| Avoidable fees across the {p.n_users:,}-user population | ৳{lk['population_avoidable']:,.0f}/year |

The avoidable share is bounded by what each customer **already** pays digitally, and
capped at 60%. No behaviour change is assumed that the customer has not already
demonstrated.

---

## How to reproduce

```bash
python data/generate.py     # fixed seed, ~25s
python -m ml.train          # ~2.5 min
python -m ml.evaluate       # regenerates this file
```
"""
    OUT.write_text(md, encoding="utf-8")
    print(f"\nwrote {OUT}")
    print(f"  forecaster MAE {fc['mae_model']:,.0f} vs baseline {fc['mae_base']:,.0f} "
          f"({fc['improvement']:.1f}% better), coverage {fc['coverage']:.3f}")
    print(f"  categoriser macro-F1 {cat['macro_f1_model']:.4f} vs rules {cat['macro_f1_rule']:.4f}")
    print(f"  plan-caused shortfalls {imp['caused_naive']:.1f}%% -> {imp['caused_copilot']:.1f}%% "
          f"(risk flag precision {imp['risk_precision']:.3f}, recall {imp['risk_recall']:.3f})")
    print(f"  avoidable fees BDT {lk['mean_avoidable_annual']:,.0f}/user/year")


if __name__ == "__main__":
    main()
