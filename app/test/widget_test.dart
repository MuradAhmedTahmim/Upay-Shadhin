// Tests for the Flutter client.
//
// The number and date formatters are tested directly because the same formatting also
// exists in nlg/narrator.py on the server. If the two drift, the app and the API would
// render the same amount differently on the same screen.
//
// Every test that depends on language or theme restores the default afterwards, since
// both are global (see lib/settings.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadhin_app/i18n.dart';
import 'package:shadhin_app/settings.dart';
import 'package:shadhin_app/theme.dart';

void main() {
  tearDown(() {
    Settings.lang = Lang.bn;
    Settings.dark = false;
  });

  group('numbers in Bangla', () {
    setUp(() => Settings.lang = Lang.bn);

    test('converts digits to Bangla numerals', () {
      expect(num_(0), '০');
      expect(num_(7), '৭');
      expect(num_(1234567890), '১,২৩৪,৫৬৭,৮৯০');
    });

    test('inserts thousands separators', () {
      expect(num_(999), '৯৯৯');
      expect(num_(1000), '১,০০০');
      expect(num_(2850), '২,৮৫০');
    });

    test('rounds to the requested precision', () {
      expect(num_(2437.6), '২,৪৩৮');
      expect(num_(1.25, decimals: 1), '১.৩');
    });

    test('handles negative amounts', () => expect(num_(-1500), '-১,৫০০'));

    test('money carries the taka sign', () => expect(money(30000), '৳৩০,০০০'));
  });

  group('numbers in English', () {
    setUp(() => Settings.lang = Lang.en);

    test('keeps Western numerals', () {
      expect(num_(1234567890), '1,234,567,890');
      expect(num_(2850), '2,850');
    });

    test('money is labelled BDT, because the currency does not change', () {
      expect(money(30000), 'BDT 30,000');
    });
  });

  group('dates', () {
    test('formats in Bangla', () {
      Settings.lang = Lang.bn;
      expect(date_('2026-09-24'), '২৪ সেপ্টেম্বর');
      expect(date_('2026-01-01'), '১ জানুয়ারি');
    });

    test('formats in English', () {
      Settings.lang = Lang.en;
      expect(date_('2026-09-24'), '24 September');
    });

    test('passes through anything it cannot parse', () {
      expect(date_('not-a-date'), 'not-a-date');
      expect(date_(''), '');
    });
  });

  group('narrative selection', () {
    const both = {'bn': 'বাংলা বাক্য', 'en': 'English sentence'};

    test('picks the side matching the language', () {
      Settings.lang = Lang.bn;
      expect(narrative(both), 'বাংলা বাক্য');
      Settings.lang = Lang.en;
      expect(narrative(both), 'English sentence');
    });

    test('falls back rather than showing nothing', () {
      Settings.lang = Lang.en;
      expect(narrative({'bn': 'শুধু বাংলা'}), 'শুধু বাংলা');
      expect(narrative(null), '');
    });
  });

  group('strings switch with the language', () {
    test('nav labels', () {
      Settings.lang = Lang.bn;
      expect(T.navForecast, 'পূর্বাভাস');
      Settings.lang = Lang.en;
      expect(T.navForecast, 'Forecast');
    });

    test('category names fall back to the API Bangla label', () {
      Settings.lang = Lang.bn;
      expect(T.category('cash_out', 'ক্যাশ-আউট'), 'ক্যাশ-আউট');
      Settings.lang = Lang.en;
      expect(T.category('cash_out', 'ক্যাশ-আউট'), 'Cash-out');
      expect(T.category('unknown_kind', null), 'unknown_kind');
    });
  });

  group('theme', () {
    test('palette changes with the dark flag', () {
      Settings.dark = false;
      final lightBg = C.bg;
      Settings.dark = true;
      expect(C.bg, isNot(lightBg));
    });

    test('dark surfaces are darker than their text', () {
      Settings.dark = true;
      expect(C.bg.computeLuminance(), lessThan(C.ink.computeLuminance()));
    });

    test('light surfaces are lighter than their text', () {
      Settings.dark = false;
      expect(C.bg.computeLuminance(), greaterThan(C.ink.computeLuminance()));
    });

    test('text clears WCAG AA contrast on both surfaces', () {
      // Colour is never the only signal in this UI, but it still has to be readable
      // on a phone in daylight and on a projector. 4.5:1 is the AA threshold for
      // body text; muted secondary text is held to 3:1.
      double ratio(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final dark in [false, true]) {
        Settings.dark = dark;
        final where = dark ? 'dark' : 'light';
        expect(ratio(C.ink, C.bg), greaterThanOrEqualTo(4.5),
            reason: 'body text on background ($where)');
        expect(ratio(C.ink, C.surface), greaterThanOrEqualTo(4.5),
            reason: 'body text on cards ($where)');
        expect(ratio(C.muted, C.surface), greaterThanOrEqualTo(3.0),
            reason: 'secondary text on cards ($where)');
        expect(ratio(C.risk, C.riskBg), greaterThanOrEqualTo(4.5),
            reason: 'risk text on its tint ($where)');
        expect(ratio(C.safe, C.safeBg), greaterThanOrEqualTo(4.5),
            reason: 'safe text on its tint ($where)');
        expect(ratio(C.warn, C.warnBg), greaterThanOrEqualTo(4.5),
            reason: 'warning text on its tint ($where)');
      }
    });

    test('buildTheme reports the matching brightness', () {
      Settings.dark = true;
      expect(buildTheme().brightness, Brightness.dark);
      Settings.dark = false;
      expect(buildTheme().brightness, Brightness.light);
    });
  });

  testWidgets('StatusNote renders its message and icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: StatusNote(
            text: 'ব্যালেন্স নিরাপত্তা সীমার নিচে নামতে পারে',
            color: C.risk,
            background: C.riskBg,
            icon: Icons.warning_amber_rounded,
          ),
        ),
      ),
    );

    expect(find.text('ব্যালেন্স নিরাপত্তা সীমার নিচে নামতে পারে'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('WhyBlock stays collapsed until tapped, then shows the evidence',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(
          body: WhyBlock(reasons: [
            {
              'code': 'binding_day',
              'detail': 'সবচেয়ে চাপের দিন',
              'evidence': {'day': 21},
            }
          ]),
        ),
      ),
    );

    expect(find.text(T.whyThisNumber), findsOneWidget);
    expect(find.text('সবচেয়ে চাপের দিন'), findsNothing);

    await tester.tap(find.text(T.whyThisNumber));
    await tester.pumpAndSettle();

    expect(find.text('সবচেয়ে চাপের দিন'), findsOneWidget);
  });

  testWidgets('WhyBlock renders nothing when there are no reasons', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WhyBlock(reasons: []))),
    );
    expect(find.byType(ExpansionTile), findsNothing);
  });
}
