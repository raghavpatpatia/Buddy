import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Google Gemini on its free tier: fast one-off answers (food ideas) with the user's own key.
class GeminiBrain {
  GeminiBrain._();
  static final instance = GeminiBrain._();

  static const _storage = FlutterSecureStorage();
  static const _keyName = 'gemini_api_key';
  static const model = 'gemini-flash-lite-latest';

  String? _key;
  bool _keyLoaded = false;

  Future<String?> apiKey() async {
    if (!_keyLoaded) {
      try {
        _key = await _storage.read(key: _keyName);
      } catch (_) {}
      _keyLoaded = true;
    }
    return _key;
  }

  Future<void> setApiKey(String? key) async {
    final k = key?.trim();
    if (k == null || k.isEmpty) {
      await _storage.delete(key: _keyName);
      _key = null;
    } else {
      await _storage.write(key: _keyName, value: k);
      _key = k;
    }
    _keyLoaded = true;
  }

  /// Gemini's reply text, or null with no key, offline, over the free quota or on an error.
  /// Google's edge sometimes answers an empty 404 / 5xx for a moment, so one failure is retried.
  Future<String?> ask(String system, String prompt, {int maxTokens = 700}) async {
    final key = await apiKey();
    if (key == null) return null;
    // Newer "AQ." keys only work as a query parameter, not the x-goog-api-key header.
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key');
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': system}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 1.0,
        'maxOutputTokens': maxTokens,
        'thinkingConfig': {'thinkingLevel': 'minimal'},
      },
    });
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await http.post(uri, headers: {'content-type': 'application/json'}, body: body).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final parts = (((jsonDecode(res.body) as Map)['candidates'] as List).first as Map)['content']['parts'] as List;
          final text = parts.map((p) => (p as Map)['text'] ?? '').join().trim();
          return text.isEmpty ? null : text;
        }
        // ignore: avoid_print
        print('[BuddyGemini] HTTP ${res.statusCode}: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
        if (res.statusCode == 400 || res.statusCode == 403 || res.statusCode == 429) return null; // bad key / quota: retrying won't help
      } catch (e) {
        // ignore: avoid_print
        print('[BuddyGemini] $e');
      }
    }
    return null;
  }
}
