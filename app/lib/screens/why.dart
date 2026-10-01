/// "Why" - the transparency screen.
///
/// Judges and customers get the same page. It states which part of the answer was a
/// model prediction, which was a deterministic rule, and which was generated language -
/// the guideline asks for predictions, assumptions and generated explanations to be
/// clearly separated, and this is where that separation is made visible rather than
/// claimed in a slide.
library;

import 'package:flutter/material.dart';

import '../i18n.dart';
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
        StatusNote(
          icon: Icons.science_outlined,
          color: C.info,
          background: C.infoBg,
          text: T.syntheticNotice,
        ),
        const SizedBox(height: 14),
        Panel(
          title: T.howDecisionMade,
          child: Column(
            children: [
              _Layer(
                step: num_(1),
                title: T.step1,
                body: T.step1Body,
                color: C.brand,
                icon: Icons.insights_outlined,
              ),
              _Layer(
                step: num_(2),
                title: T.step2,
                body: T.step2Body,
                color: C.safe,
                icon: Icons.rule_outlined,
              ),
              _Layer(
                step: num_(3),
                title: T.step3,
                body: T.step3Body,
                color: C.warn,
                icon: Icons.translate_outlined,
              ),
              _Layer(
                step: num_(4),
                title: T.step4,
                body: T.step4Body,
                color: C.ink,
                icon: Icons.verified_user_outlined,
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: T.whyThisForecast,
          child: WhyBlock(
            reasons: (forecast['reasons'] as List?) ?? const [],
            title: T.seeDetails,
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: T.technical,
          child: Column(
            children: [
              _Row(label: T.asOfLabel, value: date_(profile['as_of'] as String)),
              _Row(label: T.customerId, value: profile['user_id'] as String),
              _Row(
                  label: T.forecastModel,
                  value: forecast['model_version'] as String? ?? '-'),
              _Row(
                  label: T.dataSource,
                  value: usingFixtures ? T.savedFixture : baseUrl),
              _Row(label: T.dataKind, value: T.synthetic),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          title: T.weNeverDo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Never(text: T.never1),
              _Never(text: T.never2),
              _Never(text: T.never3),
              _Never(text: T.never4),
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
              if (!last) Expanded(child: Container(width: 2, color: C.line)),
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
                      style:
                          TextStyle(fontSize: 13.5, color: C.muted, height: 1.6)),
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
            child:
                Text(label, style: TextStyle(fontSize: 13.5, color: C.muted)),
          ),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
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
          Icon(Icons.block, size: 17, color: C.risk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
