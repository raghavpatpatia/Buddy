import 'talk_settings.dart';
import 'wisdom.dart';

/// Sent in a reply stream to tell the UI to discard the partial reply (a retry or fallback follows).
const resetReply = '\u0000reset';

/// Chinese, Japanese and Korean scripts: a sign a small multilingual model has drifted.
final cjkText = RegExp(r'[぀-ヿ㐀-䶿一-鿿가-힯＀-￯]');

/// True when a reply is a canned refusal ("I'm sorry, but I can't assist with that").
bool isRefusal(String reply) => RegExp(r"^\W*(i'?m sorry|sorry|i (cannot|can'?t|am unable|'m unable)|as an ai)\b[^.!?]{0,80}\b(assist|help|respond|answer|provide|do that)", caseSensitive: false).hasMatch(reply.trim());

/// Rough "is this a coding question?" check: code fences, symbols, or dev vocabulary.
bool isCodingQuestion(String text) {
  final t = text.toLowerCase();
  if (t.contains('```') || RegExp(r'[{};]\s*$|=>|\w+\(\)|</?\w+>', multiLine: true).hasMatch(text)) return true;
  return RegExp(
    r'\b(code|coding|bug|debug|error|exception|stack ?trace|crash|compile|flutter|dart|widget|unity|c#|csharp|cocos|typescript|javascript|js|ts|python|java|kotlin|swift|sql|api|json|regex|git|function|method|class|variable|array|list|loop|recursion|algorithm|async|await|null|shader|prefab|gradle|npm|build fail|null pointer|refactor)\b',
  ).hasMatch(t);
}

/// Who Buddy is and how he answers.
String systemPrompt(String name, {required bool code}) {
  if (code) {
    return 'You are Buddy, a senior Flutter, TypeScript and Unity developer. Give a short working code snippet, then 1–2 sentences. Only more if asked.';
  }
  return 'You are Buddy, $name\'s friendly robot with a calm, spiritual heart. Reply ${TalkSettings.hinglish ? 'in Hinglish' : 'in simple English'}, '
      '1–3 short sentences, only what was asked. Use the reference idea if it fits and name its source. Never invent scripture. For money questions give practical tips: budget, emergency fund, avoid debt, SIP in index funds.';
}

/// The user's message with optional context: the last exchange and one matching teaching.
String userTurn(String name, String user, List<(bool, String)> history, List<Teaching> found, {required bool code}) {
  final last = history.length > 2 ? history.sublist(history.length - 2) : history;
  final convo = last.map((h) => '${h.$1 ? name : 'Buddy'}: ${h.$2.length > 120 ? '${h.$2.substring(0, 120)}…' : h.$2}').join('\n');
  final ref = code || found.isEmpty ? '' : '\n\n(Reference idea, ${found.first.src}: ${found.first.mean} Small step: ${found.first.act})';
  return '${convo.isEmpty ? '' : '(Earlier:\n$convo)\n\n'}$user$ref';
}

/// Instant reply from the matched teaching, used when no AI is available. Short and on-topic.
String offlineReply(String userText, List<Teaching> found, {bool coding = false}) {
  final name = TalkSettings.userName;
  final hinglish = TalkSettings.hinglish;
  if (coding) {
    return hinglish
        ? 'Abhi mera AI brain ready nahi hai, ek baar phir try karo. Tip: error ka pehla line aur stack trace ka top frame padho, wahi bug batate hain.'
        : 'My AI brain isn’t ready right now, so please try again in a moment. Tip: read the first error line and the top stack frame; they usually point right at the bug.';
  }
  final u = understand(userText);
  final open = hinglish
      ? switch (u.mood) {
          Mood.sad => 'Main samajhta hoon, $name.',
          Mood.anxious => 'Ek gehri saans lo, $name.',
          Mood.angry => 'Gussa natural hai, bas usse drive mat karne do.',
          Mood.happy => 'Waah! 😄',
          _ => 'Hmm, $name.',
        }
      : switch (u.mood) {
          Mood.sad => 'I hear you, $name.',
          Mood.anxious => 'Take one slow breath, $name.',
          Mood.angry => 'Anger is natural; just don’t let it drive.',
          Mood.happy => 'Love that! 😄',
          _ => 'Hmm, $name.',
        };
  if (found.isEmpty) return hinglish ? '$open Thoda aur batao?' : '$open Tell me a little more?';
  final t = found.first;
  return hinglish ? '$open ${t.mean} (${t.src}) Aaj: ${t.act}' : '$open ${t.mean} (${t.src}) Try today: ${t.act}';
}
