import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/features/capture/fuzzy_match.dart';

void main() {
  group('FuzzyMatch String Similarity Tests', () {
    test('matches exact strings with score 1.0', () {
      expect(FuzzyMatch.similarity('Meridian Brothers', 'Meridian Brothers'), 1.0);
    });

    test('fuzzy matches OCR typos in seller entity names', () {
      final entities = [
        'Meridian Brothers',
        'Meridian Distributors',
        'Meridian Gurgaon',
      ];

      final match1 = FuzzyMatch.findBestMatch('Meridian Brothrs', entities, (e) => e);
      expect(match1, 'Meridian Brothers');

      final match2 = FuzzyMatch.findBestMatch('Meridian Distr', entities, (e) => e);
      expect(match2, 'Meridian Distributors');

      final match3 = FuzzyMatch.findBestMatch('DBR Gurgoan', entities, (e) => e);
      expect(match3, 'Meridian Gurgaon');
    });

    test('fuzzy matches OCR buyer names to master buyer list', () {
      final buyers = [
        'AIRPLAZA RETAIL HOLDING PVT LTD',
        'Zepto Limited',
        'KIRANAKART TECHNOLOGIES PVT LTD',
        '212 Bakehouse',
        'SRS VALUE BAZAR',
      ];

      final match1 = FuzzyMatch.findBestMatch('Airplaza Retail Hold', buyers, (b) => b);
      expect(match1, 'AIRPLAZA RETAIL HOLDING PVT LTD');

      final match2 = FuzzyMatch.findBestMatch('Zepto Ltd', buyers, (b) => b);
      expect(match2, 'Zepto Limited');

      final match3 = FuzzyMatch.findBestMatch('212 Bake house', buyers, (b) => b);
      expect(match3, '212 Bakehouse');

      final match4 = FuzzyMatch.findBestMatch('Kiranakart Tech', buyers, (b) => b);
      expect(match4, 'KIRANAKART TECHNOLOGIES PVT LTD');
    });
  });
}
