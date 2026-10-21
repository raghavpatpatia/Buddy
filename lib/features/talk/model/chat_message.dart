import '../../../core/arch/repository.dart';

/// One chat bubble; [refs] are ids of teachings shown as verse cards.
class ChatMessage {
  final bool user;
  final String text;
  final List<String> refs;
  const ChatMessage(this.user, this.text, [this.refs = const []]);

  ChatMessage withText(String t) => ChatMessage(user, t, refs);

  static final codec = JsonCodec<ChatMessage>(
    encode: (m) => {'u': m.user, 't': m.text, 'r': m.refs},
    decode: (j) => ChatMessage(j['u'] == true, j['t'] ?? '', List<String>.from(j['r'] ?? [])),
  );
}
