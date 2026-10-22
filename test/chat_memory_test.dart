import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/talk/data/chat_memory.dart';
import 'package:buddy_app/features/talk/data/cloud_brain.dart';
import 'package:buddy_app/features/talk/data/prompts.dart';
import 'package:buddy_app/features/talk/data/reply_chain.dart';
import 'package:buddy_app/features/talk/data/wisdom.dart';
import 'package:buddy_app/features/talk/model/brain_model.dart';
import 'package:buddy_app/features/talk/model/chat_context.dart';
import 'package:buddy_app/features/talk/model/chat_message.dart';
import 'package:buddy_app/features/talk/view/talk_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Source that records what it was asked and answers with a fixed text.
class _Spy implements ReplySource {
  ReplyRequest? last;
  @override
  Stream<String> reply(ReplyRequest r) async* {
    last = r;
    yield 'ok';
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    ChatMemory.instance.messages.clear();
  });

  group('context window', () {
    final history = <Turn>[
      (false, 'Hi 👋'),
      (true, 'My name is Raghav and I make games in Unity.'),
      (false, 'Nice to meet you, Raghav!'),
      (true, 'I earn 80k a month and want to save for a PC.'),
      (false, 'Great goal. How much does the PC cost?'),
      (true, 'About 1.5 lakh.'),
    ];

    test('everything fits: the whole chat minus the leading greeting', () {
      final c = buildContext(history, '', budget: 10000);
      expect(c.turns.first.$2, startsWith('My name is Raghav'));
      expect(c.turns.length, 5);
      expect(c.dropped, 1);
    });

    test('small budget keeps the newest whole turns and always starts with the user', () {
      final c = buildContext(history, '', budget: 90);
      expect(c.turns.last.$2, 'About 1.5 lakh.');
      expect(c.turns.first.$1, isTrue);
      expect(c.turns.length, lessThan(5));
      expect(c.dropped + c.turns.length, history.length);
    });

    test('notes use up part of the budget', () {
      final none = buildContext(history, '', budget: 200).turns.length;
      final withNotes = buildContext(history, 'x' * 150, budget: 200).turns.length;
      expect(withNotes, lessThan(none));
    });

    test('bigger brains remember more', () {
      expect(smartBrain.historyChars, greaterThan(fastBrain.historyChars));
      expect(fastBrain.historyChars, greaterThan(2000));
    });
  });

  group('saved session memory', () {
    test('messages and notes survive a restart; clear forgets both', () async {
      final m = ChatMemory.instance;
      m.messages.addAll(const [ChatMessage(false, 'Hi'), ChatMessage(true, 'I live in Pune'), ChatMessage(false, '')]);
      await m.save();
      await m.setNotes('- Lives in Pune', 2);
      final saved = [for (final j in Store.getJson('chat') as List) ChatMessage.codec.decode(j)];
      expect(saved.map((x) => x.text), ['Hi', 'I live in Pune', '']);
      expect(Store.raw.getString('chat_notes'), '- Lives in Pune');
      await m.clear();
      expect(m.messages, isEmpty);
      expect(m.notes, '');
      expect(m.noted, 0);
      expect(Store.getJson('chat'), isEmpty);
    });

    test('history skips empty placeholders', () {
      final m = ChatMemory.instance;
      m.messages.addAll(const [ChatMessage(true, 'Q'), ChatMessage(false, '')]);
      expect(m.history, [(true, 'Q')]);
    });

    test('unnoted: only turns that left the window and are not in the notes yet', () async {
      final m = ChatMemory.instance;
      for (var i = 0; i < 10; i++) {
        m.messages.add(ChatMessage(i.isEven, 'message number $i ${'x' * 40}'));
      }
      final ctx = m.context(200);
      expect(m.unnoted(ctx), hasLength(ctx.dropped));
      await m.setNotes('- something', ctx.dropped);
      expect(m.unnoted(ctx), isEmpty);
    });

    test('trimming old messages moves the noted counter with them', () async {
      final m = ChatMemory.instance;
      for (var i = 0; i < ChatMemory.keep + 10; i++) {
        m.messages.add(ChatMessage(i.isEven, 'm$i'));
      }
      await m.setNotes('- n', 30);
      await m.save();
      expect(m.messages, hasLength(ChatMemory.keep));
      expect(m.noted, 20);
    });
  });

  group('what the brains receive', () {
    test('the chain passes the whole session and notes to each source', () async {
      final spy = _Spy();
      final chain = ReplyChain([spy]);
      await chain.reply(text: 'How long to save for it?', history: const [(true, 'PC costs 1.5 lakh'), (false, 'Got it')], found: const [], notes: '- Earns 80k').toList();
      expect(spy.last!.history, hasLength(2));
      expect(spy.last!.notes, '- Earns 80k');
      expect(spy.last!.window(10000).turns.first.$2, 'PC costs 1.5 lakh');
    });

    test('cloud messages alternate roles, start with the user and end with the new message', () {
      final msgs = chatMessages(const [(false, 'Hi!'), (true, 'a'), (true, 'b'), (false, 'c')], 'new');
      expect(msgs.map((m) => m['role']), ['user', 'assistant', 'user']);
      expect(msgs.first['content'], 'a\n\nb');
      expect(msgs.last['content'], 'new');
    });

    test('system prompt carries the memory notes and no "1–3 sentences" limit', () {
      final s = systemPrompt('Raghav', code: false, notes: '- Wants a gaming PC');
      expect(s, contains('- Wants a gaming PC'));
      expect(s, contains('Remember and use everything'));
      expect(s, isNot(contains('1–3 short sentences')));
    });

    test('on-device prompt includes the transcript and marks the new message', () {
      final p = localPrompt('Raghav', const [(true, 'I am 26'), (false, 'Noted!')], 'How old am I?');
      expect(p, contains('Raghav: I am 26'));
      expect(p, contains('Buddy: Noted!'));
      expect(p.trim(), endsWith('How old am I?'));
      expect(localPrompt('Raghav', const [], 'Hi'), 'Hi');
    });

    test('wisdom cards only for feelings and life questions', () {
      bool w(String t) => wantsWisdom(t, understand(t));
      expect(w('What were we just talking about?'), isFalse);
      expect(w('Name the seven wonders'), isFalse);
      expect(w('fix this dart error'), isFalse);
      expect(w('I feel so stressed and lonely today'), isTrue);
      expect(w('What does the Gita say about karma?'), isTrue);
    });

    test('a copied speaker label is removed', () {
      expect(stripSpeaker('Buddy: You are 26.'), 'You are 26.');
      expect(stripSpeaker('You are 26.'), 'You are 26.');
    });

    test('notes keep only bullet lines, at most 10', () {
      final raw = 'Here are the notes:\n- Name is Raghav\n* Lives in Bengaluru\n• Saving for a PC\n${List.generate(12, (i) => '- extra $i').join('\n')}\nHope that helps!';
      final notes = cleanNotes(raw);
      expect(notes.split('\n').first, '- Name is Raghav');
      expect(notes.split('\n')[1], '- Lives in Bengaluru');
      expect(notes.split('\n'), hasLength(10));
      expect(notes, isNot(contains('Hope')));
    });
  });

  testWidgets('chat replies render bold, code, headings and bullets', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SelectableText.rich(TextSpan(children: markdownSpans('## Plan\n- Save **20k** a month\n- Use `SIP`', Colors.black)))),
    ));
    final text = t.widget<SelectableText>(find.byType(SelectableText)).textSpan!.toPlainText();
    expect(text, 'Plan\n•  Save 20k a month\n•  Use SIP');
  });
}
