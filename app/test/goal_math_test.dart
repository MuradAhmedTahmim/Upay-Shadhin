// Cross-checks the Dart port of the goal optimiser against the Python original.
//
// `deploy/precompute.py` records what `rules/optimizer.py` returned for a set of goal
// cases inside every demo bundle. These tests replay those cases through the Dart port
// and assert the numbers match. If the Python rule changes and the port does not, this
// fails - which is the whole reason the recorded cases are shipped.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadhin_app/goal_math.dart';

List<File> demoBundles() {
  final dir = Directory('assets/demo');
  if (!dir.existsSync()) return const [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json') && !f.path.endsWith('manifest.json'))
      .toList();
}

void main() {
  final bundles = demoBundles();

  test('demo bundles exist (run: python -m deploy.precompute)', () {
    expect(bundles, isNotEmpty);
  });

  group('matches rules/optimizer.py', () {
    for (final file in bundles) {
      final bundle = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final uid = (bundle['profile'] as Map)['user_id'] as String;
      final asOf = DateTime.parse((bundle['profile'] as Map)['as_of'] as String);
      final safeWeekly =
          ((bundle['safe_to_save'] as Map)['weekly_amount'] as num).toDouble();
      final avoidableAnnual = (((bundle['insights'] as Map)['leakage']
          as Map)['avoidable_fees_annualised'] as num).toDouble();
      final monthlyFees = avoidableAnnual / 12.0;

      for (final c in (bundle['goal_cases'] as List).cast<Map<String, dynamic>>()) {
        final amount = (c['goal_amount'] as num).toDouble();
        final days = c['deadline_days'] as int;
        final expected = c['expected'] as Map<String, dynamic>;

        test('$uid — ${amount.toStringAsFixed(0)} in $days days', () {
          final plan = planGoal(
            goalAmount: amount,
            deadlineDays: days,
            safeWeekly: safeWeekly,
            asOf: asOf,
            monthlyAvoidableFees: monthlyFees,
          );

          expect(verdictKey(plan.verdict), expected['verdict'],
              reason: 'verdict for $uid');
          expect(plan.requiredWeekly,
              closeTo((expected['required_weekly'] as num).toDouble(), 0.01),
              reason: 'required weekly');
          expect(plan.projectedTotal,
              closeTo((expected['projected_total'] as num).toDouble(), 0.01),
              reason: 'projected total');
          expect(plan.coverage,
              closeTo((expected['coverage'] as num).toDouble(), 0.0001),
              reason: 'coverage');

          // The same trade-offs, in the same order.
          final expectedCodes = (expected['alternatives'] as List)
              .map((a) => (a as Map)['code'] as String)
              .toList();
          expect(plan.alternatives.map((a) => a.code).toList(), expectedCodes,
              reason: 'alternative codes');

          for (var i = 0; i < expectedCodes.length; i++) {
            final got = plan.alternatives[i];
            final want = (expected['alternatives'] as List)[i] as Map;
            switch (got.code) {
              case 'extend_deadline':
                expect(got.extraWeeks, want['extra_weeks']);
                expect(got.newDeadlineDays, want['new_deadline_days']);
                expect(got.newDeadlineDate!.toIso8601String().split('T').first,
                    want['new_deadline_date'],
                    reason: 'extended deadline date');
              case 'redirect_cash_out_fees':
                expect(got.extraWeekly!,
                    closeTo((want['extra_weekly'] as num).toDouble(), 0.01));
                expect(got.newProjectedTotal!,
                    closeTo((want['new_projected_total'] as num).toDouble(), 0.01));
                expect(got.closesGap, want['closes_gap']);
            }
          }
        });
      }
    }
  });

  group('properties the rule must hold', () {
    final asOf = DateTime(2026, 8, 31);

    test('a goal within capacity is achievable', () {
      final p = planGoal(
          goalAmount: 20000, deadlineDays: 180, safeWeekly: 1000, asOf: asOf);
      expect(p.verdict, GoalVerdict.feasible);
      expect(p.projectedTotal, greaterThanOrEqualTo(p.goalAmount));
    });

    test('an impossible goal is refused, and offers a longer deadline', () {
      final p = planGoal(
          goalAmount: 30000, deadlineDays: 180, safeWeekly: 500, asOf: asOf);
      expect(p.verdict, GoalVerdict.notFeasible);
      final ext = p.alternatives.firstWhere((a) => a.code == 'extend_deadline');
      expect(ext.newDeadlineDays, greaterThan(p.deadlineDays));
    });

    test('no capacity means no plan, and says why', () {
      final p =
          planGoal(goalAmount: 30000, deadlineDays: 180, safeWeekly: 0, asOf: asOf);
      expect(p.verdict, GoalVerdict.notFeasible);
      expect(p.alternatives.map((a) => a.code),
          contains('lower_floor_or_reduce_outflow'));
    });

    test('the verdict follows coverage, not encouragement', () {
      final p =
          planGoal(goalAmount: 10000, deadlineDays: 70, safeWeekly: 950, asOf: asOf);
      expect(p.coverage, lessThan(1.0));
      expect(p.verdict, isNot(GoalVerdict.feasible));
    });

    test('a deadline under a week still counts as one saving week', () {
      final p =
          planGoal(goalAmount: 1000, deadlineDays: 3, safeWeekly: 500, asOf: asOf);
      expect(p.weeks, 1);
      expect(p.projectedTotal, 500);
    });
  });
}
