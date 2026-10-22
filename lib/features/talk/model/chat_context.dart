/// One turn of the conversation: (is the user speaking, text).
typedef Turn = (bool user, String text);

/// What a brain sees of the conversation: memory notes on older turns plus the newest turns word for word.
class ChatContext {
  final String notes;
  final List<Turn> turns;

  /// How many of the oldest history turns didn't fit and are only covered by [notes].
  final int dropped;
  const ChatContext(this.notes, this.turns, this.dropped);
}

/// The newest [history] turns that fit in [budget] characters (whole turns only, at most [maxTurns]).
/// Leading Buddy turns are skipped so the window always starts with something the user said.
ChatContext buildContext(List<Turn> history, String notes, {required int budget, int maxTurns = 40}) {
  var used = notes.length, start = history.length;
  while (start > 0 && history.length - start < maxTurns) {
    final size = history[start - 1].$2.length + 12;
    if (used + size > budget) break;
    used += size;
    start--;
  }
  while (start < history.length && !history[start].$1) {
    start++;
  }
  return ChatContext(notes, history.sublist(start), start);
}
