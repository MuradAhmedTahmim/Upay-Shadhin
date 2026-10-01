/// "Why" - the transparency screen.
///
/// Judges and customers get the same page. It states which part of the answer was a
/// model prediction, which was a deterministic rule, and which was generated language -
/// the guideline asks for predictions, assumptions and generated explanations to be
/// clearly separated, and this is where that separation is made visible rather than
/// claimed in a slide.
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class WhyScreen extends StatelessWidget {
  const WhyScreen({
    super.key,
    required this.profile,
    required this.forecast,
    required this.usingFixtures,
    required this.baseUrl,
  });

  final Map<String, dynamic> profile;
  final Map<String, dynamic> forecast;
  final bool usingFixtures;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const StatusNote(
          icon: Icons.science_outlined,
          color: C.brandDark,
          background: Color(0xFFE8F6FD),
          text: 'এই অ্যাপের সব তথ্য সিন্থেটিক (কৃত্রিমভাবে তৈরি)। কোনো প্রকৃত '
              'গ্রাহকের ডেটা ব্যবহার করা হয়নি।',
        ),
        const SizedBox(height: 14),
        Panel(
          title: 'সিদ্ধান্তটি কীভাবে তৈরি হলো',
          child: Column(
            children: const [
              _Layer(
                step: '১',
                title: 'পূর্বাভাস — মেশিন লার্নিং',
                body: 'আপনার নিজের লেনদেনের ইতিহাস থেকে আগামী ৩০ দিনের নগদ '
                    'প্রবাহ অনুমান করা হয় (P10/P50/P90)। এটি একটি পরিসংখ্যানগত '
                    'অনুমান, নিশ্চয়তা নয়।',
                color: C.brand,
                icon: Icons.insights_outlined,
              ),
              _Layer(
                step: '২',
                title: 'সিদ্ধান্ত — নির্দিষ্ট নিয়ম',
                body: 'কত টাকা নিরাপদে জমানো যায় তা ঠিক করে একটি সাধারণ, '
                    'যাচাইযোগ্য নিয়ম — কোনো মডেল নয়। সবচেয়ে সতর্ক অনুমান (P10) '
                    'ব্যবহার করা হয়, যাতে খারাপ মাসেও সমস্যা না হয়।',
                color: C.safe,
                icon: Icons.rule_outlined,
              ),
              _Layer(
                step: '৩',
                title: 'ব্যাখ্যা — ভাষা',
                body: 'উপরের সংখ্যাগুলোকে সহজ বাংলায় লেখা হয়। ভাষার অংশটি কোনো '
                    'সিদ্ধান্ত নেয় না এবং কোনো সংখ্যা বদলাতে পারে না।',
                color: C.warn,
                icon: Icons.translate_outlined,
              ),
              _Layer(
                step: '৪',
                title: 'অনুমোদন — আপনি',
                body: 'কোনো টাকা স্বয়ংক্রিয়ভাবে সরানো হয় না। প্রতিটি পরিকল্পনা '
                    'আপনার নিশ্চিতকরণের অপেক্ষায় থাকে।',
                color: C.ink,
                icon: Icons.verified_user_outlined,
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: 'এই পূর্বাভাসের কারণ',
          child: WhyBlock(
            reasons: (forecast['reasons'] as List?) ?? const [],
            title: 'বিস্তারিত দেখুন',
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: 'কারিগরি তথ্য',
          child: Column(
            children: [
              _Row(label: 'হিসাবের তারিখ', value: bnDate(profile['as_of'] as String)),
              _Row(label: 'গ্রাহক আইডি', value: profile['user_id'] as String),
              _Row(
                  label: 'পূর্বাভাস মডেল',
                  value: forecast['model_version'] as String? ?? '-'),
              _Row(
                  label: 'ডেটা উৎস',
                  value: usingFixtures ? 'সংরক্ষিত ফিক্সচার (অফলাইন)' : baseUrl),
              const _Row(label: 'ডেটার ধরন', value: 'সিন্থেটিক'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: 'আমরা যা করি না',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Never(text: 'আপনার অনুমতি ছাড়া টাকা সরাই না'),
              _Never(text: 'ঋণ অনুমোদন বা বাতিল করি না'),
              _Never(text: 'অপ্রয়োজনীয় খরচে উৎসাহ দিই না'),
              _Never(text: 'লুকানো ফি বা শর্ত রাখি না'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Layer extends StatelessWidget {
  const _Layer({
    required this.step,
    required this.title,
    required this.body,
    required this.color,
    required this.icon,
    this.last = false,
  });

  final String step;
  final String title;
  final String body;
  final Color color;
  final IconData icon;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: C.line),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$step. $title',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 13.5, color: C.muted, height: 1.6)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontSize: 13.5, color: C.muted)),
          ),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Never extends StatelessWidget {
  const _Never({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block, size: 17, color: C.risk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
