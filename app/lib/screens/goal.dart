/// Goal - turn a target into an honest verdict.
///
/// The screen is built around refusing to flatter. It leads with the safe-to-save
/// amount the forecast supports, and when a goal does not fit it says so and offers
/// the trade-offs rather than nudging the customer to "try harder".
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class GoalScreen extends StatefulWidget {
  const GoalScreen({
    super.key,
    required this.client,
    required this.userId,
    required this.safeToSave,
    required this.initialGoal,
  });

  final ApiClient client;
  final String userId;
  final Map<String, dynamic> safeToSave;
  final Map<String, dynamic> initialGoal;

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  late Map<String, dynamic> _goal = widget.initialGoal;
  double _amount = 30000;
  double _months = 6;
  bool _busy = false;
  bool _confirmed = false;

  Future<void> _recalculate() async {
    setState(() => _busy = true);
    final g = await widget.client
        .simulateGoal(widget.userId, _amount, (_months * 30).round());
    if (!mounted) return;
    setState(() {
      _goal = g;
      _busy = false;
      _confirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sts = widget.safeToSave;
    final weekly = (sts['weekly_amount'] as num).toDouble();
    final verdict = _goal['verdict'] as String? ?? 'not_feasible';
    final narrative = (_goal['narrative'] as Map?)?['bn'] as String? ?? '';
    final alternatives = (_goal['alternatives'] as List?) ?? const [];
    final stale = _goal['_fixture'] == true;

    final (Color vc, Color vbg, String vlabel, IconData vicon) = switch (verdict) {
      'feasible' => (C.safe, C.safeBg, 'সম্ভব', Icons.check_circle_outline),
      'tight' => (C.warn, C.warnBg, 'টানটান', Icons.error_outline),
      _ => (C.risk, C.riskBg, 'এখন সম্ভব নয়', Icons.cancel_outlined),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Panel(
          title: 'আপনি নিরাপদে কত জমাতে পারেন',
          subtitle: 'পূর্বাভাসের সবচেয়ে সতর্ক হিসাব (P10) থেকে',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('৳${bnNum(weekly)}',
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6, left: 6),
                    child: Text('/ সপ্তাহ',
                        style: TextStyle(fontSize: 15, color: C.muted)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text((sts['narrative'] as Map)['bn'] as String,
                  style: const TextStyle(fontSize: 14.5, height: 1.6)),
              const Divider(height: 28),
              WhyBlock(reasons: (sts['reasons'] as List?) ?? const []),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: 'আপনার লক্ষ্য',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SliderRow(
                label: 'কত টাকা',
                value: '৳${bnNum(_amount)}',
                slider: Slider(
                  value: _amount,
                  min: 5000,
                  max: 200000,
                  divisions: 39,
                  onChanged: (v) => setState(() => _amount = v),
                  onChangeEnd: (_) => _recalculate(),
                ),
              ),
              _SliderRow(
                label: 'কত সময়ে',
                value: '${bnNum(_months)} মাস',
                slider: Slider(
                  value: _months,
                  min: 1,
                  max: 36,
                  divisions: 35,
                  onChanged: (v) => setState(() => _months = v),
                  onChangeEnd: (_) => _recalculate(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (stale)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: StatusNote(
              icon: Icons.cloud_off,
              color: C.warn,
              background: C.warnBg,
              text: 'সার্ভার বন্ধ — নিচের ফলাফলটি সংরক্ষিত উদাহরণ '
                  '(৳৩০,০০০ / ৬ মাস), আপনার স্লাইডারের মান নয়।',
            ),
          ),
        Panel(
          title: 'ফলাফল',
          trailing: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              Text(narrative, style: const TextStyle(fontSize: 14.5, height: 1.6)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _MiniStat(
                    label: 'দরকার / সপ্তাহ',
                    value: '৳${bnNum((_goal['required_weekly'] as num).toDouble())}',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'নিরাপদে সম্ভব',
                    value: '৳${bnNum((_goal['safe_weekly'] as num).toDouble())}',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'জমবে',
                    value: '৳${bnNum((_goal['projected_total'] as num).toDouble())}',
                  ),
                ),
              ]),
              if (alternatives.isNotEmpty) ...[
                const Divider(height: 28),
                const Text('বিকল্প পথ',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                for (final a in alternatives) _Alternative(data: a as Map<String, dynamic>),
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
              const Text('এই পরিকল্পনা স্বয়ংক্রিয়ভাবে চালু হবে না',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'আপনার অনুমতি ছাড়া কোনো টাকা সরানো হবে না। আপনি যেকোনো সময় '
                'পরিমাণ বদলাতে বা বন্ধ করতে পারবেন।',
                style: TextStyle(fontSize: 13.5, color: C.muted, height: 1.55),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: weekly <= 0
                      ? null
                      : () => setState(() => _confirmed = !_confirmed),
                  icon: Icon(_confirmed ? Icons.check : Icons.lock_outline),
                  label: Text(_confirmed
                      ? 'পরিকল্পনা নিশ্চিত করা হয়েছে (ডেমো)'
                      : 'আমি রাজি — সাপ্তাহিক সঞ্চয় চালু করুন'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _confirmed ? C.safe : C.brand,
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
  const _SliderRow({required this.label, required this.value, required this.slider});
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
            Text(label, style: const TextStyle(fontSize: 14, color: C.muted)),
            Text(value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
        Text(label, style: const TextStyle(fontSize: 12, color: C.muted)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _Alternative extends StatelessWidget {
  const _Alternative({required this.data});
  final Map<String, dynamic> data;

  String get _title => switch (data['code']) {
        'extend_deadline' => 'সময় বাড়ান',
        'redirect_cash_out_fees' => 'ক্যাশ-আউট ফি বাঁচিয়ে যোগ করুন',
        _ => 'খরচ কমান বা সীমা পুনর্বিবেচনা করুন',
      };

  String get _detail {
    switch (data['code']) {
      case 'extend_deadline':
        return 'একই সাপ্তাহিক পরিমাণ রেখে লক্ষ্যের তারিখ '
            '${bnNum((data['extra_weeks'] as num).toDouble())} সপ্তাহ পেছালে '
            'লক্ষ্যে পৌঁছানো যাবে।';
      case 'redirect_cash_out_fees':
        return 'ক্যাশ-আউটের বদলে ডিজিটাল পেমেন্ট করলে সপ্তাহে প্রায় '
            '৳${bnNum((data['extra_weekly'] as num).toDouble())} বাঁচে, '
            'যা যোগ করলে মোট দাঁড়ায় '
            '৳${bnNum((data['new_projected_total'] as num).toDouble())}।';
      default:
        return '${data['detail'] ?? ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
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
                    style: const TextStyle(
                        fontSize: 13.5, color: C.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
