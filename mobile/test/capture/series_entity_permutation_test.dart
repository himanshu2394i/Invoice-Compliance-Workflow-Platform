import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/core/models/master_data.dart';
import 'package:invoice_capture/features/capture/series_detect.dart';

void main() {
  group('Series to Seller Entity Permutation Tests', () {
    const registry = [
      SeriesEntry(id: '1', seriesPrefix: 'CAD', entityName: 'Meridian Brothers'),
      SeriesEntry(id: '2', seriesPrefix: 'HAL', entityName: 'Meridian Distributors'),
      SeriesEntry(id: '3', seriesPrefix: 'MORDE', entityName: 'Meridian Brothers'),
      SeriesEntry(id: '4', seriesPrefix: 'NIV', entityName: 'Meridian Brothers'),
      SeriesEntry(id: '5', seriesPrefix: 'DBR', entityName: 'Meridian Brothers'),
      SeriesEntry(id: '6', seriesPrefix: 'IN00', entityName: 'Meridian Gurgaon'),
      SeriesEntry(id: '7', seriesPrefix: 'REHIN', entityName: 'Meridian Gurgaon'),
      SeriesEntry(id: '8', seriesPrefix: 'HYGIN', entityName: 'Meridian Gurgaon'),
    ];

    const entities = [
      ('Meridian Brothers', '06AAAAA0003A1Z3'),
      ('Meridian Distributors', '06AAAAA0015A1ZF'),
      ('Meridian Gurgaon', '06AAAAA0017A1ZH'),
    ];

    String resolveEntityGstin(String invoiceNum) {
      final hit = detectSeries(invoiceNum, registry);
      if (hit == null) return entities.first.$2;

      final prefix = hit.seriesPrefix.toUpperCase();
      if (hit.entityName != null && hit.entityName!.isNotEmpty) {
        final match = entities.where((e) => e.$1.toUpperCase() == hit.entityName!.toUpperCase()).toList();
        if (match.isNotEmpty) return match.first.$2;
      }

      if (prefix.startsWith('HAL')) return '06AAAAA0015A1ZF';
      if (prefix.startsWith('IN') || prefix.startsWith('REH') || prefix.startsWith('HYG')) return '06AAAAA0017A1ZH';
      return '06AAAAA0003A1Z3';
    }

    final permutations = [
      // CAD Series -> Meridian Brothers
      ('CAD/15442', 'CAD', '06AAAAA0003A1Z3'),
      ('cad/15455', 'CAD', '06AAAAA0003A1Z3'),
      ('Cad15462', 'CAD', '06AAAAA0003A1Z3'),
      
      // HAL Series -> Meridian Distributors
      ('HAL08221', 'HAL', '06AAAAA0015A1ZF'),
      ('hal08244', 'HAL', '06AAAAA0015A1ZF'),
      ('HAL/2026/001', 'HAL', '06AAAAA0015A1ZF'),
      
      // MORDE Series -> Meridian Brothers
      ('MORDE0031289', 'MORDE', '06AAAAA0003A1Z3'),
      ('morde0099', 'MORDE', '06AAAAA0003A1Z3'),
      
      // NIV Series -> Meridian Brothers
      ('NIV3594182600261', 'NIV', '06AAAAA0003A1Z3'),
      ('niv3594182600267', 'NIV', '06AAAAA0003A1Z3'),
      
      // DBR Series -> Meridian Brothers
      ('DBR07283', 'DBR', '06AAAAA0003A1Z3'),
      ('dbr07285', 'DBR', '06AAAAA0003A1Z3'),
      
      // IN00 Series -> Meridian Gurgaon
      ('IN009988', 'IN00', '06AAAAA0017A1ZH'),
      ('in001234', 'IN00', '06AAAAA0017A1ZH'),
      
      // REHIN Series -> Meridian Gurgaon
      ('REHIN000797', 'REHIN', '06AAAAA0017A1ZH'),
      ('rehin000800', 'REHIN', '06AAAAA0017A1ZH'),
      
      // HYGIN Series -> Meridian Gurgaon
      ('HYGIN014569', 'HYGIN', '06AAAAA0017A1ZH'),
      ('hygin014592', 'HYGIN', '06AAAAA0017A1ZH'),
    ];

    for (final (invNum, expectedPrefix, expectedGstin) in permutations) {
      test('Permutation invoice $invNum maps to series prefix $expectedPrefix and entity GSTIN $expectedGstin', () {
        final hit = detectSeries(invNum, registry);
        expect(hit, isNotNull);
        expect(hit!.seriesPrefix, expectedPrefix);

        final gstin = resolveEntityGstin(invNum);
        expect(gstin, expectedGstin);
      });
    }
  });
}
