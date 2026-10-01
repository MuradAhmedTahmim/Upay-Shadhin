// Tests for the Flutter client.
//
// The Bangla numeral helpers are tested directly because they are duplicated logic:
// the same formatting exists in nlg/narrator.py on the server, and the two must agree
// or the app and the API will show the same amount differently.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadhin_app/api.dart';
import 'package:shadhin_app/theme.dart';

void main() {
  group('bnNum', () {
    test('converts digits to Bangla numerals', () {
      expect(bnNum(0), '০');
      expect(bnNum(7), '৭');
      expect(bnNum(1234567890), '১,২৩৪,৫৬৭,৮৯০');
    });

    test('inserts thousands separators', () {
      expect(bnNum(999), '৯৯৯');
      expect(bnNum(1000), '১,০০০');
      expect(bnNum(30000), '৩০,০০০');
      expect(bnNum(2850), '২,৮৫০');
    });

    test('rounds to the requested precision', () {
      expect(bnNum(2437.6), '২,৪৩৮');
      expect(bnNum(1.25, decimals: 1), '১.৩');
    });

    test('handles negative amounts', () {
      expect(bnNum(-1500), '-১,৫০০');
    });
  });

  group('bnDate', () {
    test('formats an ISO date in Bangla', () {
      expect(bnDate('2026-09-24'), '২৪ সেপ্টেম্বর');
      expect(bnDate('2026-01-01'), '১ জানুয়ারি');
    });

    test('passes through anything it cannot parse', () {
      expect(bnDate('not-a-date'), 'not-a-date');
      expect(bnDate(''), '');
    });
  });

  testWidgets('StatusNote renders its message and icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(
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

    expect(find.text('কেন এই হিসাব?'), findsOneWidget);
    expect(find.text('সবচেয়ে চাপের দিন'), findsNothing);

    await tester.tap(find.text('কেন এই হিসাব?'));
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
