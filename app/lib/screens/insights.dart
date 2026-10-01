/// Insights - where the money goes, and what the cash-out habit costs.
///
/// The leakage card is the one that earns its place: it converts a habit the customer
/// cannot see into a yearly taka figure, and it shows the evidence rather than asking
/// to be believed.
library;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key, required this.insights});

  final Map<String, dynamic> insights;

  @override
  Widget build(BuildContext context) {
    final cats =
        (insights['top_categories_30d'] as List).cast<Map<String, dynamic>>();
    final leak = insights['leakage'] as Map<String, dynamic>;
    final narr = insights['narrative'] as Map<String, dynamic>;
    final total = cats.fold<double>(0, (a, c) => a + (c['amount'] as num).toDouble());
    final habits = (leak['habitual_amounts'] as List?) ?? const [];
    final avoidable = (leak['avoidable_fees_annualised'] as num).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Panel(
          title: T.leakageTitle,
          subtitle: T.leakageSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(money((leak['fees_annualised'] as num).toDouble()),
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: C.risk)),
              const SizedBox(height: 4),
              Text(T.feesOnly, style: TextStyle(fontSize: 13, color: C.muted)),
              const SizedBox(height: 14),
              if (avoidable > 0)
                StatusNote(
                  icon: Icons.savings_outlined,
                  color: C.safe,
                  background: C.safeBg,
                  text: T.avoidableNote(money(avoidable)),
                ),
              const SizedBox(height: 14),
              Text(narrative(narr['leakage'] as Map?),
                  style: const TextStyle(fontSize: 14.5, height: 1.6)),
              if (habits.isNotEmpty) ...[
                const Divider(height: 28),
                Text(T.habitsTitle,
                    style:
                        const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                for (final h in habits.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(Icons.repeat, size: 17, color: C.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          T.habitLine(
                            money((h['amount'] as num).toDouble()),
                            num_((h['times'] as num).toDouble()),
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(money((h['total'] as num).toDouble()),
                          style: TextStyle(
                              fontSize: 13.5,
                              color: C.muted,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ],
              const Divider(height: 28),
              WhyBlock(
                reasons: (leak['reasons'] as List?) ?? const [],
                title: T.howComputed,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: T.spendingTitle,
          subtitle: T.spendingSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in cats.take(7))
                _CategoryBar(
                  label: T.category(
                      c['category'] as String, c['category_bn'] as String?),
                  amount: (c['amount'] as num).toDouble(),
                  share: total > 0 ? (c['amount'] as num).toDouble() / total : 0,
                ),
              const SizedBox(height: 6),
              Text(narrative(narr['spending'] as Map?),
                  style: const TextStyle(fontSize: 14.5, height: 1.6)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar(
      {required this.label, required this.amount, required this.share});

  final String label;
  final double amount;
  final double share;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w500)),
              ),
              Text(money(amount),
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share.clamp(0, 1),
              minHeight: 7,
              backgroundColor: C.bg,
              valueColor: AlwaysStoppedAnimation(C.brand),
            ),
          ),
        ],
      ),
    );
  }
}
