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

/// Wisdom cards only for feelings and life questions, never for facts, code or follow-ups.
bool wantsWisdom(String text, Understanding u) {
  if (isCodingQuestion(text)) return false;
  if (const {Mood.sad, Mood.anxious, Mood.angry, Mood.confused}.contains(u.mood)) return true;
  return RegExp(r'\b(gita|karma|dharma|god|soul|meditat\w*|spiritual\w*|purpose|meaning of life|peace|faith|krishna|buddha|mantra|stress\w*|lonely|sad|motivat\w*)\b', caseSensitive: false).hasMatch(text);
}

/// Who Buddy is and how he answers; [notes] are the saved memory of this session.
String systemPrompt(String name, {required bool code, String notes = ''}) {
  final lang = TalkSettings.hinglish ? 'Reply in Hinglish (Hindi in Roman script mixed with English).' : 'Reply in clear, simple English.';
  final memory = notes.isEmpty ? '' : '\n\nWhat you remember from earlier in this conversation:\n$notes';
  if (code) {
    return 'You are Buddy, an expert software engineer (Flutter/Dart, TypeScript, Unity/C#, Kotlin, Python) helping $name. '
        'Give correct, working code with a short explanation. Use the conversation so far: if the user refers to earlier code or errors, build on them. '
        'Use markdown code blocks. $lang$memory';
  }
  return 'You are Buddy, a smart, warm AI assistant on $name\'s phone, as capable as ChatGPT or Claude. '
      'Answer any question directly and accurately: facts, advice, planning, writing, maths, money, health, career, life. '
      'Remember and use everything $name said earlier in this conversation (names, numbers, plans, preferences) and refer back to it naturally. '
      'Match the length to the question: one or two sentences for small talk, clear steps or short bullet points for bigger questions. '
      'If you are not sure, say so instead of guessing; never make up facts or quotes. '
      'Be kind and supportive on personal topics; a reference idea from Indian wisdom may be added to the message, use it only if it truly fits. '
      '$lang$memory';
}

/// The new message, with the optional wisdom reference (never for code).
String userTurn(String user, List<Teaching> found, {required bool code}) {
  final ref = code || found.isEmpty ? '' : '\n\n(Optional reference idea, ${found.first.src}: ${found.first.mean} Small step: ${found.first.act})';
  return '$user$ref';
}

/// One prompt for on-device brains, whose engine takes a single user turn: the transcript, then the new message.
String localPrompt(String name, List<(bool, String)> turns, String message) {
  if (turns.isEmpty) return message;
  String clip(String t) => t.length > 1200 ? '${t.substring(0, 1200)}…' : t;
  final convo = turns.map((t) => '${t.$1 ? name : 'Buddy'}: ${clip(t.$2)}').join('\n');
  return 'Conversation so far:\n$convo\n\n'
      'New message from $name (reply to this only; use the conversation above for context, do not repeat it or start with "Buddy:"):\n$message';
}

/// Removes a speaker label a small model sometimes copies from the transcript.
String stripSpeaker(String reply) => reply.replaceFirst(RegExp(r'^\s*(buddy|assistant)\s*:\s*', caseSensitive: false), '');

/// Keeps only bullet lines (max 10) from a notes reply, dropping chatter around them.
String cleanNotes(String raw) {
  final lines = raw.split('\n').map((l) => l.trim()).where((l) => RegExp(r'^[-*•]\s+\S').hasMatch(l)).map((l) => '- ${l.substring(1).trim()}');
  return lines.take(10).join('\n');
}

/// Asks a brain to fold [turns] into the running [notes].
String notesPrompt(String name, String notes, List<(bool, String)> turns) {
  String clip(String t) => t.length > 600 ? '${t.substring(0, 600)}…' : t;
  final convo = turns.map((t) => '${t.$1 ? name : 'Buddy'}: ${clip(t.$2)}').join('\n');
  return 'Update the memory notes about a chat between $name and Buddy.\n\n'
      'Current notes:\n${notes.isEmpty ? '(none)' : notes}\n\nNew part of the chat:\n$convo\n\n'
      'Write the updated notes: at most 10 short bullet lines starting with "- ". Keep facts about $name (name, work, goals, plans, preferences, numbers), '
      'decisions made, questions still open and topics discussed. Drop small talk. Output only the bullets.';
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
