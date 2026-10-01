/// upay Shadhin - AI cash-flow copilot.
///
/// AI Hackathon 2026, DIU CPC x upay, Track 03 (Customer Innovation & Financial
/// Independence). All data shown is synthetic.
library;

import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/goal.dart';
import 'screens/home.dart';
import 'screens/insights.dart';
import 'screens/why.dart';
import 'theme.dart';

void main() => runApp(const ShadhinApp());

class ShadhinApp extends StatelessWidget {
  const ShadhinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'upay Shadhin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final ApiClient _client = ApiClient();
  int _tab = 0;

  String _userId = kFixtureUserId;
  List<dynamic> _users = const [];

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _forecast;
  Map<String, dynamic>? _insights;
  Map<String, dynamic>? _safeToSave;
  Map<String, dynamic>? _goal;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client.addListener(_onClientMode);
    _load();
  }

  @override
  void dispose() {
    _client.removeListener(_onClientMode);
    super.dispose();
  }

  void _onClientMode() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _client.users();
      // The bundled fixtures belong to one user; if the live API is unreachable we
      // must show that user rather than whatever was selected.
      if (_client.usingFixtures) _userId = kFixtureUserId;

      final results = await Future.wait([
        _client.profile(_userId),
        _client.forecast(_userId),
        _client.insights(_userId),
        _client.safeToSave(_userId),
        _client.simulateGoal(_userId, 30000, 180),
      ]);
      if (!mounted) return;
      setState(() {
        _users = users;
        _profile = results[0];
        _forecast = results[1];
        _insights = results[2];
        _safeToSave = results[3];
        _goal = results[4];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _switchUser(String id) async {
    setState(() => _userId = id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _profile == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40, color: C.risk),
                const SizedBox(height: 12),
                Text('ডেটা লোড করা যায়নি\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.6)),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('আবার চেষ্টা করুন')),
              ],
            ),
          ),
        ),
      );
    }

    final pages = [
      HomeScreen(forecast: _forecast!, profile: _profile!),
      InsightsScreen(insights: _insights!),
      GoalScreen(
        client: _client,
        userId: _userId,
        safeToSave: _safeToSave!,
        initialGoal: _goal!,
      ),
      WhyScreen(
        profile: _profile!,
        forecast: _forecast!,
        usingFixtures: _client.usingFixtures,
        baseUrl: _client.baseUrl,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: C.line)),
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('উপায় স্বাধীন',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            Text(
              '${_profile!['user_id']} • ${_profile!['archetype']}',
              style: const TextStyle(fontSize: 11.5, color: C.muted),
            ),
          ],
        ),
        actions: [
          if (_users.isNotEmpty && !_client.usingFixtures)
            PopupMenuButton<String>(
              tooltip: 'গ্রাহক বদলান',
              icon: const Icon(Icons.people_outline, color: C.ink),
              onSelected: _switchUser,
              itemBuilder: (_) => [
                for (final u in _users)
                  PopupMenuItem(
                    value: u['user_id'] as String,
                    child: Text(
                      '${u['user_id']}  •  ${u['archetype']}  •  ৳${bnNum((u['balance'] as num).toDouble())}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: C.ink),
            tooltip: 'রিফ্রেশ',
          ),
        ],
      ),
      body: Column(
        children: [
          // Be explicit about which data the viewer is looking at. Silently serving
          // captured responses as if they were live would be dishonest.
          if (_client.usingFixtures)
            Container(
              width: double.infinity,
              color: C.warnBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: const [
                  Icon(Icons.cloud_off, size: 16, color: C.warn),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'অফলাইন মোড — সংরক্ষিত ডেমো ডেটা দেখানো হচ্ছে',
                      style: TextStyle(fontSize: 12.5, color: C.warn),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: pages[_tab]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: C.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: C.brand.withValues(alpha: 0.14),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.show_chart_outlined),
              selectedIcon: Icon(Icons.show_chart),
              label: 'পূর্বাভাস'),
          NavigationDestination(
              icon: Icon(Icons.pie_chart_outline),
              selectedIcon: Icon(Icons.pie_chart),
              label: 'খরচ'),
          NavigationDestination(
              icon: Icon(Icons.savings_outlined),
              selectedIcon: Icon(Icons.savings),
              label: 'লক্ষ্য'),
          NavigationDestination(
              icon: Icon(Icons.help_outline),
              selectedIcon: Icon(Icons.help),
              label: 'কেন'),
        ],
      ),
    );
  }
}
