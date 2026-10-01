/// API client for the upay Shadhin service, with a bundled-fixture fallback.
///
/// The fallback is not a convenience, it is a demo requirement: if the backend is not
/// running - or dies mid-pitch - every screen still renders real captured responses
/// instead of a spinner. `ApiClient.usingFixtures` drives the banner that tells the
/// viewer which mode they are looking at, because silently showing stale data would be
/// dishonest.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

const String kDefaultBaseUrl = String.fromEnvironment(
  'SHADHIN_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

/// The user the bundled fixtures were captured for.
const String kFixtureUserId = 'U100007';

class ApiClient extends ChangeNotifier {
  ApiClient({this.baseUrl = kDefaultBaseUrl});

  final String baseUrl;

  bool _usingFixtures = false;
  bool get usingFixtures => _usingFixtures;

  bool _checked = false;
  bool get checked => _checked;

  void _setMode(bool fixtures) {
    _checked = true;
    if (_usingFixtures != fixtures) {
      _usingFixtures = fixtures;
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _fixture(String name) async {
    final raw = await rootBundle.loadString('assets/fixtures/$name.json');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<List<dynamic>> _fixtureList(String name) async {
    final raw = await rootBundle.loadString('assets/fixtures/$name.json');
    return jsonDecode(raw) as List<dynamic>;
  }

  Future<T> _get<T>(String path, String fixture, {bool isList = false}) async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        _setMode(false);
        return jsonDecode(utf8.decode(r.bodyBytes)) as T;
      }
    } catch (_) {
      // fall through to fixtures
    }
    _setMode(true);
    return (isList ? await _fixtureList(fixture) : await _fixture(fixture)) as T;
  }

  Future<List<dynamic>> users() => _get<List<dynamic>>('/users?limit=12', 'users', isList: true);

  Future<Map<String, dynamic>> profile(String id) =>
      _get<Map<String, dynamic>>('/profile/$id', 'profile');

  Future<Map<String, dynamic>> forecast(String id) =>
      _get<Map<String, dynamic>>('/forecast/$id', 'forecast');

  Future<Map<String, dynamic>> insights(String id) =>
      _get<Map<String, dynamic>>('/insights/$id', 'insights');

  Future<Map<String, dynamic>> safeToSave(String id) =>
      _get<Map<String, dynamic>>('/safe-to-save/$id', 'safe_to_save');

  Future<Map<String, dynamic>> simulateGoal(
      String id, double amount, int deadlineDays) async {
    try {
      final r = await http
          .post(
            Uri.parse('$baseUrl/goal/simulate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': id,
              'goal_amount': amount,
              'deadline_days': deadlineDays,
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        _setMode(false);
        return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {
      // fall through
    }
    _setMode(true);
    // The fixture was captured for one goal; label it so the screen can say so.
    final f = await _fixture('goal');
    f['_fixture'] = true;
    return f;
  }
}
