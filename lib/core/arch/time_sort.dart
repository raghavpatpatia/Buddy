/// How a list is ordered: as ranked or received (best), or by date and time.
enum TimeSort { best, newest, oldest }

/// [items] in [sort] order by [at]; `best` keeps the given order and undated items always go last.
List<T> sortByTime<T>(List<T> items, DateTime? Function(T) at, TimeSort sort) {
  if (sort == TimeSort.best) return items;
  final dated = items.where((e) => at(e) != null).toList()..sort((a, b) => at(a)!.compareTo(at(b)!));
  return [...(sort == TimeSort.newest ? dated.reversed : dated), ...items.where((e) => at(e) == null)];
}
