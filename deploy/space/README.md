---
title: upay Shadhin API
emoji: 📊
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
license: mit
short_description: AI cash-flow copilot API for mobile-wallet customers (synthetic data)
---

# upay Shadhin — API

The backend for **upay Shadhin**, an AI cash-flow copilot built for AI Hackathon 2026
(DIU CPC × upay, Track 03 — Customer Innovation & Financial Independence).

> ⚠️ **All data here is synthetic.** It is generated inside this container at build time
> from a fixed seed. No production upay data, no real customer records, and no
> personally identifiable information is used anywhere.

**Customer app:** https://muradahmedtahmim.github.io/Upay-Shadhin/
**Source:** https://github.com/MuradAhmedTahmim/Upay-Shadhin

---

## What it does

Forecasts a wallet customer's next 30 days of cash flow, finds the days their balance is
predicted to dip below their own safety floor, and computes the largest weekly amount
they can save without causing that dip.

```
transactions → categoriser → forecaster → safe-to-save rule → proposal
                 (what)      (P10/P50/P90)   (deterministic)   (customer confirms)
```

The model estimates *what will happen*; a readable rule decides *what to do about it*.
Nothing here moves money: `/safe-to-save` and `/goal/simulate` return proposals carrying
`requires_confirmation: true`.

## Endpoints

Interactive docs at [`/docs`](/docs).

| Endpoint | Returns |
|---|---|
| `GET /health` | Service status, as-of date, model versions |
| `GET /users` | Demo customer directory |
| `GET /profile/{id}` | Balance, safety floor, 30-day inflow/outflow |
| `GET /forecast/{id}` | 30-day path with P10/P50/P90, risk window, `reasons[]` |
| `GET /insights/{id}` | Spending categories and cash-out leakage, with evidence |
| `GET /safe-to-save/{id}` | The weekly amount the forecast supports |
| `POST /goal/simulate` | Feasibility verdict and trade-offs |
| `GET /metrics` | The holdout metrics report |

Try `GET /forecast/U100007`. Every response carries `model_version`, so a number on a
screen can be traced back to the model that produced it.

## "Today" is 2026-08-31

That is the last day any model was allowed to see. Everything the API says about "the
next 30 days" is a genuine forward forecast over a holdout window, not a replay of data
the model already knows.

## How this image is built

The dataset and models are generated during `docker build` — they are reproducible
artifacts, not source — so the running service and the metrics it serves come from
exactly the code in this commit:

```
python data/generate.py    # 800 customers x 270 days, fixed seed
python -m ml.train         # categoriser + 3 quantile forecasters + conformal calibration
python -m ml.evaluate      # holdout report served at /metrics
```

## Holdout results

| Metric | Result |
|---|---|
| Forecast MAE vs day-of-month baseline | 8.4% lower |
| P10–P90 coverage after conformal calibration | 0.746 |
| Categoriser macro-F1 vs keyword rules | 0.9998 vs 0.9675 |
| Risk-window flag | precision 0.920, recall 0.984 |
| Plan-caused shortfalls, at matched savings | 1.1% vs 1.5% |

Full report: `GET /metrics`.
