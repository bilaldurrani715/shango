import 'package:flutter_test/flutter_test.dart';
import 'package:shango/services/location_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Local-First Bannu Location Search Tests', () {
    test('Loads 75+ places from local JSON database', () async {
      final places = await LocationService.getLocalPlaces();
      expect(places.length, greaterThanOrEqualTo(75));

      final hasDHQ = places.any((p) => p.name.contains('DHQ'));
      final hasKGN = places.any((p) => p.name.contains('KGN'));
      final hasCantt = places.any((p) => p.name.contains('Cantt'));
      final hasAdda = places.any((p) => p.name.contains('General Bus Stand'));

      expect(hasDHQ, isTrue);
      expect(hasKGN, isTrue);
      expect(hasCantt, isTrue);
      expect(hasAdda, isTrue);
    });

    test('Local search matches "dhq" via searchLocalPlaces', () async {
      final results = await LocationService.searchLocalPlaces('dhq');
      expect(results, isNotEmpty);
      expect(results.first.name, contains('DHQ Hospital'));
    });

    test('Local search matches Urdu and alias keywords (e.g. "lari adda")', () async {
      final results = await LocationService.searchLocalPlaces('lari adda');
      expect(results, isNotEmpty);
      expect(results.first.name, contains('General Bus Stand'));
    });

    test('Sorts local results by proximity to passenger location', () async {
      final townshipPassenger = LatLng(32.9650, 70.6350);
      final results = await LocationService.searchLocalPlaces('township', proximity: townshipPassenger);
      expect(results, isNotEmpty);
      final distFirst = LocationService.getDistanceBetween(townshipPassenger, results.first.location);
      expect(distFirst, lessThan(1000));
    });
  });
}
