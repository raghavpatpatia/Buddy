import 'package:buddy_app/features/talk/data/prompts.dart';
import 'package:buddy_app/features/talk/data/reply_chain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test source: optionally yields some text, then either finishes or throws.
class _Fake implements ReplySource {
  final List<String> tokens;
  final bool fail;
  int calls = 0;
  _Fake(this.tokens, {this.fail = false});
  @override
  Stream<String> reply(ReplyRequest r) async* {
    calls++;
    for (final t in tokens) {
      yield t;
    }
    if (fail) throw const ReplyUnavailable('test');
  }
}

void main() {
  test('first source that answers wins; later sources are not asked', () async {
    final a = _Fake(['hi']), b = _Fake(['no']);
    final out = await ReplyChain([a, b]).reply(text: 'x', history: const [], found: const []).toList();
    expect(out, ['hi']);
    expect(b.calls, 0);
  });

  test('a source that cannot answer passes to the next one', () async {
    final out = await ReplyChain([_Fake([], fail: true), _Fake(['offline'])]).reply(text: 'x', history: const [], found: const []).toList();
    expect(out, ['offline']);
  });

  test('a source failing mid-answer is wiped (reset) before the next one answers', () async {
    final out = await ReplyChain([_Fake(['half '], fail: true), _Fake(['full answer'])]).reply(text: 'x', history: const [], found: const []).toList();
    expect(out, ['half ', resetReply, 'full answer']);
  });

  test('cancelAll stops a reply from reaching the next source', () async {
    late ReplyChain chain;
    final later = _Fake(['late']);
    chain = ReplyChain([_CancelThenFail(() => chain.cancelAll()), later]);
    final out = await chain.reply(text: 'x', history: const [], found: const []).toList();
    expect(out, isEmpty);
    expect(later.calls, 0);
  });
}

class _CancelThenFail implements ReplySource {
  final void Function() cancel;
  _CancelThenFail(this.cancel);
  @override
  Stream<String> reply(ReplyRequest r) async* {
    cancel();
    throw const ReplyUnavailable('test');
  }
}
