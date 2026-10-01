# Synthetic Data Assumptions

**All data in this project is synthetic.** No production upay data, no public dataset
containing personal records, and no real personally identifiable information was used.
Every name, phone number, merchant and amount below is generated from a fixed
vocabulary with a fixed random seed (`--seed 20260101`), so the dataset is fully
reproducible: `python data/generate.py`.

This file documents every assumption baked into `data/generate.py`, as required by the
hackathon guideline ("Document every synthetic assumption").

---

## 1. Scope

| Item | Value |
|---|---|
| Users | 800 |
| History | 270 days, `2026-01-04` → `2026-09-30` |
| Transactions | ~537,600 |
| Holdout | last 30 days (`2026-09-01` → `2026-09-30`), never used for training |
| Currency | BDT (৳) |

## 2. Income archetypes

Each user is assigned one archetype, which determines the *shape* of their inflows.

| Archetype | Share | Inflow pattern | Monthly income (mean ± sd) |
|---|---|---|---|
| `salaried` | 40% | one credit on a fixed day-of-month (`salary_day` ∈ 1–7), ±3% noise | ৳32,000 ± 13,000 |
| `gig` | 25% | irregular, ~42% of days, lognormal size | ৳26,000 ± 11,000 |
| `trader` | 20% | near-daily small inflows, ~50% chance of a Friday rest day | ৳38,000 ± 18,000 |
| `remittance` | 15% | two larger credits per month, ~85% reliability | ৳30,000 ± 14,000 |

Income is clipped to ৳9,000–৳140,000. Rural users' income is scaled by **0.78**.

## 3. Recurring outflows

| Category | Timing | Amount |
|---|---|---|
| `rent` | fixed `rent_day` ∈ 1–6 | 16–33% of monthly income, ±1% |
| `utility` | fixed `utility_day` ∈ 8–19 | 1.8–5.5% of monthly income |
| `family_support` | fixed `support_day` ∈ 5–14 | 0–18% of monthly income, ±8% |
| `mobile_recharge` | every ~10 days | one of {29, 48, 97, 148, 199, 298, 398} |

These are the patterns the forecaster is *expected* to learn; they are what make a
30-day cash-flow prediction meaningful rather than noise-fitting.

## 4. Discretionary outflows

- `food_grocery`: Poisson(1.1) events/day, ×1.3 on weekends, lognormal amounts whose
  spread is driven by the user's `volatility` dial (0.08–0.65).
- `transport`: 42% of days (55% on weekends).
- `other_retail`: 13% of days, scaled by the festival multiplier.

**Weekend** is defined as **Friday and Saturday** (Bangladesh), not Sat/Sun.

## 5. Month-end dip

63% of users carry `month_end_dip = 1`: their discretionary spending is multiplied by
**1.30** in the first ~45% of the month and **0.68** afterwards. This encodes the core
customer problem the product addresses — money is spent early and runs short late —
and is the behaviour the "risk window" detection is meant to surface.

## 6. Cash-out habit

- Each user has a `cashout_propensity` ~ Beta(2,3), multiplied by **1.35** for rural
  users (agent dependence is higher outside cities).
- Probability of a cash-out on a given day: `propensity × 0.55` on days with an inflow,
  `propensity × 0.10` otherwise — i.e. withdrawals cluster right after money arrives.
- Amounts are rounded to the nearest ৳500 (people withdraw round numbers), clipped to
  ৳500–৳25,000.
- **Fee assumption: 1.49% of the cash-out amount**, emitted as a separate transaction
  prefixed `FEE `. This rate is a plausible market-style figure chosen for the
  simulation; it is **not** a quoted upay tariff. All "fee saved" figures in the
  product scale linearly with this number and would be re-based against the real
  tariff card before any real-world claim.

Observed result: **mean ৳2,988 per user per year** in cash-out fees — the headline
leakage number the Insights screen surfaces.

## 7. Festivals

Spending ramps up over the 6 days before each festival and peaks on the day itself.

| Date | Festival | Peak multiplier |
|---|---|---|
| 2026-03-20 | Eid-ul-Fitr | ×2.6 |
| 2026-04-14 | Pohela Boishakh | ×1.5 |
| 2026-05-27 | Eid-ul-Adha | ×2.2 |

Dates are approximate and chosen to sit inside the generated window.

## 8. Segments for fairness testing

Recorded per user so model error can be broken down across groups
(`ml/evaluate.py` produces this table):

`income_band` (low <৳20k / mid / high ≥৳45k) · `area` (urban / rural) ·
`gender` (41% female) · `age_band` · `tenure_months` (3–60) · `archetype`

Gender is assigned **independently of all financial behaviour**. Any gender gap the
fairness table reports is therefore a property of the *model*, not of the data
generator — which is exactly what makes the check informative.

## 9. Counterparty / merchant strings

Generated from per-category templates with randomised reference numbers, masked
phone numbers (`017XXXXX123`), and deliberate textual noise: ~8% lowercased, ~6%
whitespace-stripped, ~4% with a trailing token. This prevents the transaction
categoriser from being a trivial keyword lookup and gives the learned model something
real to beat the rule baseline on.

## 10. Known simplifications

These are honest limitations, not oversights:

- Balance never goes meaningfully negative (a soft guard caps a debit at the available
  balance plus 2% of monthly income). Real wallets simply decline the transaction.
- No merchant-side or agent-side view; this dataset is customer-centric by design.
- No account-takeover, fraud or dispute events — those belong to Track 01/06, not here.
- Inflation, income growth and life events (marriage, job change) are not modelled over
  the 9-month window.
- Festival dates are fixed rather than derived from a lunar calendar.

## 11. Train / holdout discipline

`ml/split.py` is the single place where the cut is made. The last **30 days** of every
user's history are held out and are never seen during feature construction, model
fitting, or hyper-parameter choice. All reported metrics in `docs/metrics.md` come from
that holdout.
