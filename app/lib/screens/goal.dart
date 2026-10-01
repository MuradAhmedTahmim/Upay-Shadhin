/// Goal - turn a target into an honest verdict.
///
/// The screen is built around refusing to flatter. It leads with the safe-to-save
/// amount the forecast supports, and when a goal does not fit it says so and offers
/// the trade-offs rather than nudging the customer to "try harder".
///
/// The verdict is computed in the app (`goal_math.dart`), not fetched, so the sliders
/// respond immediately and the screen works with no backend. That arithmetic is a port
/// of `rules/optimizer.py` and is cross-tested against it.
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../goal_math.dart';
import '../i18n.dart';
import '../theme.dart';

class GoalScreen extends StatefulWidget {
  const GoalScreen({
    super.key,
    required this.client,
    required this.userId,
    required this.safeToSave,
    required this.monthlyAvoidableFees,
    required this.asOf,
  });

  final ApiClient client;
  final String userId;
  final Map<String, dynamic> safeToSave;

  /// Cash-out fees the customer could plausibly stop paying, per month. Feeds the
  /// "redirect your fees" trade-off.
  final double monthlyAvoidableFees;
  final DateTime asOf;

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  double _amount = 30000;
  double _months = 6;
  bool _confirmed = false;

  GoalPlan get _plan => planGoal(
        goalAmount: _amount,
        deadlineDays: (_months * 30).round(),
        safeWeekly: (widget.safeToSave['weekly_amount'] as num).toDouble(),
        asOf: widget.asOf,
        monthlyAvoidableFees: widget.monthlyAvoidableFees,
      );

  @override
  Widget build(BuildContext context) {
    final sts = widget.safeToSave;
    final weekly = (sts['weekly_amount'] as num).toDouble();
    final plan = _plan;

    final (Color vc, Color vbg, String vlabel, IconData vicon) = switch (plan.verdict) {
      GoalVerdict.feasible =>
        (C.safe, C.safeBg, T.feasible, Icons.check_circle_outline),
      GoalVerdict.tight => (C.warn, C.warnBg, T.tight, Icons.error_outline),
      GoalVerdict.notFeasible =>
        (C.risk, C.riskBg, T.notFeasible, Icons.cancel_outlined),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Panel(
          title: T.safeToSaveTitle,
          subtitle: T.safeToSaveSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money(weekly),
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 6),
                    child: Text(T.perWeek,
                        style: TextStyle(fontSize: 15, color: C.muted)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(narrative(sts['narrative'] as Map?),
                  style: const TextStyle(fontSize: 14.5, height: 1.6)),
              const Divider(height: 28),
              WhyBlock(reasons: (sts['reasons'] as List?) ?? const []),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: T.yourGoal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SliderRow(
                label: T.howMuch,
                value: money(_amount),
                slider: Slider(
                  value: _amount,
                  min: 5000,
                  max: 200000,
                  divisions: 39,
                  onChanged: (v) => setState(() {
                    _amount = v;
                    _confirmed = false;
                  }),
                ),
              ),
              _SliderRow(
                label: T.howLong,
                value: T.monthsLabel(num_(_months)),
                slider: Slider(
                  value: _months,
                  min: 1,
                  max: 36,
                  divisions: 35,
                  onChanged: (v) => setState(() {
                    _months = v;
                    _confirmed = false;
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: T.result,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: vbg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: vc.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(vicon, size: 15, color: vc),
              const SizedBox(width: 5),
              Text(vlabel,
                  style: TextStyle(
                      fontSize: 12.5, color: vc, fontWeight: FontWeight.w700)),
            ]),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(T.goalVerdict(plan),
                  style: const TextStyle(fontSize: 14.5, height: 1.6)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _MiniStat(
                      label: T.neededPerWeek, value: money(plan.requiredWeekly)),
                ),
                Expanded(
                  child: _MiniStat(
                      label: T.safelyAvailable, value: money(plan.safeWeekly)),
                ),
                Expanded(
                  child: _MiniStat(
                      label: T.willAccumulate, value: money(plan.projectedTotal)),
                ),
              ]),
              if (plan.alternatives.isNotEmpty) ...[
                const Divider(height: 28),
                Text(T.alternatives,
                    style:
                        const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                for (final a in plan.alternatives) _Alternative(alt: a),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Human oversight: the plan is a proposal and does nothing until confirmed.
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(T.noAutoStart,
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(T.noAutoStartBody,
                  style: TextStyle(fontSize: 13.5, color: C.muted, height: 1.55)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: weekly <= 0
                      ? null
                      : () => setState(() => _confirmed = !_confirmed),
                  icon: Icon(_confirmed ? Icons.check : Icons.lock_outline),
                  label: Text(_confirmed ? T.planConfirmed : T.confirmPlan),
                  style: FilledButton.styleFrom(
                    backgroundColor: _confirmed ? C.safe : C.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow(
      {required this.label, required this.value, required this.slider});
  final String label;
  final String value;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 14, color: C.muted)),
            Text(value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        slider,
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: C.muted)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _Alternative extends StatelessWidget {
  const _Alternative({required this.alt});
  final GoalAlternative alt;

  String get _title => switch (alt.code) {
        'extend_deadline' => T.altExtend,
        'redirect_cash_out_fees' => T.altFees,
        _ => T.altOther,
      };

  String get _detail => switch (alt.code) {
        'extend_deadline' => T.altExtendBody(num_(alt.extraWeeks ?? 0)),
        'redirect_cash_out_fees' => T.altFeesBody(
            money(alt.extraWeekly ?? 0), money(alt.newProjectedTotal ?? 0)),
        _ => T.altOtherBody,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.alt_route, size: 18, color: C.brandDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(_detail,
                    style:
                        TextStyle(fontSize: 13.5, color: C.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
