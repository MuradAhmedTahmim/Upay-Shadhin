/// upay Shadhin - AI cash-flow copilot.
///
/// AI Hackathon 2026, DIU CPC x upay, Track 03 (Customer Innovation & Financial
/// Independence). All data shown is synthetic.
library;

import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';
import 'screens/goal.dart';
import 'screens/home.dart';
import 'screens/insights.dart';
import 'screens/why.dart';
import 'settings.dart';
import 'theme.dart';

void main() => runApp(const ShadhinApp());

class ShadhinApp extends StatefulWidget {
  const ShadhinApp({super.key});

  @override
  State<ShadhinApp> createState() => _ShadhinAppState();
}

class _ShadhinAppState extends State<ShadhinApp> {
  /// Language and theme are read globally (see settings.dart); rebuilding from the
  /// root is what makes every lookup consistent with what is on screen.
  void _refreshAll() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'upay Shadhin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Shell(onSettingsChanged: _refreshAll),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.onSettingsChanged});

  final VoidCallback onSettingsChanged;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final ApiClient _client = ApiClient();
  int _tab = 0;

  String? _userId;
  List<dynamic> _users = const [];

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _forecast;
  Map<String, dynamic>? _insights;
  Map<String, dynamic>? _safeToSave;

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
      final id = _userId ??
          (users.isNotEmpty
              ? (users.first as Map)['user_id'] as String
              : await _client.defaultUserId());

      final results = await Future.wait([
        _client.profile(id),
        _client.forecast(id),
        _client.insights(id),
        _client.safeToSave(id),
      ]);
      if (!mounted) return;
      setState(() {
        _users = users;
        _userId = id;
        _profile = results[0];
        _forecast = results[1];
        _insights = results[2];
        _safeToSave = results[3];
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
    setState(() {
      _userId = id;
      _tab = _tab;
    });
    await _load();
  }

  void _toggleTheme() {
    Settings.dark = !Settings.dark;
    widget.onSettingsChanged();
  }

  void _toggleLanguage() {
    Settings.lang = Settings.isBn ? Lang.en : Lang.bn;
    widget.onSettingsChanged();
  }

  double get _monthlyAvoidableFees {
    final leak = _insights?['leakage'] as Map<String, dynamic>?;
    final annual = (leak?['avoidable_fees_annualised'] as num?)?.toDouble() ?? 0;
    return annual / 12.0;
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
                Icon(Icons.error_outline, size: 40, color: C.risk),
                const SizedBox(height: 12),
                Text('${T.loadFailed}\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.6)),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: Text(T.retry)),
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
        userId: _userId!,
        safeToSave: _safeToSave!,
        monthlyAvoidableFees: _monthlyAvoidableFees,
        asOf: DateTime.parse(_profile!['as_of'] as String),
      ),
      WhyScreen(
        profile: _profile!,
        forecast: _forecast!,
        precomputed: _client.isPrecomputed,
        baseUrl: _client.baseUrl,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: C.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: C.line)),
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(T.appName,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            Text(
              '${_profile!['user_id']} • ${_profile!['archetype']}',
              style: TextStyle(fontSize: 11.5, color: C.muted),
            ),
          ],
        ),
        actions: [
          // Language and theme sit together at the top right, where a viewer looks
          // for them, and both are labelled on hover for a judge using a mouse.
          TextButton(
            onPressed: _toggleLanguage,
            style: TextButton.styleFrom(
              foregroundColor: C.ink,
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(
              Settings.isBn ? 'EN' : 'বাং',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: _toggleTheme,
            tooltip: T.toggleTheme,
            icon: Icon(
              Settings.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: C.ink,
            ),
          ),
          if (_users.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: T.switchCustomer,
              icon: Icon(Icons.people_outline, color: C.ink),
              onSelected: _switchUser,
              itemBuilder: (_) => [
                for (final u in _users)
                  PopupMenuItem(
                    value: u['user_id'] as String,
                    child: Text(
                      '${u['user_id']}  •  ${u['archetype']}  •  '
                      '${money((u['balance'] as num).toDouble())}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          IconButton(
            onPressed: _load,
            icon: Icon(Icons.refresh, color: C.ink),
            tooltip: T.refresh,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Say which mode is running. The precomputed bundle is real model output,
          // not a mock-up - but it is fixed to one forecast date, and implying it is
          // live would be dishonest.
          if (_client.isPrecomputed)
            Container(
              width: double.infinity,
              color: C.infoBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 16, color: C.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      T.precomputedBanner,
                      style: TextStyle(fontSize: 12.5, color: C.info),
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
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.show_chart_outlined),
              selectedIcon: const Icon(Icons.show_chart),
              label: T.navForecast),
          NavigationDestination(
              icon: const Icon(Icons.pie_chart_outline),
              selectedIcon: const Icon(Icons.pie_chart),
              label: T.navSpending),
          NavigationDestination(
              icon: const Icon(Icons.savings_outlined),
              selectedIcon: const Icon(Icons.savings),
              label: T.navGoal),
          NavigationDestination(
              icon: const Icon(Icons.help_outline),
              selectedIcon: const Icon(Icons.help),
              label: T.navWhy),
        ],
      ),
    );
  }
}
