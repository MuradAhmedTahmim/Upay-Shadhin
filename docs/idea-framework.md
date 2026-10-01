# Student Idea Development Framework

The one-page logic chain the guideline asks every team to complete before writing code.
Filled in against what was actually built, with the holdout numbers from
[`metrics.md`](metrics.md).

**Problem statement (guideline template)**

> For **salaried and semi-formal income earners in Bangladesh who use an MFS wallet**,
> **money runs out before month-end and savings goals silently fail**, which costs them
> **৳2,988 a year in cash-out fees alone** and keeps them permanently reactive. We will
> build an **AI cash-flow copilot** that uses **their own transaction history** to
> **forecast the next 30 days and compute how much they can safely save**, with success
> measured by **forecast error against a seasonal baseline, plan-caused shortfalls at
> matched savings, and ৳/year of avoidable fees surfaced**.

---

## 1. User — who experiences the problem?

A wallet customer with a regular but tight cash flow. The synthetic population models
four archetypes, because the problem looks different for each:

| Archetype | Share | Why they struggle |
|---|---|---|
| Salaried | 40% | Money arrives once; by the 24th it is gone |
| Gig | 25% | Income is irregular, so "save 20%" is meaningless |
| Small trader | 20% | Daily inflow, no separation between float and savings |
| Remittance receiver | 15% | Two lumps a month, long gaps between |

Secondary user: upay itself, which gains digital transaction volume every time a
cash-out is replaced by a digital payment.

## 2. Problem — what is difficult, costly, risky or frustrating?

Customers cannot answer the one question every savings product asks them first:
*how much can you put aside?* Without that answer they either save nothing, or commit to
a round number that breaks their month and sends them back to a high-fee cash-out.

**Baseline, measured on the synthetic population:**

| | |
|---|---|
| Users whose spending is front-loaded, producing a predictable month-end shortfall | 63% |
| Users who go below their own safety floor in a given month | 68.2% |
| Mean cash-out fees paid | ৳2,988 per user per year |
| Users with a habitual repeated withdrawal amount | majority |

## 3. Why now — why could AI help?

The transaction stream already contains the answer. Payday, rent day, bill day, the
cash-out habit and the month-end dip are all *learnable* regularities, and a wallet sees
them for every customer without asking a single question. What was missing was not data
but a model that turns the pattern into a number a customer can act on, with an
uncertainty estimate honest enough to make a safety promise on.

## 4. Solution — what exactly are we building?

A four-screen mobile copilot over a forecast-driven decision chain:

```
transactions -> categoriser -> cash-flow forecaster -> safe-to-save optimiser -> proposal
                  (what)         (P10/P50/P90)          (deterministic rules)    (user confirms)
                                        |                        |
                                        +---- evidence ----------+----> plain-Bangla explanation
```

- **পূর্বাভাস** — 30-day balance path with a P10–P90 band and the predicted risk window
- **খরচ** — spending categories, and what the cash-out habit costs per year
- **লক্ষ্য** — safe-to-save amount, goal feasibility verdict, trade-offs
- **কেন** — which layer produced which number, and what the product will never do

## 5. AI role — what is the model actually doing?

| Component | Task type | Technique |
|---|---|---|
| Cash-flow forecaster | **Prediction** | Gradient-boosted quantile regression (P10/P50/P90) over 36 features, conformally calibrated |
| Transaction categoriser | **Classification** | Character n-gram TF-IDF + logistic regression |
| Explanation | **Attribution** | Feature-level evidence surfaced as `reasons[]` |
| Narrative | **Generation** | Template NLG over computed evidence (LLM-pluggable) |
| Safe-to-save | *not AI, deliberately* | Deterministic rules over the P10 path |

The split is the design. The model estimates *what will happen*; a readable rule decides
*what to do about it*. That keeps the consequential step auditable.

## 6. Impact — what outcome should improve, and by how much?

Measured on the untouched holdout (forecast issued 2026-08-31, scored on September):

| Metric | Result |
|---|---|
| Forecast MAE vs day-of-month baseline | **8.4% lower** (৳3,923 vs ৳4,280) |
| P10–P90 coverage | 0.746 (nominal 0.80) |
| Categoriser macro-F1 vs keyword rules | **0.9998 vs 0.9675** |
| Risk-window flag | precision **0.920**, recall **0.984** |
| Plan-caused shortfalls, at matched savings | **1.1% vs 1.5%** — 1.3× less harm per ৳1,000 saved |
| Correctness of refusing a plan | 92.7% of declined users did go below their floor |
| Avoidable cash-out fees surfaced | **৳1,701 per user per year** |

**Business case for upay.** Across 800 simulated users the avoidable fee pool is
৳1.36M/year. Replacing those cash-outs with digital payments moves the same money onto
rails upay already owns, which is why the customer-value story and the transaction-growth
story point the same way here rather than against each other.

## 7. Data — what can we safely simulate or source?

100% synthetic, generated locally from a fixed seed: 800 users × 270 days ≈ 537,000
transactions. No production data, no public dataset of personal records, no PII.

Injected and documented: income archetypes, recurring bills on fixed days, month-end dip,
cash-out habits, festival spikes, Bangladesh weekend effects, and fairness segments.
Every assumption — including the known simplifications — is written down in
[`../data/ASSUMPTIONS.md`](../data/ASSUMPTIONS.md).

## 8. Validation — how do we know it works?

**Offline.** The last 30 days of every user's history are held out in a single module
(`ml/split.py`) and asserted at training time. Conformal calibration uses a separate
20% of users, never fitted on. Metrics are regenerated by `python -m ml.evaluate`, not
written by hand.

**Two findings that changed the design**, recorded because they are the honest part:

1. The raw "went below the floor" rate made the copilot look *worse* than generic advice.
   It was measuring the customer's pre-existing situation (68.2% go short regardless),
   not the plan's effect. Switching to **plan-caused** shortfalls isolated the thing
   being measured.
2. The two strategies did not save the same amount, so their harm rates were not
   comparable. Adding a **matched-savings arm** — the flat rule rerun at whatever rate
   saves the same mean — settled it properly.

The evaluation also exposed a product flaw: the optimiser was proposing ৳9,165/week by
sweeping idle wallet balances. Arithmetically safe, but a one-off transfer is not a
savings habit, so the plan is now capped at 40% of weekly income.

**Fairness.** Forecast error is reported by income band, area, gender and archetype.
Gender is assigned independently of all financial behaviour in the generator, so any gap
the table shows is a property of the model rather than of the data.

**Next, with real users.** A holdout experiment answers "is the forecast right". It does
not answer "do people act on it", which needs a controlled rollout: offer the plan to a
random half of eligible customers and measure savings-balance growth, plan-caused
shortfalls, cash-out frequency and 90-day retention against the control.

## 9. Scale — what changes when real data arrives?

| Layer | Prototype | Production |
|---|---|---|
| Data | CSV + `.npz` panel | Streaming transactions → feature store |
| Features | Rebuilt per run | Materialised, versioned, point-in-time correct |
| Forecaster | One global model | Same, retrained on a schedule, with drift monitoring on coverage |
| Calibration | Held-out users | Rolling recalibration — coverage is the alarm that fires first |
| Rules | Python module | Unchanged; this layer is already production-shaped |
| Narrative | Templates | Optional LLM behind the same interface, still fed only computed numbers |
| Serving | FastAPI, models in memory | Containerised, versioned responses (already carried as `model_version`) |

**Governance.** Every response already carries the model version that produced it. The
fee rate is a documented assumption that must be re-based against the real tariff card
before any "you could save ৳X" claim is shown to a customer. The savings plan stays a
proposal requiring confirmation. No credit decision is made anywhere, at any stage.

---

## Responsible AI

| Principle | How it is met |
|---|---|
| **Privacy** | Synthetic data only, generated locally. No PII; phone numbers are masked patterns (`017XXXXX123`), not numbers. |
| **Explainability** | Every number carries `reasons[]` with raw evidence, surfaced in the UI, not just in the API. |
| **Fairness** | Error reported by income band, area, gender and archetype, with a scale-free column so a higher-income group's larger absolute error is not mistaken for bias. |
| **Security** | No secrets in the repository; `.env` git-ignored. The language layer receives only computed numbers and cannot execute anything, so there is no prompt-injection path to a financial decision. |
| **Human oversight** | The plan is proposed and requires explicit confirmation. Nothing moves money. |
| **Transparency** | Predictions (`ml/`), rules (`rules/`) and generated language (`nlg/`) are separate packages, and the "কেন" screen states which produced what. |
| **No harmful automation** | No autonomous money movement. No credit approval or denial. The product's most important behaviour is **refusing** to propose a plan for the 72% of users who cannot afford one. |
