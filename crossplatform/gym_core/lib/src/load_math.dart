/// Port of LoadMath.swift: loads at a fixed 1 g resolution so floating-point noise never changes
/// a comparison. Same IEEE operations as Swift (`(v / 0.001).rounded() * 0.001`).
library;

class LoadMath {
  static const double resolution = 0.001;

  static double normalized(double value) => (value / resolution).roundToDouble() * resolution;

  static int key(double value) => (value / resolution).round();

  static bool isEqual(double a, double b) => key(a) == key(b);

  /// Next real load above `current`: the smallest available weight strictly above it (or null),
  /// else `current + increment`.
  static double? nextLoad(double current, double increment, List<double>? availableWeights) {
    if (availableWeights != null && availableWeights.isNotEmpty) {
      final currentKey = key(current);
      final sorted = availableWeights.map(normalized).toList()..sort();
      for (final w in sorted) {
        if (key(w) > currentKey) return w;
      }
      return null;
    }
    if (!(increment > 0)) return null;
    return normalized(current + increment);
  }
}

/// Stable merge sort (Dart's `List.sort` is not stable; Swift's `sorted` is).
List<T> stableSorted<T>(Iterable<T> input, int Function(T a, T b) compare) {
  final list = input.toList();
  if (list.length < 2) return list;
  final buffer = List<T>.of(list);
  void merge(int lo, int mid, int hi) {
    var i = lo, j = mid, k = lo;
    while (i < mid && j < hi) {
      if (compare(list[j], list[i]) < 0) {
        buffer[k++] = list[j++];
      } else {
        buffer[k++] = list[i++];
      }
    }
    while (i < mid) {
      buffer[k++] = list[i++];
    }
    while (j < hi) {
      buffer[k++] = list[j++];
    }
    for (var x = lo; x < hi; x++) {
      list[x] = buffer[x];
    }
  }

  for (var width = 1; width < list.length; width *= 2) {
    for (var lo = 0; lo < list.length - width; lo += 2 * width) {
      final mid = lo + width;
      final hi = (lo + 2 * width < list.length) ? lo + 2 * width : list.length;
      merge(lo, mid, hi);
    }
  }
  return list;
}

/// Comparator from a Swift-style "a comes before b" predicate.
int Function(T, T) byPredicate<T>(bool Function(T a, T b) before) =>
    (a, b) => before(a, b) ? -1 : (before(b, a) ? 1 : 0);
