/// Goal feasibility, computed in the app.
///
/// This is a deliberate port of `plan_goal` in `rules/optimizer.py`. It exists because
/// the customer drags sliders: the published app has no backend, and even with one, a
/// round trip per slider tick is the wrong shape for this interaction.
///
/// Two implementations of the same rule is normally a smell, so the risk is contained:
/// `deploy/precompute.py` records the Python result for a set of goal cases in every
/// demo bundle, and `test/goal_math_test.dart` asserts this port reproduces them
/// exactly. If the Python rule changes and this does not, the tests fail.
///
/// Only the arithmetic is duplicated. The wording is not: the verdict sentence is built
/// from the app's own string table (`i18n.dart`), so it reads the same as the rest of
/// the UI and switches language with it.
library;

import 'dart:math' as math;

/// Mirrors `SAVE_INTERVAL_DAYS` in rules/optimizer.py.
const int kSaveIntervalDays = 7;

/// Coverage at or above this is "tight" rather than "not feasible".
const double kTightThreshold = 0.85;

enum GoalVerdict { feasible, tight, notFeasible }

class GoalAlternative {
  const GoalAlternative({required this.code, this.extraWeeks, this.newDeadlineDays, this.newDeadlineDate, this.extraWeekly, this.newProjectedTotal, this.closesGap});

  final String code;
  final int? extraWeeks;
  final int? newDeadlineDays;
  final DateTime? newDeadlineDate;
  final double? extraWeekly;
  final double? newProjectedTotal;
  final bool? closesGap;
}

class GoalPlan {
  const GoalPlan({
    required this.goalAmount,
    required this.deadlineDays,
    required this.weeks,
    required this.verdict,
    required this.safeWeekly,
    required this.requiredWeekly,
    required this.projectedTotal,
    required this.coverage,
    required this.alternatives,
  });

  final double goalAmount;
  final int deadlineDays;
  final int weeks;
  final GoalVerdict verdict;
  final double safeWeekly;
  final double requiredWeekly;
  final double projectedTotal;
  final double coverage;
  final List<GoalAlternative> alternatives;
}

/// Turn a customer goal into an honest verdict plus trade-offs.
///
/// The point is to be willing to say no. An app that always answers "yes, you can do
/// it" is not helping someone decide anything.
GoalPlan planGoal({
  required double goalAmount,
  required int deadlineDays,
  required double safeWeekly,
  required DateTime asOf,
  double monthlyAvoidableFees = 0,
}) {
  final weeks = math.max(deadlineDays ~/ kSaveIntervalDays, 1);
  final projected = safeWeekly * weeks;
  final required = goalAmount / weeks;
  final coverage = goalAmount > 0 ? projected / goalAmount : 1.0;

  final verdict = coverage >= 1.0
      ? GoalVerdict.feasible
      : (coverage >= kTightThreshold ? GoalVerdict.tight : GoalVerdict.notFeasible);

  final alternatives = <GoalAlternative>[];

  if (verdict != GoalVerdict.feasible && safeWeekly > 0) {
    final weeksNeeded = (goalAmount / safeWeekly).ceil();
    alternatives.add(GoalAlternative(
      code: 'extend_deadline',
      extraWeeks: weeksNeeded - weeks,
      newDeadlineDays: weeksNeeded * kSaveIntervalDays,
      newDeadlineDate: asOf.add(Duration(days: weeksNeeded * kSaveIntervalDays)),
    ));
  }

  if (monthlyAvoidableFees > 0) {
    final extraWeekly = monthlyAvoidableFees * 12 / 52;
    final combined = (safeWeekly + extraWeekly) * weeks;
    alternatives.add(GoalAlternative(
      code: 'redirect_cash_out_fees',
      extraWeekly: extraWeekly,
      newProjectedTotal: combined,
      closesGap: combined >= goalAmount,
    ));
  }

  if (verdict == GoalVerdict.notFeasible && safeWeekly <= 0) {
    alternatives.add(const GoalAlternative(code: 'lower_floor_or_reduce_outflow'));
  }

  return GoalPlan(
    goalAmount: goalAmount,
    deadlineDays: deadlineDays,
    weeks: weeks,
    verdict: verdict,
    safeWeekly: safeWeekly,
    requiredWeekly: required,
    projectedTotal: projected,
    coverage: coverage,
    alternatives: alternatives,
  );
}

/// The verdict string as the API spells it, so the two stay comparable in tests.
String verdictKey(GoalVerdict v) => switch (v) {
      GoalVerdict.feasible => 'feasible',
      GoalVerdict.tight => 'tight',
      GoalVerdict.notFeasible => 'not_feasible',
    };
