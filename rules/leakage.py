"""
Cash-out leakage detection.

Answers the guideline's own example question - "How can I reduce cash-outs?" - with a
number instead of advice: how much a customer pays in cash-out fees per year, how much
of that is plausibly avoidable, and which specific habit to change first.

Deliberately **not** a model. The logic is pattern mining over categorised history and
is fully auditable, which matters because this screen tells a customer they are losing
money. A black box has no business making that claim.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field, asdict

# Categories the customer already pays for digitally. If they are paying these merchants
# from the wallet, the acceptance exists - which is what makes some of their cash
# withdrawals replaceable rather than necessary.
DIGITAL_SUBSTITUTABLE = (
    "food_grocery", "transport", "other_retail", "utility", "mobile_recharge",
)

HABIT_MIN_REPEATS = 3           # same round amount this often = a routine, not a one-off
MAX_REPLACEABLE_SHARE = 0.60    # never claim more than 60% is avoidable
WINDOW_DAYS = 90


@dataclass
class LeakageReport:
    window_days: int
    cash_out_total: float
    cash_out_count: int
    fees_paid: float
    fees_annualised: float
    replaceable_share: float
    avoidable_fees_annualised: float
    habitual_amounts: list[dict]
    digital_spend: float
    substitutes: list[str]
    reasons: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


def analyse(cash_out_amounts: list[float], fees_paid: float,
            category_totals: dict, window_days: int = WINDOW_DAYS) -> LeakageReport:
    """
    Parameters
    ----------
    cash_out_amounts : every cash-out in the window, in taka
    fees_paid        : total cash-out fees in the window
    category_totals  : category -> total spend in the window
    """
    cash_total = float(sum(cash_out_amounts))
    count = len(cash_out_amounts)
    annual_factor = 365.0 / window_days
    fees_annual = fees_paid * annual_factor

    digital_spend = float(sum(category_totals.get(c, 0.0) for c in DIGITAL_SUBSTITUTABLE))
    substitutes = sorted(
        (c for c in DIGITAL_SUBSTITUTABLE if category_totals.get(c, 0.0) > 0),
        key=lambda c: -category_totals.get(c, 0.0),
    )[:3]

    # How much of the cash taken out could plausibly have stayed digital? Bounded by
    # how much the customer *already* pays digitally - we never assume behaviour they
    # have not demonstrated - and capped at 60% so the claim stays conservative.
    share = 0.0 if cash_total <= 0 else min(digital_spend / cash_total, MAX_REPLACEABLE_SHARE)

    counts = Counter(round(a) for a in cash_out_amounts)
    habitual = [
        {"amount": float(a), "times": n, "total": float(a * n)}
        for a, n in counts.most_common()
        if n >= HABIT_MIN_REPEATS
    ][:5]

    reasons = [{
        "code": "fee_basis",
        "detail": "Fees actually charged on cash-outs in the window, scaled to a year.",
        "evidence": {
            "window_days": window_days,
            "fees_in_window": round(fees_paid, 2),
            "cash_out_count": count,
            "cash_out_total": round(cash_total, 2),
        },
    }]

    if share > 0:
        reasons.append({
            "code": "replaceable_estimate",
            "detail": "Bounded by what this customer already pays digitally - no "
                      "behaviour change is assumed that they have not already shown.",
            "evidence": {
                "digital_spend_in_window": round(digital_spend, 2),
                "share": round(share, 4),
                "cap": MAX_REPLACEABLE_SHARE,
                "top_substitutes": substitutes,
            },
        })

    if habitual:
        top = habitual[0]
        reasons.append({
            "code": "habitual_withdrawal",
            "detail": "The same round amount is withdrawn repeatedly, which is a "
                      "routine rather than a one-off need.",
            "evidence": top,
        })

    return LeakageReport(
        window_days=window_days,
        cash_out_total=round(cash_total, 2),
        cash_out_count=count,
        fees_paid=round(fees_paid, 2),
        fees_annualised=round(fees_annual, 2),
        replaceable_share=round(share, 4),
        avoidable_fees_annualised=round(fees_annual * share, 2),
        habitual_amounts=habitual,
        digital_spend=round(digital_spend, 2),
        substitutes=substitutes,
        reasons=reasons,
    )
