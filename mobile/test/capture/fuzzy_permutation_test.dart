import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/features/capture/fuzzy_match.dart';

void main() {
  group('Fuzzy Matching Exhaustive Permutation Tests', () {
    final buyerMasterList = [
      'AIRPLAZA RETAIL HOLDING PVT LTD',
      'Zepto Limited',
      'KIRANAKART TECHNOLOGIES PVT LTD',
      '212 Bakehouse',
      'SRS VALUE BAZAR',
      'SPENCERS RETAIL LTD',
      'SUPERWELL COMTRADE PRIVATE LIMITED',
      'Scootsy Logistics Pvt Ltd',
      'INTELLIHEALTH SOLUTIONS PRIVATE LIMITED',
      'VALUE MART 2',
    ];

    final noisyPermutations = [
      // Typo variations for Airplaza
      ('Airplaza Retail', 'AIRPLAZA RETAIL HOLDING PVT LTD'),
      ('AIRPLAZA RETAIL HOLD', 'AIRPLAZA RETAIL HOLDING PVT LTD'),
      ('airplaza retail holding pvt', 'AIRPLAZA RETAIL HOLDING PVT LTD'),
      ('Airplaza Retal Holding', 'AIRPLAZA RETAIL HOLDING PVT LTD'),

      // Typo variations for Zepto
      ('Zepto Ltd', 'Zepto Limited'),
      ('zepto limited', 'Zepto Limited'),
      ('ZEPTO LIMITED GURGAON', 'Zepto Limited'),
      ('Zepto Limted', 'Zepto Limited'),

      // Typo variations for Kiranakart
      ('Kiranakart Tech', 'KIRANAKART TECHNOLOGIES PVT LTD'),
      ('KIRANAKART TECHNOLOGIES', 'KIRANAKART TECHNOLOGIES PVT LTD'),
      ('kiranakart tech pvt ltd', 'KIRANAKART TECHNOLOGIES PVT LTD'),

      // Typo variations for 212 Bakehouse
      ('212 Bake house', '212 Bakehouse'),
      ('212 bakehouse gurgaon', '212 Bakehouse'),

      // Typo variations for Spencers
      ('Spencers Retail', 'SPENCERS RETAIL LTD'),
      ('SPENCERS RETAIL LIMITED', 'SPENCERS RETAIL LTD'),

      // Typo variations for Scootsy
      ('Scootsy Logistics', 'Scootsy Logistics Pvt Ltd'),
      ('scootsy logistics pvt', 'Scootsy Logistics Pvt Ltd'),

      // Typo variations for Intellihealth
      ('Intellihealth Solutions', 'INTELLIHEALTH SOLUTIONS PRIVATE LIMITED'),
      ('INTELLIHEALTH SOL PRIVATE LTD', 'INTELLIHEALTH SOLUTIONS PRIVATE LIMITED'),
    ];

    for (final (noisyQuery, expectedMaster) in noisyPermutations) {
      test('Noisy OCR query "$noisyQuery" correctly matches "$expectedMaster"', () {
        final match = FuzzyMatch.findBestMatch(
          noisyQuery,
          buyerMasterList,
          (b) => b,
          minScore: 0.45,
        );
        expect(match, expectedMaster);
      });
    }

    test('Non-matching random string returns null', () {
      final match = FuzzyMatch.findBestMatch(
        'XYZ Random Unrelated Shop 9999',
        buyerMasterList,
        (b) => b,
        minScore: 0.55,
      );
      expect(match, isNull);
    });

    test('Empty query string returns null', () {
      final match = FuzzyMatch.findBestMatch(
        '',
        buyerMasterList,
        (b) => b,
      );
      expect(match, isNull);
    });
  });
}
