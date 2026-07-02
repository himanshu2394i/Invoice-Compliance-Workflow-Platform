import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/core/models/master_data.dart';
import 'package:invoice_capture/features/capture/series_detect.dart';

SeriesEntry _entry(String prefix, {String? principalName}) => SeriesEntry(
      id: prefix,
      seriesPrefix: prefix,
      entityId: null,
      entityName: null,
      principalId: principalName == null ? null : 'pid-$principalName',
      principalName: principalName,
    );

void main() {
  final registry = [
    _entry('CAD', principalName: 'Mondelez'),
    _entry('RE'),
    _entry('REHIN', principalName: 'Reckitt'),
    _entry('HAL', principalName: 'Haleon'),
  ];

  test('matches an exact prefix', () {
    final hit = detectSeries('CAD/15442', registry);
    expect(hit?.seriesPrefix, 'CAD');
    expect(hit?.principalName, 'Mondelez');
  });

  test('longest prefix wins over a shorter one', () {
    final hit = detectSeries('REHIN000800', registry);
    expect(hit?.seriesPrefix, 'REHIN');
  });

  test('matching is case-insensitive', () {
    final hit = detectSeries('hal08222', registry);
    expect(hit?.seriesPrefix, 'HAL');
  });

  test('no match returns null', () {
    expect(detectSeries('ZZTOP123', registry), isNull);
    expect(detectSeries('', registry), isNull);
    expect(detectSeries('CAD/1', <SeriesEntry>[]), isNull);
  });
}
