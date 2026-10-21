import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/store.dart';

/// A Claude model on Amazon Bedrock with its price in US$ per million tokens.
class CloudModel {
  final String id, label;
  final double inPerM, outPerM;
  const CloudModel(this.id, this.label, this.inPerM, this.outPerM);
}

// Anthropic list prices; Bedrock bills the same on the global endpoint. Check
// https://aws.amazon.com/bedrock/pricing/ if AWS changes them.
const cloudModels = [
  CloudModel('anthropic.claude-opus-5-5', 'Opus 5.5', 4.0, 20.0),
  CloudModel('anthropic.claude-sonnet-5-5', 'Sonnet 5.5', 2.0, 10.0),
  CloudModel('anthropic.claude-haiku-5-5', 'Haiku 5.5', 0.10, 0.50),
];

/// Thrown before any text is produced: the caller should use the on-device brain instead.
class CloudUnavailable implements Exception {
  final String reason;
  const CloudUnavailable(this.reason);
  @override
  String toString() => reason;
}

/// Buddy's cloud brain: Claude on AWS Bedrock, guarded by daily and monthly US$ limits.
/// Every request first reserves its worst-case cost; if that could cross either limit, it is never sent.
class CloudBrain {
  CloudBrain._();
  static final instance = CloudBrain._();

  static const _storage = FlutterSecureStorage();
  static const _keyName = 'bedrock_api_key';
  /// Prices rounded up 10% so a small AWS price change or regional premium can't push us over.
  static const _safety = 1.1;

  String? _key;
  bool _keyLoaded = false;
  /// Last outcome, shown in the brain settings ("Answered by …", "Daily limit reached", errors).
  String? lastStatus;

  static bool get enabled => Store.raw.getBool('cloud_on') ?? false;
  static String get region => Store.raw.getString('cloud_region') ?? 'ap-south-1';
  static CloudModel get model => cloudModels.firstWhere((m) => m.id == Store.raw.getString('cloud_model'), orElse: () => cloudModels.first);
  static double get dailyLimit => Store.raw.getDouble('cloud_daily_usd') ?? 0.50;
  static double get monthlyLimit => Store.raw.getDouble('cloud_monthly_usd') ?? 5.00;

  static Future<void> setEnabled(bool v) => Store.raw.setBool('cloud_on', v);
  static Future<void> setModel(String id) => Store.raw.setString('cloud_model', id);
  static Future<void> setDailyLimit(double usd) => Store.raw.setDouble('cloud_daily_usd', usd);
  static Future<void> setMonthlyLimit(double usd) => Store.raw.setDouble('cloud_monthly_usd', usd);

  static String get _monthKey => dayKey().substring(0, 7);
  static double get spentToday => Store.raw.getDouble('cloud_spent_${dayKey()}') ?? 0;
  static double get spentMonth => Store.raw.getDouble('cloud_spent_$_monthKey') ?? 0;

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

  /// Adds [usd] (may be negative when settling a reservation) to today's and this month's spend.
  /// Writes hit the in-memory prefs cache synchronously, so check + reserve can't race.
  static void _add(double usd) {
    final d = 'cloud_spent_${dayKey()}', m = 'cloud_spent_$_monthKey';
    Store.raw.setDouble(d, ((Store.raw.getDouble(d) ?? 0) + usd).clamp(0, double.infinity));
    Store.raw.setDouble(m, ((Store.raw.getDouble(m) ?? 0) + usd).clamp(0, double.infinity));
  }

  static double _cost(CloudModel m, int inTok, int outTok) => (inTok * m.inPerM + outTok * m.outPerM) / 1e6 * _safety;

  /// Streams Claude's reply text. Throws [CloudUnavailable] (before yielding anything) when cloud is
  /// off, has no key, would cross a limit, or AWS fails; an error after text started is rethrown as-is.
  Stream<String> reply({required String system, required String user, required int maxTokens}) async* {
    if (!enabled) throw const CloudUnavailable('off');
    final key = await apiKey();
    if (key == null) throw CloudUnavailable(lastStatus = 'No Bedrock API key');
    final m = model;

    // Worst case: generous input estimate (≈2 chars/token) + every output token (incl. thinking) used.
    final estIn = ((system.length + user.length) / 2).ceil() + 100;
    final reserved = _cost(m, estIn, maxTokens);
    if (spentToday + reserved > dailyLimit) throw CloudUnavailable(lastStatus = 'Daily limit reached, using on-device brain');
    if (spentMonth + reserved > monthlyLimit) throw CloudUnavailable(lastStatus = 'Monthly limit reached, using on-device brain');
    _add(reserved);

    var settled = false;
    var inTok = 0, outTok = 0;
    var gotUsage = false, yielded = false;
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('https://bedrock-mantle.$region.api.aws/anthropic/v1/messages'))
        ..headers.addAll({'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'})
        ..body = jsonEncode({
          'model': m.id,
          'max_tokens': maxTokens,
          'stream': true,
          'system': system,
          'messages': [
            {'role': 'user', 'content': user},
          ],
          // Short chat answers: low effort keeps thinking (billed as output) small and replies fast.
          'output_config': {'effort': 'low'},
        });
      final http.StreamedResponse res;
      try {
        res = await client.send(req).timeout(const Duration(seconds: 20));
      } on TimeoutException {
        // AWS may still have run it: keep the reservation.
        throw CloudUnavailable(lastStatus = 'AWS timed out, using on-device brain');
      } catch (e) {
        // Never reached AWS (offline / DNS): nothing billed.
        _add(-reserved);
        settled = true;
        throw CloudUnavailable(lastStatus = 'Offline, using on-device brain');
      }
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString().catchError((_) => '');
        // ignore: avoid_print
        print('[BuddyCloud] HTTP ${res.statusCode}: $body');
        // A rejected request isn't billed: release the reservation.
        _add(-reserved);
        settled = true;
        throw CloudUnavailable(lastStatus = switch (res.statusCode) {
          401 || 403 => 'AWS rejected the key (HTTP ${res.statusCode})',
          429 => 'AWS is busy (rate limit), using on-device brain',
          _ => 'AWS error ${res.statusCode}, using on-device brain',
        });
      }
      final lines = res.stream.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(seconds: 30));
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final Map<String, dynamic> ev;
        try {
          ev = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        switch (ev['type']) {
          case 'message_start':
            final u = (ev['message'] as Map?)?['usage'] as Map?;
            inTok = ((u?['input_tokens'] ?? 0) as num).toInt() + ((u?['cache_creation_input_tokens'] ?? 0) as num).toInt() + ((u?['cache_read_input_tokens'] ?? 0) as num).toInt();
          case 'content_block_delta':
            final d = ev['delta'] as Map?;
            if (d?['type'] == 'text_delta') {
              yielded = true;
              yield d!['text'] as String;
            }
          case 'message_delta':
            final u = ev['usage'] as Map?;
            if (u?['output_tokens'] != null) {
              outTok = (u!['output_tokens'] as num).toInt();
              gotUsage = true;
            }
          case 'error':
            final msg = (ev['error'] as Map?)?['message'] ?? 'stream error';
            if (!yielded) throw CloudUnavailable(lastStatus = 'AWS: $msg');
            throw Exception(msg);
        }
      }
      if (!yielded) throw CloudUnavailable(lastStatus = 'Empty reply, using on-device brain');
      lastStatus = 'Answered by ${m.label} (cloud)';
    } finally {
      client.close();
      if (!settled && gotUsage) {
        // Replace the reservation with what AWS actually counted.
        _add(_cost(m, inTok, outTok) - reserved);
        // ignore: avoid_print
        print('[BuddyCloud] ${m.id}: in $inTok, out $outTok tokens; today \$${spentToday.toStringAsFixed(4)}, month \$${spentMonth.toStringAsFixed(4)}');
      }
      // No usage (cancelled / cut off): keep the full reservation; we never under-count.
    }
  }
}
