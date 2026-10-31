import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteDetails {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const RouteDetails({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

class PlaceItem {
  final String name;
  final String subtitle;
  final LatLng location;
  final String? category;
  final List<String> keywords;

  const PlaceItem({
    required this.name,
    this.subtitle = '',
    required this.location,
    this.category,
    this.keywords = const [],
  });

  factory PlaceItem.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num).toDouble();
    final lng = (json['lng'] as num).toDouble();
    final kw = (json['keywords'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return PlaceItem(
      name: json['name'] as String,
      subtitle: (json['subtitle'] ?? '') as String,
      location: LatLng(lat, lng),
      category: json['category'] as String?,
      keywords: kw,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'subtitle': subtitle,
    'lat': location.latitude,
    'lng': location.longitude,
    if (category != null) 'category': category,
    'keywords': keywords,
  };
}

class _ScoredPlace {
  final PlaceItem place;
  final int score;
  const _ScoredPlace({required this.place, required this.score});
}

class LocationService {
  // Default fallback location (e.g. Bannu / Peshawar area)
  static const LatLng defaultLocation = LatLng(32.9861, 70.6042);

  /// Request GPS permission and get the current user location
  static Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled on device.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied.');
      return null;
    }

    // 1. Try high accuracy fresh GPS position
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('Error getting live position, falling back: $e');
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) return lastPos;
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 6),
          ),
        );
      } catch (_) {
        return null;
      }
    }
  }

  /// Live GPS position stream for real-time tracking
  static Stream<Position> getPositionStream({int distanceFilter = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    );
  }

  static const String googleApiKey = 'AIzaSyCi3dvlvAH_y1nIy1sZ9shgCbXH70TZcXc';

  static const List<PlaceItem> localLandmarks = [
    // Major Bannu City Landmarks & Gates
    PlaceItem(name: 'Bannu Cantt', subtitle: 'Cantt Area, Bannu, KP', location: LatLng(32.9912, 70.6054)),
    PlaceItem(name: 'Main Bazaar Bannu', subtitle: 'Central Market, Bannu City', location: LatLng(32.9845, 70.6025)),
    PlaceItem(name: 'Chowk Bazaar Bannu', subtitle: 'Historic Market Center, Bannu', location: LatLng(32.9855, 70.6040)),
    PlaceItem(name: 'Preedy Gate Bannu', subtitle: 'Old Walled City, Bannu', location: LatLng(32.9839, 70.6020)),
    PlaceItem(name: 'Mandan Gate Bannu', subtitle: 'Mandan Road Entrance, Bannu', location: LatLng(32.9870, 70.6045)),
    PlaceItem(name: 'Hinjal Gate Bannu', subtitle: 'Historic City Gate, Bannu', location: LatLng(32.9860, 70.6060)),
    PlaceItem(name: 'Lakki Gate Bannu', subtitle: 'Lakki Road Crossing, Bannu', location: LatLng(32.9820, 70.6050)),
    PlaceItem(name: 'Qasaban Gate Bannu', subtitle: 'Bannu City Gate', location: LatLng(32.9840, 70.6010)),
    PlaceItem(name: 'Sukari Bazaar Bannu', subtitle: 'Old Sukari Market, Bannu', location: LatLng(32.9850, 70.6030)),
    PlaceItem(name: 'Milad Park Bannu', subtitle: 'Recreation Park, Bannu City', location: LatLng(32.9875, 70.6015)),
    PlaceItem(name: 'Sports Complex Bannu', subtitle: 'Sports Stadium, Bannu Cantt', location: LatLng(32.9890, 70.6110)),

    // Hospitals & Healthcare
    PlaceItem(name: 'DHQ Hospital Bannu', subtitle: 'District Headquarters Hospital, DI Khan Road, Bannu', location: LatLng(32.954611, 70.648167), keywords: ['dhq', 'ghq', 'hospital']),
    PlaceItem(name: 'Old DHQ / Civil Hospital Bannu', subtitle: 'Old City Hospital, Mandan / Railway Road, Bannu', location: LatLng(32.9831, 70.6062), keywords: ['old dhq', 'civil hospital']),
    PlaceItem(name: 'Khalifa Gul Nawaz Hospital (KGN)', subtitle: 'Teaching Hospital, Bannu Township, Kohat Road, Bannu', location: LatLng(33.0185, 70.6968), keywords: ['kgn', 'khalifa gul nawaz', 'hospital', 'township']),
    PlaceItem(name: 'Bannu Medical College (BMC)', subtitle: 'KGN Complex, DI Khan Road, Bannu', location: LatLng(32.9740, 70.6270)),
    PlaceItem(name: 'Women & Children Hospital Bannu', subtitle: 'Cantt Road, Bannu', location: LatLng(32.9880, 70.6090)),
    PlaceItem(name: 'Combined Military Hospital (CMH) Bannu', subtitle: 'Bannu Cantt', location: LatLng(32.9930, 70.6070)),

    // Transport & Terminals
    PlaceItem(name: 'General Bus Stand Bannu', subtitle: 'Main Lari Adda, Bannu', location: LatLng(32.9785, 70.6120)),
    PlaceItem(name: 'Bannu Railway Station', subtitle: 'Railway Road, Bannu', location: LatLng(32.9882, 70.6080)),
    PlaceItem(name: 'Bannu Airport', subtitle: 'Civil Aviation Airport, Bannu', location: LatLng(32.9723, 70.5281)),
    PlaceItem(name: 'Miran Shah Adda Bannu', subtitle: 'North Waziristan Passenger Terminal, Bannu', location: LatLng(32.9810, 70.5980)),
    PlaceItem(name: 'DI Khan Adda Bannu', subtitle: 'DI Khan Bus Stand, Bannu', location: LatLng(32.9720, 70.6150)),
    PlaceItem(name: 'Kohat Adda Bannu', subtitle: 'Kohat Road Terminal, Bannu', location: LatLng(32.9950, 70.6130)),

    // Education & Universities
    PlaceItem(name: 'University of Science and Technology Bannu (USTB)', subtitle: 'Main Campus, DI Khan Road, Bannu', location: LatLng(32.9765, 70.6255)),
    PlaceItem(name: 'Post Graduate College Bannu', subtitle: 'College Road, Bannu', location: LatLng(32.9815, 70.6085)),
    PlaceItem(name: 'Commerce College Bannu', subtitle: 'Township Road, Bannu', location: LatLng(32.9680, 70.6300)),
    PlaceItem(name: 'Army Public School (APS) Bannu', subtitle: 'Bannu Cantt', location: LatLng(32.9940, 70.6030)),

    // Key Roads & Townships
    PlaceItem(name: 'Township Bannu', subtitle: 'Bannu Township Housing Scheme', location: LatLng(32.9650, 70.6350)),
    PlaceItem(name: 'Kohat Road Bypass', subtitle: 'Bypass Chowk, Bannu', location: LatLng(33.0010, 70.6180)),
    PlaceItem(name: 'Miran Shah Road Bannu', subtitle: 'Miran Shah Highway, Bannu', location: LatLng(32.9820, 70.5940)),
    PlaceItem(name: 'DI Khan Road Bannu', subtitle: 'Indus Highway Link, Bannu', location: LatLng(32.9690, 70.6220)),
    PlaceItem(name: 'Railway Road Bannu', subtitle: 'Commercial Avenue, Bannu', location: LatLng(32.9870, 70.6070)),

    // Government & Administration
    PlaceItem(name: 'District Courts / Sessions Court Bannu', subtitle: 'Judicial Complex, Bannu', location: LatLng(32.9895, 70.6065)),
    PlaceItem(name: 'Deputy Commissioner (DC) Office Bannu', subtitle: 'Civil Secretariat, Bannu Cantt', location: LatLng(32.9920, 70.6040)),
    PlaceItem(name: 'Police Lines Bannu', subtitle: 'Cantt Area, Bannu', location: LatLng(32.9880, 70.6040)),
  ];

  static List<PlaceItem>? _cachedLocalPlaces;

  /// Load and cache the complete Bannu places database from assets/data/bannu_places.json
  /// Returns 75+ curated Bannu landmarks with instant 0ms access and zero Google API quota cost.
  static Future<List<PlaceItem>> getLocalPlaces() async {
    if (_cachedLocalPlaces != null && _cachedLocalPlaces!.isNotEmpty) {
      return _cachedLocalPlaces!;
    }
    try {
      final jsonString = await rootBundle.loadString('assets/data/bannu_places.json');
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is List) {
        final places = decoded
            .map((e) => PlaceItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _cachedLocalPlaces = places;
        return places;
      }
    } catch (e) {
      debugPrint('Failed to load local bannu_places.json: $e');
    }
    return localLandmarks;
  }

  /// Reverse geocode coordinates to get Road, Area, and City name
  static Future<String> getAddressFromCoordinates(LatLng loc) async {
    // 1. Try Google Geocoding API first
    try {
      final googleUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${loc.latitude},${loc.longitude}&key=$googleApiKey',
      );
      final gRes = await http.get(googleUrl).timeout(const Duration(seconds: 4));
      if (gRes.statusCode == 200) {
        final gData = jsonDecode(gRes.body);
        if (gData['status'] == 'OK') {
          final results = gData['results'] as List?;
          if (results != null && results.isNotEmpty) {
            final humanAddress = _pickHumanFriendlyAddress(results);
            if (humanAddress.isNotEmpty) {
              return humanAddress;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Google reverse geocode notice: $e');
    }

    // 2. Fallback to OpenStreetMap Nominatim
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=json&lat=${loc.latitude}&lon=${loc.longitude}&zoom=18&addressdetails=1',
    );
    try {
      final res = await http.get(url, headers: {'User-Agent': 'ShanGoRideApp/1.0'}).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final road = address['road'] ?? address['neighbourhood'] ?? address['suburb'];
          final city = address['city'] ?? address['town'] ?? address['village'] ?? address['county'] ?? 'Bannu';
          if (road != null) {
            return '$road, $city';
          }
          return city.toString();
        }
        final displayName = data['display_name'] as String?;
        if (displayName != null) {
          final parts = displayName.split(',');
          return parts.take(2).join(', ').trim();
        }
      }
    } catch (e) {
      debugPrint('Reverse geocode notice: $e');
    }
    return 'Current Location (${loc.latitude.toStringAsFixed(3)}, ${loc.longitude.toStringAsFixed(3)})';
  }

  /// Extracts human-friendly street/area/city name and filters out cryptic Plus Codes (e.g. XJM4+49F)
  static String _pickHumanFriendlyAddress(List<dynamic> results) {
    final plusCodeRegex = RegExp(r'[A-Z0-9]{2,8}\+[A-Z0-9]{2,}');

    // 1. Prioritize results whose formatted_address originally has NO Plus Code and is a specific street/place/area
    for (var r in results) {
      final formatted = r['formatted_address'] as String? ?? '';
      final types = (r['types'] as List? ?? []).cast<String>();

      if (types.contains('plus_code') || (types.contains('country') && types.length <= 2)) {
        continue;
      }

      if (!plusCodeRegex.hasMatch(formatted)) {
        String cleaned = formatted.replaceAll(RegExp(r',\s*\d{5}'), '').trim();
        if (cleaned.endsWith(', Pakistan')) {
          cleaned = cleaned.substring(0, cleaned.length - ', Pakistan'.length).trim();
        }
        if (types.any((t) => [
              'street_address',
              'subpremise',
              'premise',
              'route',
              'neighborhood',
              'sublocality',
              'sublocality_level_1',
              'administrative_area_level_5'
            ].contains(t))) {
          return cleaned;
        }
      }
    }

    // 2. Check any remaining result without Plus Code (e.g. locality or neighborhood)
    for (var r in results) {
      final formatted = r['formatted_address'] as String? ?? '';
      if (!plusCodeRegex.hasMatch(formatted)) {
        String cleaned = formatted.replaceAll(RegExp(r',\s*\d{5}'), '').trim();
        if (cleaned.endsWith(', Pakistan')) {
          cleaned = cleaned.substring(0, cleaned.length - ', Pakistan'.length).trim();
        }
        if (cleaned.isNotEmpty && cleaned != 'Pakistan') {
          return cleaned;
        }
      }
    }

    // 3. Fallback: strip Plus Code prefix (e.g. "XJM4+49F, Bannu" -> "Bannu")
    for (var r in results) {
      final formatted = r['formatted_address'] as String? ?? '';
      String cleaned = formatted.replaceAll(RegExp(r'^[A-Z0-9]{2,8}\+[A-Z0-9]{2,}\s*,?\s*'), '').trim();
      cleaned = cleaned.replaceAll(RegExp(r',\s*\d{5}'), '').trim();
      if (cleaned.endsWith(', Pakistan')) {
        cleaned = cleaned.substring(0, cleaned.length - ', Pakistan'.length).trim();
      }
      if (cleaned.isNotEmpty && !plusCodeRegex.hasMatch(cleaned) && cleaned != 'Pakistan') {
        return cleaned;
      }
    }

    return '';
  }

  /// Search Google Places Text Search API with proximity bias around existing location
  static Future<List<PlaceItem>> _searchGooglePlaces(
    String cleanQuery, {
    required LatLng proximity,
  }) async {
    // 1. Try Places API (New) - POST /v1/places:searchText
    try {
      final newUrl = Uri.parse('https://places.googleapis.com/v1/places:searchText');
      final headers = {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': googleApiKey,
        'X-Goog-FieldMask': 'places.displayName,places.formattedAddress,places.location',
      };

      Future<List<PlaceItem>> queryNewApi(String text) async {
        final res = await http.post(
          newUrl,
          headers: headers,
          body: jsonEncode({
            'textQuery': text,
            'regionCode': 'PK',
            'locationBias': {
              'circle': {
                'center': {'latitude': proximity.latitude, 'longitude': proximity.longitude},
                'radius': 35000.0,
              },
            },
          }),
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final placesList = data['places'] as List?;
          if (placesList != null && placesList.isNotEmpty) {
            final places = <PlaceItem>[];
            for (final item in placesList) {
              final displayNameMap = item['displayName'] as Map<String, dynamic>?;
              final name = (displayNameMap?['text'] as String?) ?? 'Place';
              final address = (item['formattedAddress'] as String?) ?? '';
              final loc = item['location'] as Map<String, dynamic>?;
              if (loc != null) {
                final lat = (loc['latitude'] as num?)?.toDouble();
                final lng = (loc['longitude'] as num?)?.toDouble();
                if (lat != null && lng != null) {
                  places.add(
                    PlaceItem(
                      name: name,
                      subtitle: address.isNotEmpty ? address : name,
                      location: LatLng(lat, lng),
                    ),
                  );
                }
              }
            }
            return places;
          }
        }
        return [];
      }

      var places = await queryNewApi(cleanQuery);
      if (places.isNotEmpty) return places;
    } catch (e) {
      debugPrint('Places API (New) notice: $e');
    }

    // 2. Fallback to Classic Places API - GET /maps/api/place/textsearch/json
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=${Uri.encodeComponent(cleanQuery)}&location=${proximity.latitude},${proximity.longitude}&radius=35000&key=$googleApiKey',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final status = data['status'] as String?;
        if (status == 'OK') {
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            final places = <PlaceItem>[];
            for (final item in results) {
              final name = item['name'] as String? ?? 'Place';
              final address = item['formatted_address'] as String? ?? '';
              final geom = item['geometry']?['location'] as Map<String, dynamic>?;
              if (geom != null) {
                final lat = (geom['lat'] as num?)?.toDouble();
                final lng = (geom['lng'] as num?)?.toDouble();
                if (lat != null && lng != null) {
                  places.add(
                    PlaceItem(
                      name: name,
                      subtitle: address.isNotEmpty ? address : name,
                      location: LatLng(lat, lng),
                    ),
                  );
                }
              }
            }
            if (places.isNotEmpty) return places;
          }
        }
      }
    } catch (e) {
      debugPrint('Classic Places search error: $e');
    }
    return [];
  }

  /// Query OpenStreetMap Nominatim with proximity bounding box around existing location
  static Future<List<PlaceItem>> _searchNominatim(
    String cleanQuery, {
    required LatLng proximity,
  }) async {
    final nominatimResults = <PlaceItem>[];
    // Create bounding box roughly 40km around passenger's existing location
    final minLon = proximity.longitude - 0.35;
    final maxLon = proximity.longitude + 0.35;
    final minLat = proximity.latitude - 0.35;
    final maxLat = proximity.latitude + 0.35;

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(cleanQuery)}&format=json&addressdetails=1&countrycodes=pk&limit=15&viewbox=$minLon,$maxLat,$maxLon,$minLat',
    );

    try {
      final res = await http.get(
        url,
        headers: {'User-Agent': 'ShanGoRideApp/1.0'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);

        for (final item in list) {
          final lat = double.tryParse(item['lat']?.toString() ?? '');
          final lon = double.tryParse(item['lon']?.toString() ?? '');
          if (lat != null && lon != null) {
            final displayName = item['display_name'] as String? ?? '';
            final address = item['address'] as Map<String, dynamic>?;

            String title = '';
            String subtitle = '';

            if (address != null) {
              title = address['amenity'] ??
                  address['shop'] ??
                  address['tourism'] ??
                  address['road'] ??
                  address['neighbourhood'] ??
                  address['suburb'] ??
                  address['village'] ??
                  address['town'] ??
                  address['city'] ??
                  '';

              final cityOrDistrict = address['city'] ??
                  address['town'] ??
                  address['village'] ??
                  address['county'] ??
                  address['state_district'] ??
                  '';
              final state = address['state'] ?? '';

              final subParts = <String>[];
              if (address['suburb'] != null && address['suburb'] != title) {
                subParts.add(address['suburb']);
              }
              if (cityOrDistrict.isNotEmpty && cityOrDistrict != title) {
                subParts.add(cityOrDistrict);
              }
              if (state.isNotEmpty) {
                subParts.add(state);
              }

              subtitle = subParts.join(', ');
            }

            if (title.isEmpty) {
              final parts = displayName.split(',');
              title = parts.isNotEmpty ? parts.first.trim() : 'Place';
              subtitle = parts.length > 1
                  ? parts.skip(1).take(3).join(', ').trim()
                  : displayName;
            }

            if (subtitle.isEmpty) {
              subtitle = displayName;
            }

            nominatimResults.add(
              PlaceItem(
                name: title,
                subtitle: subtitle,
                location: LatLng(lat, lon),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Search places notice: $e');
    }

    return nominatimResults;
  }

  /// Search places, streets, and areas prioritizing online search:
  /// 1. Searches Google Places API (biased to passenger's existing coordinates / Bannu).
  /// 2. If Google Places has no results or quota 429 is exhausted, falls back to OpenStreetMap Nominatim.
  /// 3. All results are sorted by straight-line distance from passenger's existing location.
  static Future<List<PlaceItem>> searchPlaces(
    String query, {
    LatLng? proximity,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final center = proximity ?? defaultLocation;
    final combinedResults = <PlaceItem>[];
    final seenNames = <String>{};

    // 1. Primary: Google Places API Search (Biased to passenger's existing coordinates)
    try {
      final googleResults = await _searchGooglePlaces(cleanQuery, proximity: center);
      for (final place in googleResults) {
        final key = place.name.toLowerCase();
        if (!seenNames.contains(key)) {
          seenNames.add(key);
          combinedResults.add(place);
        }
      }
    } catch (e) {
      debugPrint('Google Places search error: $e');
    }

    // 2. Secondary: Fallback to OpenStreetMap Nominatim (if Google has no results or quota 429 is exhausted)
    if (combinedResults.length < 5) {
      try {
        final nominatimResults = await _searchNominatim(cleanQuery, proximity: center);
        for (final place in nominatimResults) {
          final key = place.name.toLowerCase();
          if (!seenNames.contains(key)) {
            seenNames.add(key);
            combinedResults.add(place);
          }
        }
      } catch (e) {
        debugPrint('Nominatim search notice: $e');
      }
    }

    // 3. Sort all results by straight-line distance from passenger's existing location
    if (proximity != null && combinedResults.length > 1) {
      combinedResults.sort((a, b) {
        final distA = getDistanceBetween(proximity, a.location);
        final distB = getDistanceBetween(proximity, b.location);
        return distA.compareTo(distB);
      });
    }

    return combinedResults;
  }

  /// Search local Bannu database (available for instant local lookup once JSON curation is complete)
  static Future<List<PlaceItem>> searchLocalPlaces(
    String query, {
    LatLng? proximity,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final cleanLower = cleanQuery.toLowerCase();
    final combinedResults = <PlaceItem>[];
    final seenNames = <String>{};

    final localList = await getLocalPlaces();
    final scoredLocal = <_ScoredPlace>[];

    final queryTokens = cleanLower
        .split(RegExp(r'[\s,.-]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    for (final place in localList) {
      final nameLower = place.name.toLowerCase();
      final subLower = place.subtitle.toLowerCase();
      int score = 0;

      if (nameLower == cleanLower) {
        score += 200;
      } else if (nameLower.startsWith(cleanLower)) {
        score += 120;
      } else if (nameLower.contains(cleanLower)) {
        score += 90;
      }

      if (subLower.contains(cleanLower)) {
        score += 40;
      }

      if (place.category != null && place.category!.toLowerCase().contains(cleanLower)) {
        score += 50;
      }

      for (final kw in place.keywords) {
        final kwLower = kw.toLowerCase();
        if (kwLower == cleanLower) {
          score += 150;
          break;
        } else if (kwLower.startsWith(cleanLower)) {
          score += 100;
          break;
        } else if (kwLower.contains(cleanLower)) {
          score += 80;
          break;
        }
      }

      if (queryTokens.length > 1) {
        int tokenMatches = 0;
        for (final token in queryTokens) {
          final inName = nameLower.contains(token);
          final inSub = subLower.contains(token);
          final inCat = place.category != null && place.category!.toLowerCase().contains(token);
          final inKw = place.keywords.any((k) => k.toLowerCase().contains(token));
          if (inName || inSub || inCat || inKw) {
            tokenMatches++;
          }
        }
        if (tokenMatches == queryTokens.length) {
          score += 110;
        } else if (tokenMatches > 0) {
          score += tokenMatches * 25;
        }
      }

      if (score > 0) {
        scoredLocal.add(_ScoredPlace(place: place, score: score));
      }
    }

    if (scoredLocal.isNotEmpty) {
      scoredLocal.sort((a, b) {
        if (a.score != b.score) {
          return b.score.compareTo(a.score);
        }
        if (proximity != null) {
          final distA = getDistanceBetween(proximity, a.place.location);
          final distB = getDistanceBetween(proximity, b.place.location);
          return distA.compareTo(distB);
        }
        return 0;
      });

      for (final item in scoredLocal) {
        final key = item.place.name.toLowerCase();
        if (!seenNames.contains(key)) {
          seenNames.add(key);
          combinedResults.add(item.place);
        }
      }
    }

    return combinedResults;
  }

  /// Calculate straight-line distance in meters between two coordinates
  static double getDistanceBetween(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  /// Format distance into readable String (e.g. "450 m" or "3.2 km")
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Format duration into readable String (e.g. "8 mins" or "1h 15m")
  static String formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins <= 1) return '1 min';
    if (mins < 60) return '$mins mins';
    final hours = mins ~/ 60;
    final remMins = mins % 60;
    return remMins > 0 ? '${hours}h ${remMins}m' : '${hours}h';
  }

  /// Fetch the optimal, shortest, and most direct route polylines, distance, and duration.
  /// Evaluates both motorcycle/two-wheeler and road routing in parallel to pick the shortest path like Google Maps.
  static Future<RouteDetails> getRouteDetails(LatLng start, LatLng end) async {
    final bikeUrl = Uri.parse(
      'https://routing.openstreetmap.de/routed-bike/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
    );
    final carUrl = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
    );

    try {
      final responses = await Future.wait([
        http.get(bikeUrl).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('', 500)),
        http.get(carUrl).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('', 500)),
      ]);

      Map<String, dynamic>? bikeRoute;
      Map<String, dynamic>? carRoute;

      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          bikeRoute = routes[0];
        }
      }

      if (responses[1].statusCode == 200) {
        final data = jsonDecode(responses[1].body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          carRoute = routes[0];
        }
      }

      final bikeDist = (bikeRoute?['distance'] as num?)?.toDouble();
      final carDist = (carRoute?['distance'] as num?)?.toDouble();

      // Automatically select the shortest, most direct route
      Map<String, dynamic>? chosenRoute;
      if (bikeDist != null && carDist != null) {
        chosenRoute = (bikeDist <= carDist) ? bikeRoute : carRoute;
      } else {
        chosenRoute = bikeRoute ?? carRoute;
      }

      if (chosenRoute != null) {
        final coordinates = chosenRoute['geometry']?['coordinates'] as List?;
        final distance = (chosenRoute['distance'] as num?)?.toDouble() ?? getDistanceBetween(start, end);

        final points = coordinates != null
            ? coordinates.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList()
            : <LatLng>[start, end];

        double totalDistance = distance;

        // Connect any gap between the start coordinate and the first mapped road point
        if (points.isNotEmpty) {
          final startGap = getDistanceBetween(start, points.first);
          if (startGap > 8) {
            points.insert(0, start);
            totalDistance += startGap;
          }

          // Connect any gap between the last mapped road point and the destination pin
          final endGap = getDistanceBetween(points.last, end);
          if (endGap > 8) {
            points.add(end);
            totalDistance += endGap;
          }
        } else {
          points.addAll([start, end]);
        }

        final duration = (chosenRoute['duration'] as num?)?.toDouble() ?? (totalDistance / 8.33);

        return RouteDetails(
          points: points,
          distanceMeters: totalDistance,
          durationSeconds: duration,
        );
      }
    } catch (e) {
      debugPrint('Optimal Route fetch notice: $e');
    }

    final straightDist = getDistanceBetween(start, end);
    return RouteDetails(
      points: [start, end],
      distanceMeters: straightDist,
      durationSeconds: straightDist / 8.33, // ~30 km/h average speed in city
    );
  }

  /// Helper backwards compatible method
  static Future<List<LatLng>> getRoutePoints(LatLng start, LatLng end) async {
    final details = await getRouteDetails(start, end);
    return details.points;
  }

  /// Extracts coordinates and human-readable address from WhatsApp Google Maps links,
  /// short links (maps.app.goo.gl), HTML body staticmap center, or raw coordinate strings.
  static Future<PlaceItem?> parseLocationFromMapsLink(String input) async {
    if (input.trim().isEmpty) return null;
    final trimmed = input.trim();

    try {
      // 1. Check for URL within the text
      final urlRegExp = RegExp(r'https?:\/\/[^\s]+');
      final match = urlRegExp.firstMatch(trimmed);

      String urlToAnalyze = match != null ? match.group(0)! : trimmed;
      String htmlBody = '';
      LatLng? extractedLoc;

      // If it is a short link or maps link, resolve redirects and fetch body
      if (urlToAnalyze.contains('maps.app.goo.gl') ||
          urlToAnalyze.contains('goo.gl/maps') ||
          urlToAnalyze.contains('google.com/maps') ||
          urlToAnalyze.contains('maps.google.com')) {
        try {
          final request = http.Request('GET', Uri.parse(urlToAnalyze))
            ..headers['User-Agent'] =
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
            ..followRedirects = true
            ..maxRedirects = 10;

          final streamedRes = await request.send().timeout(const Duration(seconds: 10));
          final finalUrl = streamedRes.request?.url.toString() ?? '';
          if (finalUrl.isNotEmpty) {
            urlToAnalyze = finalUrl;
          }
          final res = await http.Response.fromStream(streamedRes);
          htmlBody = res.body;
        } catch (e) {
          debugPrint('Error resolving short URL: $e');
        }
      }

      // 2. Try regex extraction for coordinates across URL and HTML response body

      // Pattern 1: center=lat%2Clng or center=lat,lng (from staticmap meta tags in HTML body)
      if (htmlBody.isNotEmpty) {
        final centerMatch = RegExp(r'center=(-?\d{1,2}\.\d+)(?:%2C|,)(-?\d{1,3}\.\d+)').firstMatch(htmlBody);
        if (centerMatch != null) {
          final lat = double.tryParse(centerMatch.group(1)!);
          final lng = double.tryParse(centerMatch.group(2)!);
          if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
            extractedLoc = LatLng(lat, lng);
          }
        }
      }

      // Pattern 2: @lat,lng (e.g. /@33.99812,71.55632,15z)
      if (extractedLoc == null) {
        final atMatch = RegExp(r'@(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(urlToAnalyze) ??
            (htmlBody.isNotEmpty ? RegExp(r'@(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(htmlBody) : null);
        if (atMatch != null) {
          final lat = double.tryParse(atMatch.group(1)!);
          final lng = double.tryParse(atMatch.group(2)!);
          if (lat != null && lng != null) extractedLoc = LatLng(lat, lng);
        }
      }

      // Pattern 3: q=lat,lng or query=lat,lng or ll=lat,lng or daddr=lat,lng or destination=lat,lng
      if (extractedLoc == null) {
        final queryMatch = RegExp(r'(?:[?&](?:q|query|ll|daddr|destination)=)(-?\d{1,2}\.\d+)[,%2C\s]+(-?\d{1,3}\.\d+)').firstMatch(urlToAnalyze);
        if (queryMatch != null) {
          final lat = double.tryParse(queryMatch.group(1)!);
          final lng = double.tryParse(queryMatch.group(2)!);
          if (lat != null && lng != null) extractedLoc = LatLng(lat, lng);
        }
      }

      // Pattern 4: /place/lat,lng or /place/lat+lng
      if (extractedLoc == null) {
        final placeMatch = RegExp(r'\/place\/(-?\d{1,2}\.\d+)[\+,%2C\s]+(-?\d{1,3}\.\d+)').firstMatch(urlToAnalyze);
        if (placeMatch != null) {
          final lat = double.tryParse(placeMatch.group(1)!);
          final lng = double.tryParse(placeMatch.group(2)!);
          if (lat != null && lng != null) extractedLoc = LatLng(lat, lng);
        }
      }

      // Pattern 5: Protobuf coordinates in HTML body: !2d(lng)!3d(lat) or !3d(lat)!4d(lng)
      if (extractedLoc == null && htmlBody.isNotEmpty) {
        final pbLngLat = RegExp(r'!2d(-?\d{1,3}\.\d+)!3d(-?\d{1,2}\.\d+)').firstMatch(htmlBody);
        if (pbLngLat != null) {
          final lng = double.tryParse(pbLngLat.group(1)!);
          final lat = double.tryParse(pbLngLat.group(2)!);
          if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
            extractedLoc = LatLng(lat, lng);
          }
        }
        if (extractedLoc == null) {
          final pbLatLng = RegExp(r'!3d(-?\d{1,2}\.\d+)!4d(-?\d{1,3}\.\d+)').firstMatch(htmlBody);
          if (pbLatLng != null) {
            final lat = double.tryParse(pbLatLng.group(1)!);
            final lng = double.tryParse(pbLatLng.group(2)!);
            if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
              extractedLoc = LatLng(lat, lng);
            }
          }
        }
      }

      // Pattern 6: geo:lat,lng
      if (extractedLoc == null) {
        final geoMatch = RegExp(r'geo:(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)').firstMatch(urlToAnalyze);
        if (geoMatch != null) {
          final lat = double.tryParse(geoMatch.group(1)!);
          final lng = double.tryParse(geoMatch.group(2)!);
          if (lat != null && lng != null) extractedLoc = LatLng(lat, lng);
        }
      }

      // Pattern 7: Raw Coordinates in text (e.g. "32.9861, 70.6042" or "32.9861 70.6042")
      if (extractedLoc == null) {
        final rawMatch = RegExp(r'(-?\d{1,2}\.\d{3,})[,\s]+(-?\d{1,3}\.\d{3,})').firstMatch(trimmed);
        if (rawMatch != null) {
          final lat = double.tryParse(rawMatch.group(1)!);
          final lng = double.tryParse(rawMatch.group(2)!);
          if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
            extractedLoc = LatLng(lat, lng);
          }
        }
      }

      // Pattern 8: If place name query exists in URL (e.g. /place/Bannu+Cantt), search it
      if (extractedLoc == null && urlToAnalyze.contains('/place/')) {
        final nameMatch = RegExp(r'\/place\/([^/?#&]+)').firstMatch(urlToAnalyze);
        if (nameMatch != null) {
          final rawPlaceName = Uri.decodeComponent(nameMatch.group(1)!.replaceAll('+', ' '));
          final places = await searchPlaces(rawPlaceName);
          if (places.isNotEmpty) {
            return places.first;
          }
        }
      }

      if (extractedLoc != null) {
        // Reverse geocode to get human-friendly address
        String address = await getAddressFromCoordinates(extractedLoc);
        if (address.isEmpty || address.contains('Unknown Location')) {
          address = 'Location (${extractedLoc.latitude.toStringAsFixed(4)}, ${extractedLoc.longitude.toStringAsFixed(4)})';
        }
        return PlaceItem(
          name: address,
          subtitle: '${extractedLoc.latitude.toStringAsFixed(5)}, ${extractedLoc.longitude.toStringAsFixed(5)}',
          location: extractedLoc,
        );
      }
    } catch (e) {
      debugPrint('Error parsing maps link: $e');
    }

    return null;
  }
}
