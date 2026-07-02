import '../../core/models/master_data.dart';

/// Returns the registry entry whose prefix is the longest case-insensitive
/// prefix of [invoiceNumber], or null when nothing matches. Mirrors the
/// backend's ResolveSeriesForInvoiceNumber so the review screen can show the
/// same principal the server will stamp at upload time.
SeriesEntry? detectSeries(String invoiceNumber, List<SeriesEntry> registry) {
  final number = invoiceNumber.trim().toUpperCase();
  if (number.isEmpty) return null;
  SeriesEntry? best;
  for (final entry in registry) {
    final prefix = entry.seriesPrefix.toUpperCase();
    if (prefix.isEmpty || !number.startsWith(prefix)) continue;
    if (best == null ||
        prefix.length > best.seriesPrefix.length) {
      best = entry;
    }
  }
  return best;
}
