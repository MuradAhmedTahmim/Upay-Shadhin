/// Visual language for upay Shadhin.
///
/// Bangla-first and deliberately large-typed: the track asks for inclusive UX, and the
/// customers this is built for are often reading financial detail on a small phone in
/// bright light. Colour carries meaning (risk, safety, savings) but never carries it
/// alone - every coloured state is also labelled in words.
library;

import 'package:flutter/material.dart';

class C {
  static const brand = Color(0xFF00A1E0); // upay-like cyan
  static const brandDark = Color(0xFF0B6E99);
  static const ink = Color(0xFF14202B);
  static const muted = Color(0xFF5B6B7A);
  static const line = Color(0xFFE2E8EE);
  static const bg = Color(0xFFF5F8FA);
  static const surface = Colors.white;

  static const safe = Color(0xFF12855B);
  static const safeBg = Color(0xFFE6F5EE);
  static const risk = Color(0xFFC0392B);
  static const riskBg = Color(0xFFFDECEA);
  static const warn = Color(0xFFB7791F);
  static const warnBg = Color(0xFFFDF6E3);
  static const band = Color(0x3300A1E0);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.brand, primary: C.brand),
    scaffoldBackgroundColor: C.bg,
    fontFamily: 'NotoSansBengali',
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: C.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: C.line),
      ),
    ),
  );
}

/// A titled white card - the single layout primitive every screen is built from.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(subtitle!,
                                style: const TextStyle(
                                    fontSize: 13, color: C.muted)),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            if (title != null) const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// A coloured status strip. Always carries text, never colour alone.
class StatusNote extends StatelessWidget {
  const StatusNote({
    super.key,
    required this.text,
    required this.color,
    required this.background,
    this.icon,
  });

  final String text;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 14, height: 1.55, color: color, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// Expandable "why does it say that" block, used wherever a number is asserted.
class WhyBlock extends StatelessWidget {
  const WhyBlock({super.key, required this.reasons, this.title = 'কেন এই হিসাব?'});

  final List<dynamic> reasons;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (reasons.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.psychology_outlined, color: C.brandDark),
        title: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        children: [
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['detail'] ?? ''}',
                      style: const TextStyle(fontSize: 14, height: 1.5)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: C.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: C.line),
                    ),
                    child: Text(
                      '${r['code']}  •  ${r['evidence'] ?? {}}',
                      style: const TextStyle(
                          fontSize: 11.5, color: C.muted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
