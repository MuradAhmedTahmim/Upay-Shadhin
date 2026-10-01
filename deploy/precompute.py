"""
Precompute the demo bundle the published web app ships with.

Why this exists: the published app has no backend. Hosting the FastAPI service on a
free tier means either paying for it or handing a judge a one-minute cold start on
their first click, and a demo that makes people wait is worse than one that does not.

So every figure the hosted app shows is still **real model output** - the same
`api/service.py` code path the live API serves - just computed ahead of time and
written to JSON. Nothing is mocked, hand-written or rounded for presentation.

The one thing that cannot be precomputed is goal simulation, because the customer moves
the sliders. That arithmetic is ported to Dart (`app/lib/goal_math.dart`) and tested
against this module's output so the two cannot drift apart silently.

    python -m deploy.precompute [--users 12]
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from api import service

OUT = Path(__file__).resolve().parent.parent / "app" / "assets" / "demo"

# Goal cases written into the manifest so the Dart port can be tested against the
# Python implementation rather than against hand-copied expectations.
GOAL_CASES = [
    (30000, 180),
    (30000, 90),
    (50000, 365),
    (100000, 180),
    (10000, 30),
]


def main(n_users: int) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    e = service.engine()

    users = service.list_users(limit=500)

    # Pick a spread of archetypes rather than the first N, so the demo switcher shows
    # a salaried customer, a gig earner and a trader instead of three near-identical
    # profiles. Within each archetype, prefer customers who actually have savings
    # capacity - a demo where every verdict is "no" shows nothing working.
    chosen: list[dict] = []
    by_type: dict[str, list[dict]] = {}
    for u in users:
        by_type.setdefault(u["archetype"], []).append(u)

    with_capacity = []
    for archetype, group in by_type.items():
        for u in group[:60]:
            sts = service.safe_to_save(u["user_id"])
            if sts["weekly_amount"] > 0:
                with_capacity.append((archetype, u))
            if len([a for a, _ in with_capacity if a == archetype]) >= 4:
                break

    seen = set()
    while len(chosen) < n_users and with_capacity:
        for archetype in sorted(by_type):
            for i, (a, u) in enumerate(with_capacity):
                if a == archetype and u["user_id"] not in seen:
                    chosen.append(u)
                    seen.add(u["user_id"])
                    with_capacity.pop(i)
                    break
            if len(chosen) >= n_users:
                break
        else:
            continue
        if not with_capacity:
            break

    manifest_users = []
    for u in chosen:
        uid = u["user_id"]
        profile = service.profile(uid)
        bundle = {
            "profile": profile,
            "forecast": service.forecast_for(uid),
            "insights": service.insights(uid),
            "safe_to_save": service.safe_to_save(uid),
            # Reference outputs for the Dart port of the goal optimiser.
            "goal_cases": [
                {
                    "goal_amount": amount,
                    "deadline_days": days,
                    "expected": service.simulate_goal(uid, amount, days),
                }
                for amount, days in GOAL_CASES
            ],
        }
        (OUT / f"{uid}.json").write_text(
            json.dumps(bundle, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        manifest_users.append({
            "user_id": uid,
            "archetype": profile["archetype"],
            "income_band": profile["income_band"],
            "area": profile["area"],
            "balance": profile["balance"],
        })

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "as_of": e.as_of.isoformat(),
        "forecast_model": e.model_version,
        "categoriser_model": e.cat.version,
        "data": "synthetic",
        "note": "Precomputed from the same api/service.py the live API serves. "
                "Every figure is real model output.",
        "users": manifest_users,
    }
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    total = sum(f.stat().st_size for f in OUT.glob("*.json"))
    print(f"wrote {len(manifest_users)} customers + manifest to {OUT}")
    print(f"  archetypes: {sorted({u['archetype'] for u in manifest_users})}")
    print(f"  total size: {total / 1024:.0f} KB")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--users", type=int, default=12)
    main(ap.parse_args().users)
