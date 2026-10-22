import '../../../core/store.dart';
import '../model/chat_context.dart';
import '../model/chat_message.dart';

/// The saved Talk session: messages plus memory notes that summarise turns too old to send word for word.
class ChatMemory {
  ChatMemory._();
  static final instance = ChatMemory._();

  static const keep = 200;

  final messages = <ChatMessage>[];
  bool _loaded = false;

  /// Bullet notes about older turns; empty until the chat outgrows a brain's window.
  String get notes => Store.raw.getString('chat_notes') ?? '';

  /// How many of the oldest history turns [notes] already cover.
  int get noted => Store.raw.getInt('chat_noted') ?? 0;

  void load() {
    if (_loaded) return;
    _loaded = true;
    messages.addAll((Store.getJson('chat', []) as List).map((e) => ChatMessage.codec.decode(e)));
  }

  /// Turns worth remembering: everything said, minus empty placeholders.
  List<Turn> get history => [for (final m in messages) if (m.text.trim().isNotEmpty) (m.user, m.text)];

  ChatContext context(int budget) => buildContext(history, notes, budget: budget);

  /// Turns that left the window but aren't in the notes yet.
  List<Turn> unnoted(ChatContext c) {
    final h = history;
    final from = noted.clamp(0, h.length), to = c.dropped.clamp(0, h.length);
    return from < to ? h.sublist(from, to) : const [];
  }

  Future<void> setNotes(String text, int upTo) async {
    await Store.raw.setString('chat_notes', text.trim());
    await Store.raw.setInt('chat_noted', upTo);
  }

  /// Saves the last [keep] messages; older ones are covered by the notes, so the counter moves with them.
  Future<void> save() async {
    if (messages.length > keep) {
      final cut = messages.length - keep;
      final cutTurns = [for (final m in messages.take(cut)) if (m.text.trim().isNotEmpty) m].length;
      messages.removeRange(0, cut);
      await Store.raw.setInt('chat_noted', (noted - cutTurns).clamp(0, 1 << 30));
    }
    await Store.setJson('chat', [for (final m in messages) ChatMessage.codec.encode(m)]);
  }

  /// Forgets the whole session: messages and notes.
  Future<void> clear() async {
    messages.clear();
    await Store.raw.remove('chat_notes');
    await Store.raw.remove('chat_noted');
    await Store.setJson('chat', []);
  }
}
