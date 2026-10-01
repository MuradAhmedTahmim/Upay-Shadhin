/// Bangla / English string table and locale-aware number and date formatting.
///
/// Bangla is the primary language - the track asks for inclusive, Bangla-friendly UX -
/// and English is offered because a judging panel or an upay reviewer may not read
/// Bangla. The API already returns every generated explanation as `{"bn": ..., "en": ...}`,
/// so switching language changes the narrative text too, not just the chrome.
///
/// Numerals follow the language: ১২,৩৫০ in Bangla, 12,350 in English. Amounts stay in
/// taka either way, because the currency does not change with the reader.
library;

import 'goal_math.dart';
import 'settings.dart';

const String _western = '0123456789';
const String _bengali = '০১২৩৪৫৬৭৮৯';

const Map<int, String> _monthsBn = {
  1: 'জানুয়ারি', 2: 'ফেব্রুয়ারি', 3: 'মার্চ', 4: 'এপ্রিল',
  5: 'মে', 6: 'জুন', 7: 'জুলাই', 8: 'আগস্ট',
  9: 'সেপ্টেম্বর', 10: 'অক্টোবর', 11: 'নভেম্বর', 12: 'ডিসেম্বর',
};

const Map<int, String> _monthsEn = {
  1: 'January', 2: 'February', 3: 'March', 4: 'April',
  5: 'May', 6: 'June', 7: 'July', 8: 'August',
  9: 'September', 10: 'October', 11: 'November', 12: 'December',
};

String _grouped(num value, int decimals) => value
    .toStringAsFixed(decimals)
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

String toBengaliDigits(String s) {
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final i = _western.indexOf(ch);
    buf.write(i >= 0 ? _bengali[i] : ch);
  }
  return buf.toString();
}

/// A number in the current language's numerals.
String num_(num value, {int decimals = 0}) {
  final s = _grouped(value, decimals);
  return Settings.isBn ? toBengaliDigits(s) : s;
}

/// A taka amount, e.g. `৳১২,৩৫০` or `BDT 12,350`.
String money(num value, {int decimals = 0}) =>
    Settings.isBn ? '৳${num_(value, decimals: decimals)}' : 'BDT ${num_(value, decimals: decimals)}';

/// An ISO date in the current language, e.g. `২৪ সেপ্টেম্বর` or `24 September`.
String date_(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (m == null || d == null) return iso;
  return Settings.isBn
      ? '${num_(d)} ${_monthsBn[m] ?? ''}'.trim()
      : '$d ${_monthsEn[m] ?? ''}'.trim();
}

/// Pick the right side of a `{"bn": ..., "en": ...}` object from the API.
String narrative(Map? m) {
  if (m == null) return '';
  final v = m[Settings.narrativeKey] ?? m['bn'] ?? m['en'];
  return v is String ? v : '';
}

String _p(String bn, String en) => Settings.isBn ? bn : en;

/// The string table. Accessed as `T.something` so a missing key is a compile error.
class T {
  T._();

  // --- chrome -------------------------------------------------------------
  static String get appName => _p('উপায় স্বাধীন', 'upay Shadhin');
  static String get navForecast => _p('পূর্বাভাস', 'Forecast');
  static String get navSpending => _p('খরচ', 'Spending');
  static String get navGoal => _p('লক্ষ্য', 'Goal');
  static String get navWhy => _p('কেন', 'Why');
  static String get refresh => _p('রিফ্রেশ', 'Refresh');
  static String get switchCustomer => _p('গ্রাহক বদলান', 'Switch customer');
  static String get toggleTheme => _p('ডার্ক / লাইট মোড', 'Dark / light mode');
  static String get toggleLanguage => _p('Switch to English', 'বাংলায় দেখুন');
  static String get precomputedBanner => _p(
      'ডেমো মোড — সব সংখ্যা আসল মডেলের আউটপুট, আগেই হিসাব করা (৩১ আগস্ট ২০২৬)',
      'Demo mode - every figure is real model output, precomputed (31 Aug 2026)');
  static String get loadFailed => _p('ডেটা লোড করা যায়নি', 'Could not load data');
  static String get retry => _p('আবার চেষ্টা করুন', 'Try again');

  // --- home ---------------------------------------------------------------
  static String get currentBalance => _p('বর্তমান ব্যালেন্স', 'Current balance');
  static String floorAndAsOf(String floor, String asOf) => _p(
      'নিরাপত্তা সীমা $floor  •  $asOf পর্যন্ত হিসাব',
      'Safety floor $floor  •  as of $asOf');
  static String get forecastTitle =>
      _p('আগামী ৩০ দিনের পূর্বাভাস', 'The next 30 days');
  static String get forecastSubtitle => _p(
      'ছায়া অংশ = সম্ভাব্য সীমা (P10–P90)', 'Shaded area = likely range (P10–P90)');
  static String get legendExpected => _p('সম্ভাব্য ব্যালেন্স', 'Expected balance');
  static String get legendBand => _p('অনিশ্চয়তার সীমা', 'Uncertainty range');
  static String get legendFloor => _p('নিরাপত্তা সীমা', 'Safety floor');
  static String get last30 => _p('গত ৩০ দিনে', 'Last 30 days');
  static String get totalIn => _p('মোট আয়', 'Money in');
  static String get totalOut => _p('মোট খরচ', 'Money out');

  // --- insights -----------------------------------------------------------
  static String get leakageTitle =>
      _p('ক্যাশ-আউটে বছরে কত যাচ্ছে', 'What cash-outs cost you a year');
  static String get leakageSubtitle => _p(
      'গত ৯০ দিনের হিসাব থেকে বার্ষিক অনুমান',
      'Annualised from the last 90 days');
  static String get feesOnly => _p('শুধু ফি বাবদ, প্রতি বছর', 'In fees alone, per year');
  static String avoidableNote(String amount) => _p(
      'এর মধ্যে আনুমানিক $amount এড়ানো সম্ভব।',
      'About $amount of that looks avoidable.');
  static String get habitsTitle => _p('নিয়মিত অভ্যাস', 'Repeated habits');
  static String habitLine(String amount, String times) => _p(
      '$amount করে $times বার তোলা হয়েছে',
      'Withdrawn $amount, $times times');
  static String get howComputed =>
      _p('এই হিসাব কীভাবে করা হলো?', 'How was this calculated?');
  static String get spendingTitle => _p('গত ৩০ দিনের খরচ', 'Spending, last 30 days');
  static String get spendingSubtitle => _p(
      'লেনদেনের ধরন স্বয়ংক্রিয়ভাবে শনাক্ত করা হয়েছে',
      'Transaction types detected automatically');

  // --- goal ---------------------------------------------------------------
  static String get safeToSaveTitle =>
      _p('আপনি নিরাপদে কত জমাতে পারেন', 'What you can safely save');
  static String get safeToSaveSubtitle => _p(
      'পূর্বাভাসের সবচেয়ে সতর্ক হিসাব (P10) থেকে',
      'From the most cautious forecast (P10)');
  static String get perWeek => _p('/ সপ্তাহ', '/ week');
  static String get yourGoal => _p('আপনার লক্ষ্য', 'Your goal');
  static String get howMuch => _p('কত টাকা', 'How much');
  static String get howLong => _p('কত সময়ে', 'In how long');
  static String monthsLabel(String n) => _p('$n মাস', '$n months');
  static String get result => _p('ফলাফল', 'Verdict');
  static String get feasible => _p('সম্ভব', 'Achievable');
  static String get tight => _p('টানটান', 'Tight');
  static String get notFeasible => _p('এখন সম্ভব নয়', 'Not yet');
  static String get neededPerWeek => _p('দরকার / সপ্তাহ', 'Needed / week');
  static String get safelyAvailable => _p('নিরাপদে সম্ভব', 'Safely available');
  static String get willAccumulate => _p('জমবে', 'Will accumulate');
  static String get alternatives => _p('বিকল্প পথ', 'Other ways');
  static String get altExtend => _p('সময় বাড়ান', 'Give it more time');
  static String altExtendBody(String weeks) => _p(
      'একই সাপ্তাহিক পরিমাণ রেখে লক্ষ্যের তারিখ $weeks সপ্তাহ পেছালে লক্ষ্যে পৌঁছানো যাবে।',
      'Keep the same weekly amount and move the target date $weeks weeks later.');
  static String get altFees =>
      _p('ক্যাশ-আউট ফি বাঁচিয়ে যোগ করুন', 'Redirect your cash-out fees');
  static String altFeesBody(String weekly, String total) => _p(
      'ক্যাশ-আউটের বদলে ডিজিটাল পেমেন্ট করলে সপ্তাহে প্রায় $weekly বাঁচে, '
      'যা যোগ করলে মোট দাঁড়ায় $total।',
      'Paying digitally instead of cashing out saves about $weekly a week, '
      'which would bring the total to $total.');
  static String get altOther =>
      _p('খরচ কমান বা সীমা পুনর্বিবেচনা করুন', 'Reduce an outflow, or revisit the floor');
  static String get altOtherBody => _p(
      'বর্তমান নিরাপত্তা সীমায় সঞ্চয়ের সুযোগ নেই। হয় সীমাটি জেনেবুঝে কমাতে হবে, '
      'নয়তো নিয়মিত কোনো খরচ কমাতে হবে।',
      'There is no safe capacity at the current safety floor. Either lower the floor '
      'deliberately, or reduce a recurring outflow.');

  /// The goal verdict sentence.
  ///
  /// Written here rather than taken from the API because the verdict itself is now
  /// computed in the app (see goal_math.dart), so its wording belongs with the rest of
  /// the app's language and switches with the toggle like everything else.
  static String goalVerdict(GoalPlan p) {
    final amount = money(p.goalAmount);
    final weeks = num_(p.weeks);
    final needed = money(p.requiredWeekly);
    final safe = money(p.safeWeekly);
    return switch (p.verdict) {
      GoalVerdict.feasible => _p(
          '$amount জমানোর লক্ষ্যটি বাস্তবসম্মত। সপ্তাহে $safe করে রাখলে '
          '$weeks সপ্তাহে লক্ষ্যে পৌঁছাবেন।',
          'Your goal of $amount is achievable: $safe per week reaches it in '
          '$weeks weeks.'),
      GoalVerdict.tight => _p(
          '$amount জমানোর লক্ষ্যটি সম্ভব, তবে বেশ টানটান। দরকার সপ্তাহে $needed, '
          'আর নিরাপদে সম্ভব $safe।',
          'The goal is close but tight: it needs $needed per week and $safe is what '
          'is safely available.'),
      GoalVerdict.notFeasible => _p(
          'এই সময়ের মধ্যে $amount জমানো বাস্তবসম্মত নয়। দরকার সপ্তাহে $needed, '
          'কিন্তু নিরাপদে সম্ভব $safe। সময় বাড়ালে বা খরচ কমালে লক্ষ্যটি সম্ভব হতে পারে।',
          'This goal is not realistic in the time given: it needs $needed a week '
          'against $safe available. Extending the deadline or reducing an outflow '
          'would change that.'),
    };
  }
  static String get noAutoStart => _p(
      'এই পরিকল্পনা স্বয়ংক্রিয়ভাবে চালু হবে না',
      'This plan does not start by itself');
  static String get noAutoStartBody => _p(
      'আপনার অনুমতি ছাড়া কোনো টাকা সরানো হবে না। আপনি যেকোনো সময় '
      'পরিমাণ বদলাতে বা বন্ধ করতে পারবেন।',
      'No money moves without your approval. You can change the amount or stop it '
      'at any time.');
  static String get confirmPlan =>
      _p('আমি রাজি — সাপ্তাহিক সঞ্চয় চালু করুন', 'I agree - start weekly saving');
  static String get planConfirmed => _p(
      'পরিকল্পনা নিশ্চিত করা হয়েছে (ডেমো)', 'Plan confirmed (demo)');

  // --- why ----------------------------------------------------------------
  static String get syntheticNotice => _p(
      'এই অ্যাপের সব তথ্য সিন্থেটিক (কৃত্রিমভাবে তৈরি)। কোনো প্রকৃত গ্রাহকের ডেটা '
      'ব্যবহার করা হয়নি।',
      'Every figure in this app is synthetic. No real customer data is used anywhere.');
  static String get howDecisionMade =>
      _p('সিদ্ধান্তটি কীভাবে তৈরি হলো', 'How this decision was made');
  static String get step1 => _p('পূর্বাভাস — মেশিন লার্নিং', 'Forecast - machine learning');
  static String get step1Body => _p(
      'আপনার নিজের লেনদেনের ইতিহাস থেকে আগামী ৩০ দিনের নগদ প্রবাহ অনুমান করা হয় '
      '(P10/P50/P90)। এটি একটি পরিসংখ্যানগত অনুমান, নিশ্চয়তা নয়।',
      'Your next 30 days of cash flow are estimated from your own transaction history '
      '(P10/P50/P90). This is a statistical projection, not a guarantee.');
  static String get step2 => _p('সিদ্ধান্ত — নির্দিষ্ট নিয়ম', 'Decision - a fixed rule');
  static String get step2Body => _p(
      'কত টাকা নিরাপদে জমানো যায় তা ঠিক করে একটি সাধারণ, যাচাইযোগ্য নিয়ম — কোনো '
      'মডেল নয়। সবচেয়ে সতর্ক অনুমান (P10) ব্যবহার করা হয়, যাতে খারাপ মাসেও সমস্যা না হয়।',
      'How much can safely be saved is decided by a simple, auditable rule - not a '
      'model. It uses the most cautious forecast (P10), so a bad month is already '
      'absorbed.');
  static String get step3 => _p('ব্যাখ্যা — ভাষা', 'Explanation - language');
  static String get step3Body => _p(
      'উপরের সংখ্যাগুলোকে সহজ বাংলায় লেখা হয়। ভাষার অংশটি কোনো সিদ্ধান্ত নেয় না এবং '
      'কোনো সংখ্যা বদলাতে পারে না।',
      'The numbers above are written out in plain language. This layer decides nothing '
      'and cannot change a figure.');
  static String get step4 => _p('অনুমোদন — আপনি', 'Approval - you');
  static String get step4Body => _p(
      'কোনো টাকা স্বয়ংক্রিয়ভাবে সরানো হয় না। প্রতিটি পরিকল্পনা আপনার নিশ্চিতকরণের '
      'অপেক্ষায় থাকে।',
      'No money moves automatically. Every plan waits for your confirmation.');
  static String get whyThisForecast =>
      _p('এই পূর্বাভাসের কারণ', 'What drives this forecast');
  static String get seeDetails => _p('বিস্তারিত দেখুন', 'See the detail');
  static String get technical => _p('কারিগরি তথ্য', 'Technical detail');
  static String get asOfLabel => _p('হিসাবের তারিখ', 'Calculated as of');
  static String get customerId => _p('গ্রাহক আইডি', 'Customer ID');
  static String get forecastModel => _p('পূর্বাভাস মডেল', 'Forecast model');
  static String get dataSource => _p('ডেটা উৎস', 'Data source');
  static String get precomputedSource => _p(
      'আগেই হিসাব করা ডেমো বান্ডল', 'Precomputed demo bundle');
  static String get dataKind => _p('ডেটার ধরন', 'Data type');
  static String get synthetic => _p('সিন্থেটিক', 'Synthetic');
  static String get weNeverDo => _p('আমরা যা করি না', 'What we never do');
  static String get never1 =>
      _p('আপনার অনুমতি ছাড়া টাকা সরাই না', 'Move money without your approval');
  static String get never2 =>
      _p('ঋণ অনুমোদন বা বাতিল করি না', 'Approve or decline any loan');
  static String get never3 => _p(
      'অপ্রয়োজনীয় খরচে উৎসাহ দিই না', 'Encourage spending you do not need');
  static String get never4 =>
      _p('লুকানো ফি বা শর্ত রাখি না', 'Hide a fee or a condition');

  // --- shared -------------------------------------------------------------
  static String get whyThisNumber => _p('কেন এই হিসাব?', 'Why this number?');

  /// Spending category names, keyed as the API returns them.
  static String category(String key, String? bnFromApi) {
    if (Settings.isBn) return bnFromApi ?? key;
    const en = {
      'income': 'Income',
      'rent': 'Rent',
      'utility': 'Utility bills',
      'mobile_recharge': 'Mobile recharge',
      'family_support': 'Family support',
      'food_grocery': 'Food & groceries',
      'transport': 'Transport',
      'cash_out': 'Cash-out',
      'other_retail': 'Other shopping',
    };
    return en[key] ?? key;
  }
}
