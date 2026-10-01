/// Insights - where the money goes, and what the cash-out habit costs.
///
/// The leakage card is the one that earns its place: it converts a habit the customer
/// cannot see into a yearly taka figure, and it shows the evidence rather than asking
/// to be believed.
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key, required this.insights});

  final Map<String, dynamic> insights;

  @override
  Widget build(BuildContext context) {
    final cats = (insights['top_categories_30d'] as List).cast<Map<String, dynamic>>();
    final leak = insights['leakage'] as Map<String, dynamic>;
    final narrative = insights['narrative'] as Map<String, dynamic>;
    final total = cats.fold<double>(0, (a, c) => a + (c['amount'] as num).toDouble());
    final habits = (leak['habitual_amounts'] as List?) ?? const [];
    final avoidable = (leak['avoidable_fees_annualised'] as num).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Panel(
          title: 'ক্যাশ-আউটে বছরে কত যাচ্ছে',
          subtitle: 'গত ৯০ দিনের হিসাব থেকে বার্ষিক অনুমান',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('৳${bnNum((leak['fees_annualised'] as num).toDouble())}',
                  style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w800, height: 1.1, color: C.risk)),
              const SizedBox(height: 4),
              const Text('শুধু ফি বাবদ, প্রতি বছর',
                  style: TextStyle(fontSize: 13, color: C.muted)),
              const SizedBox(height: 14),
              if (avoidable > 0)
                StatusNote(
                  icon: Icons.savings_outlined,
                  color: C.safe,
                  background: C.safeBg,
                  text: 'এর মধ্যে আনুমানিক ৳${bnNum(avoidable)} এড়ানো সম্ভব।',
                ),
              const SizedBox(height: 14),
              Text(narrative['leakage']['bn'] as String,
                  style: const TextStyle(fontSize: 14.5, height: 1.6)),
              if (habits.isNotEmpty) ...[
                const Divider(height: 28),
                const Text('নিয়মিত অভ্যাস',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                for (final h in habits.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      const Icon(Icons.repeat, size: 17, color: C.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '৳${bnNum((h['amount'] as num).toDouble())} করে '
                          '${bnNum((h['times'] as num).toDouble())} বার তোলা হয়েছে',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text('৳${bnNum((h['total'] as num).toDouble())}',
                          style: const TextStyle(
                              fontSize: 13.5, color: C.muted, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ],
              const Divider(height: 28),
              WhyBlock(
                reasons: (leak['reasons'] as List?) ?? const [],
                title: 'এই হিসাব কীভাবে করা হলো?',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: 'গত ৩০ দিনের খরচ',
          subtitle: 'লেনদেনের ধরন স্বয়ংক্রিয়ভাবে শনাক্ত করা হয়েছে',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in cats.take(7))
                _CategoryBar(
                  label: c['category_bn'] as String? ?? c['category'] as String,
                  amount: (c['amount'] as num).toDouble(),
                  share: total > 0 ? (c['amount'] as num).toDouble() / total : 0,
                ),
              const SizedBox(height: 6),
              Text(narrative['spending']['bn'] as String,
                  style: const TextStyle(fontSize: 14.5, height: 1.6)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.label, required this.amount, required this.share});

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
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
              ),
              Text('৳${bnNum(amount)}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share.clamp(0, 1),
              minHeight: 7,
              backgroundColor: C.bg,
              valueColor: const AlwaysStoppedAnimation(C.brand),
            ),
          ),
        ],
      ),
    );
  }
}
