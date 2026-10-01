# upay Shadhin (উপায় স্বাধীন)

**An AI cash-flow copilot that tells a mobile-wallet customer how much they can *safely* save today — and proves it with a 30-day forecast.**

AI Hackathon 2026 · DIU CPC × upay · **Track 03 — Customer Innovation & Financial Independence**

> ⚠️ Every number in this project comes from **synthetic data generated locally**. No production upay data, no real customer records, and no personally identifiable information is used anywhere. See [`data/ASSUMPTIONS.md`](data/ASSUMPTIONS.md).

---

## Project Overview

### The problem

Millions of MFS customers in Bangladesh know the feeling: money arrives on payday, and
by the 24th it is gone. They cannot say *why*, they cannot say *when* it will happen
again, and so they never start saving — because every savings app asks the one question
they cannot answer: **"how much can you put aside?"**

Two measurable consequences show up in our simulated population of 800 wallet users:

| Observed in synthetic data | Value |
|---|---|
| Users whose spending is front-loaded, causing a predictable month-end shortfall | **63%** |
| Average cash-out fees paid per user per year | **৳2,988** |

Generic budgeting advice ("save 20% of your income") fails these users because it
ignores their actual cash-flow shape — rent on the 3rd, family support on the 9th,
an irregular gig income, a festival month.

### The solution

**upay Shadhin** forecasts a user's next 30 days of cash flow, finds the days where
their balance is predicted to dip below their own safety floor, and from the
*pessimistic* end of that forecast computes a **safe-to-save amount** — the largest
sum they can set aside without being pushed into a shortfall later in the month.

It then explains the whole thing in plain Bangla, with the evidence attached.

```
INPUT                 INTELLIGENCE                      ACTION
synthetic wallet  ->  categoriser  ->  cash-flow    ->  safe-to-save    ->  user confirms
transactions          (what)          forecaster       optimiser           an auto-save
                                      P10/P50/P90      + risk window       plan
                                         |                  |
                                         +---- feature attribution ----> plain-Bangla
                                                                          explanation
```

### Main purpose

To move a customer from *"I have no idea where my money goes"* to
*"I know I can save ৳2,100 a week, and I know why"* — which is the difference between
being an active wallet user and being financially independent.

**Problem statement (hackathon template):**
> For salaried and semi-formal income earners in Bangladesh who use an MFS wallet,
> money predictably runs out before month-end and savings goals silently fail, costing
> them repeated high-cost cash-outs. We will build an AI cash-flow copilot that uses a
> user's own transaction history to forecast the next 30 days, compute a safe-to-save
> amount, and explain the plan in plain Bangla — measured by forecast MAE vs baseline,
> simulated goal-completion uplift, and ৳/year of avoidable cash-out fees surfaced.

---

## Features

> Build status is tracked honestly. ✅ = implemented and runnable today.
> 🚧 = in progress during the hackathon window.

### ✅ 1. Synthetic MFS data generator — `data/generate.py`

Generates 800 users × 270 days ≈ **537,000 transactions** with deliberately injected,
documented behavioural patterns, so the models have something real to learn:

- **Four income archetypes**: salaried (fixed payday), gig (irregular), trader
  (near-daily), remittance (twice monthly)
- **Recurring outflows** on fixed days: rent, utility, family support, mobile recharge
- **Month-end dip** for 63% of users (spend front-loaded, then run short)
- **Cash-out habit** clustered on days money arrives, with a 1.49% fee
- **Festival spikes** (Eid-ul-Fitr, Pohela Boishakh, Eid-ul-Adha) ramping over 6 days
- **Bangladesh weekend** (Friday/Saturday) effects
- **Fairness segments** recorded per user: income band, urban/rural, gender, age band,
  tenure, archetype

Fully reproducible from a fixed seed. Every assumption — including the known
simplifications — is written down in [`data/ASSUMPTIONS.md`](data/ASSUMPTIONS.md).

### ✅ 2. Train/holdout discipline — `ml/split.py`

The **last 30 days of every user's history** (2026-09-01 → 2026-09-30) are held out and
never touched during feature construction or model fitting. This is enforced in exactly
one module, and `ml/train.py` asserts it at runtime:

```python
assert (meta[:, 1] + meta[:, 2]).max() <= split.TRAIN_END_IDX, "holdout leaked into training"
```

### ✅ 3. Quantile cash-flow forecaster — `ml/forecast.py` *(the core AI)*

Three `HistGradientBoostingRegressor` models with `loss="quantile"` at **α = 0.10 /
0.50 / 0.90**, trained on 360,000 rows × 36 features.

**What it predicts:** the *cumulative* net cash flow over the next h = 1…30 days — not
the per-day flow. This is a deliberate product decision: the app needs a balance
**path** with an honest uncertainty band, and summing 30 independent per-day quantiles
would compound into a meaningless band. Predicting the cumulative directly gives

```
balance_path_q[h] = balance_today + cumulative_forecast_q[h]
```

which is exactly what the risk-window detector and the savings optimiser consume.

**Features** (36): horizon, target-day calendar (day-of-month, weekday, Bangladesh
weekend flag, month progress), days-to-payday *learned from the user's own inflow
history*, lagged and rolling net flow (7/14/30-day means and standard deviations),
current and 30-day-average balance, days since last inflow, inflow count and size,
cash-out rate, fee burden, recurring-payment share, 30-day rolling average per spending
category, plus archetype / income band / area as native categorical features.

**Baseline it must beat:** the per-user mean net flow by day-of-month, accumulated over
the same horizon. That baseline is *also handed to the model as a feature*, so the model
is structurally able to match it and is only rewarded for improving on it.

The three quantiles are fitted independently and can cross, so predictions are
monotonicity-corrected before they ever reach a customer — a P10 band is never shown
above its P90.

### ✅ 4. Transaction categoriser — `ml/categorizer.py`

Character n-gram TF-IDF (`char_wb`, 2–4) over the counterparty string, combined with
amount, hour, direction and round-amount signals, classified into 9 categories by
logistic regression.

Merchant strings in the generated data are deliberately messy (random casing,
whitespace stripped, trailing tokens, masked phone numbers), so this is not a keyword
lookup. A hand-written **keyword-rule baseline** (`rule_predict`) ships alongside it and
is reported next to the model in the metrics, so the value added by learning is visible
rather than asserted.

### 🚧 5. Safe-to-save optimiser — `rules/`

Pure deterministic Python, **kept strictly out of the ML layer** (guideline: "Keep
business rules distinct from machine-learning predictions"). Consumes the **P10**
(pessimistic) forecast path and returns:

- the largest weekly auto-save amount that never breaches the user's safety floor
- a goal feasibility verdict, with trade-offs ("extend by 3 weeks" / "redirect your
  cash-out fees")
- the **risk window** — the exact dates the balance is predicted to go short

### 🚧 6. Cash-out leakage detector — `rules/`

Mines repeated, habitual withdrawals from categorised history and quantifies the annual
fee cost, naming the digital substitutes the user already uses.

### 🚧 7. Plain-Bangla explanation layer — `nlg/`

Structured evidence → Bangla sentence. Ships with a **deterministic template provider**
behind an `LLMProvider` interface, so an LLM key can be dropped in later without
touching the API. The language layer only ever *renders numbers it is handed* — it
never makes a decision. This is the guideline's "do not put sensitive decision logic
entirely inside a free-form LLM prompt", enforced structurally.

### 🚧 8. FastAPI service — `api/`

### 🚧 9. Flutter customer app — `app/`

---

## AI Components — where AI is actually used

| Component | Technique | Role | Not AI (deliberately) |
|---|---|---|---|
| Cash-flow forecaster | Gradient-boosted quantile regression | **Prediction** of the 30-day balance path with uncertainty | — |
| Transaction categoriser | TF-IDF char n-grams + logistic regression | **Classification** of messy merchant strings | — |
| Explainability | Permutation importance + per-prediction feature contribution | **Explanation** of what drives the forecast | — |
| Safe-to-save optimiser | — | — | Deterministic rules, auditable line by line |
| Leakage detector | — | — | Pattern mining, no model |
| Narrative | Template NLG (LLM-pluggable) | **Generation** of the Bangla sentence only | Never decides anything |

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Python 3.14, Dart |
| Data | pandas 3.0, NumPy, CSV + compressed `.npz` panel cache |
| ML | scikit-learn 1.9 (`HistGradientBoostingRegressor` with quantile loss, `LogisticRegression`, `TfidfVectorizer`), SciPy, joblib |
| Business rules | Pure Python (no framework) |
| GenAI | Pluggable `LLMProvider`; deterministic template provider by default |
| API | FastAPI + Uvicorn |
| Frontend | Flutter (Dart), `http`, `fl_chart` |
| Testing | pytest |
| Database | None — the prototype reads generated CSV / joblib artifacts. API responses are typed and versioned so the app can be repointed at a real backend unchanged. |

**Why not XGBoost/LightGBM?** Neither has reliable wheels for Python 3.14 yet.
scikit-learn's `HistGradientBoosting*` is the same algorithm family (histogram-based
gradient boosting), ships in the box, and supports native categorical features and
quantile loss — so the dependency risk buys us nothing.

---

## Requirements

### Software
- **Python 3.11+** (developed on 3.14.3)
- **Flutter SDK 3.x** with Dart (only needed for the mobile app)
- **Git**

### Hardware
Nothing special. Training both models takes **~2.5 minutes on a laptop CPU**; no GPU is
used or needed. Peak RAM during training is under 2 GB. The generated dataset is ~47 MB
on disk.

### Python dependencies
```
numpy
pandas
scikit-learn
scipy
joblib
fastapi
uvicorn[standard]
pytest
```

---

## Installation & Setup

```bash
# 1. Clone
git clone https://github.com/MuradAhmedTahmim/Upay-Shadhin.git
cd Upay-Shadhin

# 2. (recommended) create a virtual environment
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS / Linux:
source .venv/bin/activate

# 3. Install Python dependencies
python -m pip install -r requirements.txt

# 4. Generate the synthetic dataset  (~25 s, writes data/*.csv)
python data/generate.py

# 5. Train both models  (~2.5 min, writes ml/artifacts/*.joblib)
python -m ml.train

# 6. Reproduce the evaluation on the untouched holdout
python -m ml.evaluate        # writes docs/metrics.md
```

> **Why aren't the dataset and models in the repository?**
> They are generated artifacts, not source. `data/*.csv` (47 MB) and
> `ml/artifacts/*.joblib` are git-ignored and fully reproducible from a fixed seed by
> steps 4–5 above. The repository holds the code that produces them, which is the thing
> worth reviewing.

### Flutter app

```bash
cd app
flutter pub get
flutter run -d windows     # or:  flutter run -d chrome
```

---

## Environment Variables

The prototype runs **with no environment variables set at all** — this is intentional,
so a judge can clone and run it without obtaining any credentials.

The following are optional. Copy `.env.example` to `.env` and fill in as needed.
**Never commit `.env`;** it is git-ignored.

| Variable | Purpose | Default if unset |
|---|---|---|
| `SHADHIN_LLM_PROVIDER` | Which narrative provider to use: `template`, `claude`, or `gemini` | `template` (deterministic, no network) |
| `SHADHIN_LLM_API_KEY` | API key for the chosen LLM provider. **Placeholder only — never commit a real key.** | unset; the template provider is used |
| `SHADHIN_API_HOST` | Host the FastAPI service binds to | `127.0.0.1` |
| `SHADHIN_API_PORT` | Port the FastAPI service binds to | `8000` |
| `SHADHIN_API_BASE_URL` | Base URL the Flutter app calls | `http://127.0.0.1:8000` |

Example `.env`:
```
SHADHIN_LLM_PROVIDER=template
SHADHIN_LLM_API_KEY=your_api_key_here
SHADHIN_API_BASE_URL=http://127.0.0.1:8000
```

---

## Run & Build Commands

| Task | Command |
|---|---|
| Show the train/holdout split being enforced | `python -m ml.split` |
| Generate synthetic data | `python data/generate.py` |
| Generate a larger/smaller dataset | `python data/generate.py --users 2000 --days 365 --seed 42` |
| Rebuild the user×day panel cache | `python -m ml.panel` |
| Train both models | `python -m ml.train` |
| Evaluate on the holdout | `python -m ml.evaluate` |
| Run the API (development) | `uvicorn api.main:app --reload` |
| Run the API (fixed port) | `uvicorn api.main:app --host 127.0.0.1 --port 8000` |
| Run the test suite | `python -m pytest -q` |
| Run the Flutter app | `cd app && flutter run -d windows` |
| Build the Flutter web bundle | `cd app && flutter build web --release` |
| Build the Android APK | `cd app && flutter build apk --release` |

---

## Live Deployment URL

**Status: not yet deployed.** 🚧

The API and the Flutter web build will be deployed during the hackathon window, and
**this section will be updated with the actual live URL** as soon as it is available.

Until then, the project runs fully locally by following *Installation & Setup* above —
no credentials or external services are required.

| Component | Planned deployment | URL |
|---|---|---|
| Flutter web app | static hosting | _to be added_ |
| FastAPI service | container host | _to be added_ |

---

## Testing Instructions

### 1. Verify the synthetic data contains the patterns it claims

```bash
python data/generate.py
```

Expected output:
```
users       : 800
transactions: 537,598
window      : 2026-01-04 .. 2026-09-30  (270 days)
holdout     : last 30 days (2026-09-01 .. 2026-09-30)
```

Sanity-check the injected behaviour:

```bash
python -c "import pandas as pd, numpy as np; tx=pd.read_csv('data/transactions.csv',parse_dates=['date']); tx['s']=np.where(tx.direction=='credit',tx.amount,-tx.amount); d=tx.groupby(['user_id','date'])['s'].sum().reset_index(); d['dom']=d.date.dt.day; print(d.groupby('dom')['s'].mean().round(0).head(15))"
```

**Expected:** net flow is clearly **positive on days 1–7** (payday) and turns
**negative from about day 8 onward** — the month-end dip the product exists to solve.

### 2. Verify the holdout is genuinely untouched

```bash
python -m ml.split
```

**Expected:** training as-of dates end at `2026-08-01`; with a 30-day horizon the last
training target lands on `2026-08-31`, one day before the holdout opens. `ml/train.py`
re-asserts this at runtime and will raise `holdout leaked into training` if it is ever
violated.

### 3. Train and evaluate

```bash
python -m ml.train
python -m ml.evaluate
```

**Expected:** `docs/metrics.md` is written, containing
- forecaster MAE **below** the day-of-month baseline, with the % improvement
- P10–P90 coverage close to **0.80**
- categoriser macro-F1 **above** the keyword-rule baseline
- a fairness table breaking error down by income band, area and gender
- the simulated goal-completion uplift and ৳/year leakage figures

### 4. Run the unit tests

```bash
python -m pytest -q
```

Key cases covered: the savings optimiser never proposes an amount that breaches the
safety floor; the forecast quantile band is never inverted; the holdout split is
respected.

### 5. Manual end-to-end check (once the API and app are up) 🚧

1. `uvicorn api.main:app --reload`, then open `http://127.0.0.1:8000/docs`
2. Call `GET /forecast/{user_id}` — the response carries a `reasons[]` array and a
   `model_version`, so every number is traceable
3. `cd app && flutter run -d windows` and walk the four screens
4. **Kill the API and walk the app again** — it falls back to bundled fixtures, so the
   demo survives a dead backend

---

## Other Configuration

- **No database, no cloud account, no API key** is required to run the prototype.
- `ml/_panel_cache.npz` is a compressed cache of the user×day matrices. Delete it or run
  `python -m ml.panel` to force a rebuild after regenerating the data.
- `data/generate.py` takes `--users`, `--days` and `--seed`. Changing any of them
  invalidates the panel cache and the trained models — rerun `python -m ml.panel` and
  `python -m ml.train`.
- All randomness is seeded. Two clean runs of the pipeline produce identical numbers.

---

## Responsible AI

Built against the hackathon's Responsible AI table, not retrofitted to it.

| Principle | How this project satisfies it |
|---|---|
| **Privacy** | 100% synthetic data, generated locally from a fixed seed. No production data, no PII, no external data collection. Phone numbers in the data are masked patterns (`017XXXXX123`), not numbers. |
| **Explainability** | Every forecast carries a `reasons[]` array derived from feature attribution. The savings recommendation is deterministic rules over the forecast, auditable line by line. |
| **Fairness** | Forecast error is reported broken down by income band, urban/rural and gender. Gender is assigned independently of all financial behaviour in the generator, so any gap the table shows is a property of the *model*, not the data. |
| **Security** | No secrets in the repository; `.env` is git-ignored. The LLM layer receives only pre-computed numbers and cannot execute an action, so there is no prompt-injection path to a financial decision. |
| **Human oversight** | The auto-save plan is **proposed**, never executed. The user confirms. |
| **Transparency** | Predictions, deterministic rules and generated language live in three separate packages (`ml/`, `rules/`, `nlg/`) and are labelled as such in the UI. |
| **No harmful automation** | No autonomous money movement. No credit approval or denial — at most an *explainable readiness signal* that tells a customer which behaviours matter, with no lending decision attached. |

---

## Repository Structure

```
shadhin/
├── data/          synthetic generator + documented assumptions
│   ├── generate.py
│   └── ASSUMPTIONS.md
├── ml/            data prep and models (prediction only)
│   ├── split.py          <- the single source of truth for train/holdout
│   ├── panel.py          <- user x day matrices
│   ├── forecast.py       <- quantile cash-flow forecaster
│   ├── categorizer.py    <- transaction categoriser + rule baseline
│   ├── train.py
│   └── evaluate.py
├── rules/         deterministic business logic (no ML)
├── nlg/           evidence -> plain-Bangla narrative
├── api/           FastAPI service
├── app/           Flutter customer app
├── docs/          metrics, idea framework, pitch notes
└── tests/
```

---

## Status & Roadmap

| Block | Scope | Status |
|---|---|---|
| A | Synthetic data generator + documented assumptions | ✅ done |
| B | Categoriser + quantile forecaster + holdout evaluation | ✅ models trained, 🚧 evaluation report |
| C | Safe-to-save optimiser + leakage detector + tests | 🚧 |
| D | FastAPI service | 🚧 |
| E | Flutter app (Home / Insights / Goal / Why) | 🚧 |
| F | Fairness table, idea framework, pitch, deployment | 🚧 |

---

## Licence & Attribution

Built for AI Hackathon 2026 (DIU CPC × upay). Synthetic data only; not affiliated with
or endorsed by upay. The 1.49% cash-out fee used in the simulation is a plausible
market-style figure chosen for modelling purposes and is **not** a quoted upay tariff —
all "fee saved" figures scale linearly with it and would be re-based against the real
tariff card before any real-world claim.
