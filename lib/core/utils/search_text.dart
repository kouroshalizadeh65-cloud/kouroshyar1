/// Normalizes Persian/Arabic text for tolerant, immediate local search.
String normalizeSearchText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('ي', 'ی')
    .replaceAll('ى', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('ۀ', 'ه')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
    .replaceAll(RegExp(r'[\s\u200c\u200f\u200e]+'), ' ');

bool searchTextContains(String? source, String query) {
  final normalizedQuery = normalizeSearchText(query);
  if (normalizedQuery.isEmpty) return true;
  return normalizeSearchText(source ?? '').contains(normalizedQuery);
}

bool searchAnyContains(String query, Iterable<Object?> values) {
  final normalizedQuery = normalizeSearchText(query);
  if (normalizedQuery.isEmpty) return true;
  return values.any((value) => normalizeSearchText(value?.toString() ?? '').contains(normalizedQuery));
}
