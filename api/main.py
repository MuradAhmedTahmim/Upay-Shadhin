"""
FastAPI service for upay Shadhin.

A thin HTTP wrapper over api/service.py. Responses are typed and every one of them
carries `model_version`, so a number on a screen can always be traced back to the model
that produced it - the guideline's "make model outputs traceable and explainable".

    uvicorn api.main:app --reload
    open http://127.0.0.1:8000/docs
"""
from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from . import service

app = FastAPI(
    title="upay Shadhin API",
    version="1.0.0",
    description=(
        "AI cash-flow copilot for mobile-wallet customers. All data is synthetic. "
        "No endpoint moves money: savings plans are proposals that require explicit "
        "customer confirmation."
    ),
)

# The Flutter app runs from a different origin in web builds.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


class GoalRequest(BaseModel):
    user_id: str = Field(..., examples=["U100000"])
    goal_amount: float = Field(..., gt=0, examples=[30000])
    deadline_days: int = Field(..., gt=0, le=1095, examples=[180])


class CoachRequest(BaseModel):
    user_id: str
    question: str


@app.get("/health", tags=["meta"])
def health() -> dict:
    e = service.engine()
    return {
        "status": "ok",
        "as_of": e.as_of.isoformat(),
        "users": e.p.n_users,
        "forecast_model": e.model_version,
        "categoriser_model": e.cat.version,
        "data": "synthetic",
    }


@app.get("/users", tags=["customer"])
def users(limit: int = Query(50, ge=1, le=500)) -> list[dict]:
    """Demo user directory. Real deployments would resolve the customer from auth."""
    return service.list_users(limit)


@app.get("/profile/{user_id}", tags=["customer"])
def profile(user_id: str) -> dict:
    try:
        return service.profile(user_id)
    except KeyError:
        raise HTTPException(404, f"unknown user {user_id}")


@app.get("/forecast/{user_id}", tags=["intelligence"])
def forecast(user_id: str) -> dict:
    """30-day cash-flow forecast with a P10-P90 band and the predicted risk window."""
    try:
        return service.forecast_for(user_id)
    except KeyError:
        raise HTTPException(404, f"unknown user {user_id}")


@app.get("/insights/{user_id}", tags=["intelligence"])
def insights(user_id: str) -> dict:
    """Spending categories and cash-out leakage, with the evidence behind each claim."""
    try:
        return service.insights(user_id)
    except KeyError:
        raise HTTPException(404, f"unknown user {user_id}")


@app.get("/safe-to-save/{user_id}", tags=["action"])
def safe_to_save(user_id: str) -> dict:
    """
    The largest weekly auto-save that the pessimistic forecast says is safe.

    This is a **proposal**. It is never executed without explicit customer
    confirmation, which is why the response carries `requires_confirmation: true`.
    """
    try:
        return service.safe_to_save(user_id)
    except KeyError:
        raise HTTPException(404, f"unknown user {user_id}")


@app.post("/goal/simulate", tags=["action"])
def goal_simulate(req: GoalRequest) -> dict:
    """Feasibility verdict for a savings goal, with trade-offs. Changes nothing."""
    try:
        return service.simulate_goal(req.user_id, req.goal_amount, req.deadline_days)
    except KeyError:
        raise HTTPException(404, f"unknown user {req.user_id}")


@app.get("/metrics", tags=["meta"])
def metrics() -> dict:
    """Holdout metrics report, so the numbers behind the product are inspectable."""
    path = Path(__file__).resolve().parent.parent / "docs" / "metrics.md"
    if not path.exists():
        raise HTTPException(404, "run `python -m ml.evaluate` first")
    return {"report": path.read_text(encoding="utf-8")}
