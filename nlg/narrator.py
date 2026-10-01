"""
Evidence -> plain-Bangla narrative.

The hard rule this module exists to enforce: **the language layer never decides
anything.** It receives numbers that `ml/` predicted and `rules/` decided, and turns
them into a sentence. It cannot change an amount, approve a plan, or invent a figure.

That is the structural answer to the guideline's "do not put sensitive decision logic
entirely inside a free-form LLM prompt" - here there is no path from generated text back
into a financial decision, so there is nothing for a prompt injection to reach.

The default provider is deterministic templates, so the prototype runs with no API key
and no network. `LLMProvider` is the seam: a Claude or Gemini provider can be dropped in
by setting SHADHIN_LLM_PROVIDER, and it would be handed the same evidence dict and asked
only to phrase it more naturally.
"""
from __future__ import annotations

import os
from abc import ABC, abstractmethod

BN_DIGITS = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")

BN_MONTHS = {
    1: "জানুয়ারি", 2: "ফেব্রুয়ারি", 3: "মার্চ", 4: "এপ্রিল", 5: "মে", 6: "জুন",
    7: "জুলাই", 8: "আগস্ট", 9: "সেপ্টেম্বর", 10: "অক্টোবর", 11: "নভেম্বর", 12: "ডিসেম্বর",
}

CATEGORY_BN = {
    "income": "আয়",
    "rent": "বাসা ভাড়া",
    "utility": "বিল (বিদ্যুৎ/গ্যাস/পানি)",
    "mobile_recharge": "মোবাইল রিচার্জ",
    "family_support": "পরিবারকে পাঠানো",
    "food_grocery": "খাবার ও বাজার",
    "transport": "যাতায়াত",
    "cash_out": "ক্যাশ-আউট",
    "other_retail": "অন্যান্য কেনাকাটা",
}


def bn_num(x: float, decimals: int = 0) -> str:
    """Format a number with thousands separators in Bangla digits."""
    s = f"{x:,.{decimals}f}"
    return s.translate(BN_DIGITS)


def bn_date(iso: str) -> str:
    """'2026-09-24' -> '২৪ সেপ্টেম্বর'"""
    try:
        y, m, d = (int(p) for p in iso.split("-"))
    except (ValueError, AttributeError):
        return iso
    return f"{str(d).translate(BN_DIGITS)} {BN_MONTHS.get(m, '')}".strip()


class LLMProvider(ABC):
    """The seam. A real LLM provider implements render() and nothing else."""

    name = "abstract"

    @abstractmethod
    def render(self, kind: str, evidence: dict) -> dict:
        """Return {'bn': ..., 'en': ...} for one piece of evidence."""


class TemplateProvider(LLMProvider):
    """
    Deterministic Bangla/English templates. No network, no key, no variance.

    Every string is built only from values present in `evidence`, so a sentence can
    never claim something the model did not predict.
    """

    name = "template"

    def render(self, kind: str, e: dict) -> dict:
        fn = getattr(self, f"_{kind}", None)
        if fn is None:
            return {"bn": "", "en": ""}
        return fn(e)

    # ---------------------------------------------------------------- forecast

    def _forecast_summary(self, e: dict) -> dict:
        end = bn_num(e["expected_balance_end"])
        return {
            "bn": f"আগামী ৩০ দিনে আপনার ব্যালেন্স আনুমানিক ৳{end} হতে পারে। "
                  f"সম্ভাব্য সীমা ৳{bn_num(e['low_balance_end'])} থেকে "
                  f"৳{bn_num(e['high_balance_end'])}।",
            "en": f"Over the next 30 days your balance is projected to be about "
                  f"BDT {e['expected_balance_end']:,.0f}, with a likely range of "
                  f"{e['low_balance_end']:,.0f} to {e['high_balance_end']:,.0f}.",
        }

    def _risk_window(self, e: dict) -> dict:
        if not e.get("has_risk"):
            return {
                "bn": "আগামী ৩০ দিনে আপনার ব্যালেন্স নিরাপত্তা সীমার নিচে নামার "
                      "সম্ভাবনা দেখা যাচ্ছে না।",
                "en": "No shortfall is projected in the next 30 days.",
            }
        return {
            "bn": f"{bn_date(e['start_date'])} থেকে {bn_date(e['end_date'])} পর্যন্ত "
                  f"আপনার ব্যালেন্স ৳{bn_num(e['lowest_balance'])} পর্যন্ত নামতে পারে, "
                  f"যা আপনার নিরাপত্তা সীমা ৳{bn_num(e['floor'])}-এর নিচে। "
                  f"এই সময়ের আগে কিছু টাকা হাতে রাখলে ভালো হয়।",
            "en": f"Between {e['start_date']} and {e['end_date']} your balance could fall "
                  f"to BDT {e['lowest_balance']:,.0f}, below your safety floor of "
                  f"{e['floor']:,.0f}. Keeping a buffer before then would help.",
        }

    def _safe_to_save(self, e: dict) -> dict:
        if e["weekly_amount"] <= 0:
            return {
                "bn": "এই মুহূর্তে নিয়মিত সঞ্চয় শুরু করার মতো অতিরিক্ত টাকা "
                      "পূর্বাভাসে দেখা যাচ্ছে না। আগে মাস শেষের ঘাটতি সামলানো "
                      "বেশি জরুরি।",
                "en": "The forecast does not show room for a regular savings plan right "
                      "now. Covering the month-end gap comes first.",
            }
        bn = (f"পূর্বাভাস অনুযায়ী আপনি প্রতি সপ্তাহে ৳{bn_num(e['weekly_amount'])} "
              f"পর্যন্ত নিরাপদে জমাতে পারেন — মাসে প্রায় "
              f"৳{bn_num(e['monthly_equivalent'])}।")
        en = (f"You can safely set aside up to BDT {e['weekly_amount']:,.0f} per week, "
              f"about {e['monthly_equivalent']:,.0f} per month.")
        if e.get("binding_date"):
            bn += (f" এই পরিমাণ ঠিক করা হয়েছে {bn_date(e['binding_date'])} তারিখের "
                   f"কথা মাথায় রেখে, কারণ ওই দিনই আপনার ব্যালেন্স সবচেয়ে চাপে থাকবে।")
            en += (f" The amount is sized around {e['binding_date']}, the tightest day in "
                   f"the next 30.")
        return {"bn": bn, "en": en}

    def _goal(self, e: dict) -> dict:
        amt, weeks = bn_num(e["goal_amount"]), bn_num(e["weeks"])
        if e["verdict"] == "feasible":
            return {
                "bn": f"৳{amt} জমানোর লক্ষ্যটি বাস্তবসম্মত। সপ্তাহে "
                      f"৳{bn_num(e['safe_weekly'])} করে রাখলে {weeks} সপ্তাহে "
                      f"লক্ষ্যে পৌঁছাবেন।",
                "en": f"Your goal of BDT {e['goal_amount']:,.0f} is achievable: "
                      f"{e['safe_weekly']:,.0f} per week reaches it in {e['weeks']} weeks.",
            }
        if e["verdict"] == "tight":
            return {
                "bn": f"৳{amt} জমানোর লক্ষ্যটি সম্ভব, তবে বেশ টানটান। "
                      f"দরকার সপ্তাহে ৳{bn_num(e['required_weekly'])}, "
                      f"আর নিরাপদে সম্ভব ৳{bn_num(e['safe_weekly'])}।",
                "en": f"The goal is close but tight: it needs "
                      f"{e['required_weekly']:,.0f} per week and "
                      f"{e['safe_weekly']:,.0f} is what is safely available.",
            }
        return {
            "bn": f"এই সময়ের মধ্যে ৳{amt} জমানো বাস্তবসম্মত নয়। দরকার সপ্তাহে "
                  f"৳{bn_num(e['required_weekly'])}, কিন্তু নিরাপদে সম্ভব "
                  f"৳{bn_num(e['safe_weekly'])}। সময় বাড়ালে বা খরচ কমালে "
                  f"লক্ষ্যটি সম্ভব হতে পারে।",
            "en": f"This goal is not realistic in the time given: it needs "
                  f"{e['required_weekly']:,.0f} a week against "
                  f"{e['safe_weekly']:,.0f} available. Extending the deadline or "
                  f"reducing an outflow would change that.",
        }

    def _leakage(self, e: dict) -> dict:
        if e["fees_annualised"] <= 0:
            return {
                "bn": "গত ৯০ দিনে উল্লেখযোগ্য ক্যাশ-আউট ফি দেখা যায়নি।",
                "en": "No significant cash-out fees in the last 90 days.",
            }
        bn = (f"গত ৯০ দিনে ক্যাশ-আউট ফি বাবদ গেছে ৳{bn_num(e['fees_paid'])} — "
              f"বছরে যা প্রায় ৳{bn_num(e['fees_annualised'])}।")
        en = (f"You paid BDT {e['fees_paid']:,.0f} in cash-out fees over 90 days, "
              f"about {e['fees_annualised']:,.0f} a year.")
        if e.get("avoidable_fees_annualised", 0) > 0:
            subs = ", ".join(CATEGORY_BN.get(s, s) for s in e.get("substitutes", [])[:2])
            bn += (f" এর মধ্যে আনুমানিক ৳{bn_num(e['avoidable_fees_annualised'])} "
                   f"এড়ানো সম্ভব, কারণ আপনি ইতিমধ্যেই {subs} ডিজিটালি পরিশোধ করেন।")
            en += (f" About {e['avoidable_fees_annualised']:,.0f} of that looks avoidable, "
                   f"since you already pay for {', '.join(e.get('substitutes', [])[:2])} "
                   f"digitally.")
        if e.get("habitual_amounts"):
            h = e["habitual_amounts"][0]
            bn += (f" আপনি ৳{bn_num(h['amount'])} করে {bn_num(h['times'])} বার "
                   f"তুলেছেন — এটি একটি নিয়মিত অভ্যাস।")
            en += (f" You withdrew {h['amount']:,.0f} {h['times']} times - that is a "
                   f"routine, not a one-off.")
        return {"bn": bn, "en": en}

    def _spending(self, e: dict) -> dict:
        top = e["top_categories"][:3]
        parts_bn = [f"{CATEGORY_BN.get(c['category'], c['category'])} "
                    f"৳{bn_num(c['amount'])}" for c in top]
        parts_en = [f"{c['category']} {c['amount']:,.0f}" for c in top]
        return {
            "bn": "গত ৩০ দিনে আপনার সবচেয়ে বড় খরচ: " + ", ".join(parts_bn) + "।",
            "en": "Your largest outflows in the last 30 days: " + ", ".join(parts_en) + ".",
        }


def get_provider() -> LLMProvider:
    """
    Pick a narrative provider from the environment.

    Only the template provider is implemented. If a key-backed provider is configured
    but unavailable we fall back to templates rather than failing the request - a
    customer should still see their numbers when the language service is down.
    """
    choice = os.environ.get("SHADHIN_LLM_PROVIDER", "template").lower()
    if choice != "template" and not os.environ.get("SHADHIN_LLM_API_KEY"):
        return TemplateProvider()
    return TemplateProvider()


PROVIDER = get_provider()


def say(kind: str, evidence: dict) -> dict:
    return PROVIDER.render(kind, evidence)
