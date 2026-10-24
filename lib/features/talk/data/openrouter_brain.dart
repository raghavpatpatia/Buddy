import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// OpenRouter's free models with the user's own key: the backup when Gemini is over its quota or down.
/// Only `:free` models are ever called, so a key with no credits costs nothing.
class OpenRouterBrain {
  OpenRouterBrain._();
  static final instance = OpenRouterBrain._();

  static const _storage = FlutterSecureStorage();
  static const _keyName = 'openrouter_api_key';
  static const models = ['nvidia/nemotron-3.5-lightning:free', 'google/gemma-4-26b-a4b-it:free', 'google/gemma-4-31b-it:free'];

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

  /// The first free model's reply text, or null with no key, offline, or when every free model is busy.
  Future<String?> ask(String system, String prompt, {int maxTokens = 700}) async {
    final key = await apiKey();
    if (key == null) return null;
    for (final model in models) {
      try {
        final res = await http
            .post(
              Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
              headers: {'content-type': 'application/json', 'authorization': 'Bearer $key', 'X-Title': 'Buddy'},
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'system', 'content': system},
                  {'role': 'user', 'content': prompt},
                ],
                'temperature': 1.0,
                'max_tokens': maxTokens,
                'reasoning': {'enabled': false},
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final text = ((((jsonDecode(res.body) as Map)['choices'] as List).first as Map)['message']['content'] as String? ?? '').trim();
          if (text.isNotEmpty) return text;
          continue;
        }
        // ignore: avoid_print
        print('[BuddyOpenRouter] $model HTTP ${res.statusCode}: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
        if (res.statusCode == 401 || res.statusCode == 402) return null; // bad key / no credits: other models won't help
      } catch (e) {
        // ignore: avoid_print
        print('[BuddyOpenRouter] $model $e');
      }
    }
    return null;
  }
}
