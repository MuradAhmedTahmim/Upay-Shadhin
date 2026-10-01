/// Visual language for upay Shadhin, in light and dark.
///
/// Bangla-first and deliberately large-typed: the track asks for inclusive UX, and the
/// customers this is built for are often reading financial detail on a small phone in
/// bright light. Colour carries meaning (risk, safety, savings) but never carries it
/// alone - every coloured state is also labelled in words, so the app still works for a
/// colour-blind reader and in a washed-out projector image.
///
/// `C` resolves each colour against `Settings.dark` at build time. The root widget
/// rebuilds the whole tree when the toggle flips, so every lookup matches what is on
/// screen. See settings.dart for why this is global rather than inherited.
library;

import 'package:flutter/material.dart';

import 'i18n.dart';
import 'settings.dart';

class _Palette {
  const _Palette({
    required this.brand,
    required this.brandDark,
    required this.ink,
    required this.muted,
    required this.line,
    required this.bg,
    required this.surface,
    required this.safe,
    required this.safeBg,
    required this.risk,
    required this.riskBg,
    required this.warn,
    required this.warnBg,
    required this.band,
    required this.info,
    required this.infoBg,
  });

  final Color brand, brandDark, ink, muted, line, bg, surface;
  final Color safe, safeBg, risk, riskBg, warn, warnBg, band, info, infoBg;
}

const _light = _Palette(
  brand: Color(0xFF00A1E0),
  brandDark: Color(0xFF0B6E99),
  ink: Color(0xFF14202B),
  muted: Color(0xFF5B6B7A),
  line: Color(0xFFE2E8EE),
  bg: Color(0xFFF5F8FA),
  surface: Colors.white,
  safe: Color(0xFF0E6B49),
  safeBg: Color(0xFFE6F5EE),
  risk: Color(0xFFC0392B),
  riskBg: Color(0xFFFDECEA),
  warn: Color(0xFF8A5600),
  warnBg: Color(0xFFFDF6E3),
  band: Color(0x3300A1E0),
  info: Color(0xFF0B6E99),
  infoBg: Color(0xFFE8F6FD),
);

// Dark is not the light palette inverted. Saturated accents vibrate on a dark
// background, so each one is lightened and desaturated until it reads calmly, and the
// tinted status backgrounds become low-alpha washes rather than pale pastels.
const _dark = _Palette(
  brand: Color(0xFF4CC2F1),
  brandDark: Color(0xFF8AD6F7),
  ink: Color(0xFFE8EEF3),
  muted: Color(0xFF93A6B5),
  line: Color(0xFF263340),
  bg: Color(0xFF0E1620),
  surface: Color(0xFF16202B),
  safe: Color(0xFF4FC58D),
  safeBg: Color(0xFF143024),
  risk: Color(0xFFF07167),
  riskBg: Color(0xFF3A1F1C),
  warn: Color(0xFFE3B261),
  warnBg: Color(0xFF332817),
  band: Color(0x384CC2F1),
  info: Color(0xFF8AD6F7),
  infoBg: Color(0xFF13293A),
);

/// Semantic colours. Resolved against the current theme on every access.
class C {
  C._();

  static _Palette get _p => Settings.dark ? _dark : _light;

  static Color get brand => _p.brand;
  static Color get brandDark => _p.brandDark;
  static Color get ink => _p.ink;
  static Color get muted => _p.muted;
  static Color get line => _p.line;
  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get safe => _p.safe;
  static Color get safeBg => _p.safeBg;
  static Color get risk => _p.risk;
  static Color get riskBg => _p.riskBg;
  static Color get warn => _p.warn;
  static Color get warnBg => _p.warnBg;
  static Color get band => _p.band;
  static Color get info => _p.info;
  static Color get infoBg => _p.infoBg;
}

ThemeData buildTheme() {
  final dark = Settings.dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.brand,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(primary: C.brand, surface: C.surface),
    scaffoldBackgroundColor: C.bg,
    fontFamily: 'NotoSansBengali',
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    cardTheme: CardThemeData(
      elevation: 0,
      color: C.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: C.line),
      ),
    ),
  );
}

/// A titled card - the single layout primitive every screen is built from.
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
                                style: TextStyle(fontSize: 13, color: C.muted)),
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
                    fontSize: 14,
                    height: 1.55,
                    color: color,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// Expandable "why does it say that" block, used wherever a number is asserted.
class WhyBlock extends StatelessWidget {
  const WhyBlock({super.key, required this.reasons, this.title});

  final List<dynamic> reasons;
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (reasons.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: Icon(Icons.psychology_outlined, color: C.brandDark),
        title: Text(title ?? T.whyThisNumber,
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
                      style: TextStyle(fontSize: 11.5, color: C.muted, height: 1.4),
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
