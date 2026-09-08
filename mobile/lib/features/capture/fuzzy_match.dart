/// Utility for fuzzy string matching (Levenshtein distance and token similarity)
/// to match noisy OCR-extracted text against known master lists of buyers and seller entities.
class FuzzyMatch {
  /// Calculates Levenshtein distance between two strings.
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> previousRow = List<int>.generate(s2.length + 1, (i) => i);
    List<int> currentRow = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      currentRow[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        currentRow[j + 1] = [
          currentRow[j] + 1,
          previousRow[j + 1] + 1,
          previousRow[j] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
      previousRow = List<int>.from(currentRow);
    }
    return previousRow[s2.length];
  }

  /// Returns normalized similarity score between 0.0 and 1.0.
  static double similarity(String s1, String s2) {
    final str1 = s1.trim().toLowerCase();
    final str2 = s2.trim().toLowerCase();
    if (str1.isEmpty || str2.isEmpty) return 0.0;
    if (str1 == str2) return 1.0;
    if (str1.contains(str2) || str2.contains(str1)) return 0.85;

    int distance = levenshteinDistance(str1, str2);
    int maxLength = str1.length > str2.length ? str1.length : str2.length;
    return 1.0 - (distance / maxLength);
  }

  /// Token-based overlap similarity (handles word order differences e.g. "Zepto Pvt Ltd" vs "Zepto Limited").
  static double tokenSetSimilarity(String s1, String s2) {
    final tokens1 = s1.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    final tokens2 = s2.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    if (tokens1.isEmpty || tokens2.isEmpty) return 0.0;

    final intersection = tokens1.intersection(tokens2);
    final union = tokens1.union(tokens2);
    return intersection.length / union.length;
  }

  /// Combined similarity score taking maximum of edit distance and token set ratio.
  static double combinedScore(String s1, String s2) {
    final sim = similarity(s1, s2);
    final tokenSim = tokenSetSimilarity(s1, s2);
    return sim > tokenSim ? sim : tokenSim;
  }

  /// Finds the best match candidate from [candidates] for a given [query].
  /// Returns null if no candidate reaches [minScore] (default 0.55).
  static T? findBestMatch<T>(
    String query,
    List<T> candidates,
    String Function(T candidate) getLabel, {
    double minScore = 0.55,
  }) {
    if (query.trim().isEmpty || candidates.isEmpty) return null;

    T? bestCandidate;
    double maxScore = 0.0;

    for (final candidate in candidates) {
      final label = getLabel(candidate);
      final score = combinedScore(query, label);
      if (score > maxScore) {
        maxScore = score;
        bestCandidate = candidate;
      }
    }

    return maxScore >= minScore ? bestCandidate : null;
  }
}
