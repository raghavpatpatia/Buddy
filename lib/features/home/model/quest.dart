/// A daily quest on the home screen; [progress] is 0..1 and claiming it gives [xp].
class Quest {
  final String id, title, emoji, progressText;
  final double progress;
  final int xp;
  const Quest(this.id, this.emoji, this.title, this.progress, this.xp, this.progressText);
  bool get done => progress >= 1;
}
