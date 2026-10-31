import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import 'admin_panel.dart';
import 'rider_dashboard_screen.dart';
import 'shell.dart';

class AdminFleetMapScreen extends StatefulWidget {
  const AdminFleetMapScreen({super.key});

  @override
  State<AdminFleetMapScreen> createState() => _AdminFleetMapScreenState();
}

class _AdminFleetMapScreenState extends State<AdminFleetMapScreen> {
  final RideService _rideService = RideService();
  final NotificationService _notificationService = NotificationService();

  gmaps.GoogleMapController? _mapController;
  gmaps.MapType _mapType = gmaps.MapType.normal;

  // Filter & Search
  String _vehicleFilter = 'all'; // all, bike, car, auto, on_trip
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Selected driver for detailed card
  Map<String, dynamic>? _selectedDriverData;

  // Custom Bitmap Markers
  gmaps.BitmapDescriptor? _bikeMarker;
  gmaps.BitmapDescriptor? _carMarker;
  gmaps.BitmapDescriptor? _autoMarker;
  gmaps.BitmapDescriptor? _busyMarker;

  @override
  void initState() {
    super.initState();
    _loadCustomMarkers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomMarkers() async {
    try {
      _bikeMarker = await _createCustomPinBitmap(
        icon: Icons.two_wheeler,
        pinColor: C.black,
        iconColor: const Color(0xFFFFCC00),
        borderColor: const Color(0xFFFFCC00),
        size: 44,
      );
      _carMarker = await _createCustomPinBitmap(
        icon: Icons.directions_car,
        pinColor: const Color(0xFF1E3A8A),
        iconColor: Colors.white,
        borderColor: const Color(0xFF60A5FA),
        size: 44,
      );
      _autoMarker = await _createCustomPinBitmap(
        icon: Icons.electric_rickshaw,
        pinColor: const Color(0xFF065F46),
        iconColor: Colors.white,
        borderColor: const Color(0xFF34D399),
        size: 44,
      );
      _busyMarker = await _createCustomPinBitmap(
        icon: Icons.do_not_disturb_on,
        pinColor: const Color(0xFFDC2626),
        iconColor: Colors.white,
        borderColor: const Color(0xFFFCA5A5),
        size: 46,
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error generating admin fleet markers: $e');
    }
  }

  static Future<gmaps.BitmapDescriptor> _createCustomPinBitmap({
    required IconData icon,
    required Color pinColor,
    required Color iconColor,
    required Color borderColor,
    required double size,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double radius = size * 0.38;
    final Offset center = Offset(size / 2, radius + 2);

    // Drop shadow
    final Paint shadowPaint = Paint()
      ..color = Colors.black45
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawCircle(center.translate(0, 2), radius, shadowPaint);

    // Pin circle
    final Paint pinPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, pinPaint);

    // Outer ring border
    final Paint borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawCircle(center, radius, borderPaint);

    // Pointer needle triangle at bottom
    final double triW = size * 0.28;
    final double triH = size * 0.18;
    final Path pointer = Path()
      ..moveTo(center.dx - triW / 2, center.dy + radius - 1)
      ..lineTo(center.dx + triW / 2, center.dy + radius - 1)
      ..lineTo(center.dx, center.dy + radius + triH)
      ..close();
    canvas.drawPath(pointer, pinPaint);

    final Paint pointerBorder = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawPath(pointer, pointerBorder);

    // Center icon
    final TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.42,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: iconColor,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );

    final int width = size.toInt();
    final int height = (center.dy + radius + triH + 3).ceil();
    final ui.Image img = await pictureRecorder.endRecording().toImage(width, height);
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    return gmaps.BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  bool _matchesVehicle(String? vehicleType, String filterKey) {
    if (filterKey == 'all' || filterKey == 'on_trip') return true;
    final v = (vehicleType ?? 'Bike').trim().toLowerCase();
    if (filterKey == 'bike') {
      return v.contains('bike') || v.contains('motor') || v.contains('scooter') || v.isEmpty;
    }
    if (filterKey == 'car') {
      return v.contains('car') || v.contains('taxi') || v.contains('sedan') || v.contains('cab');
    }
    if (filterKey == 'auto') {
      return v.contains('auto') || v.contains('rickshaw');
    }
    return true;
  }

  IconData _getVehicleIcon(String? vehicleType) {
    final v = (vehicleType ?? '').trim().toLowerCase();
    if (v.contains('car') || v.contains('taxi') || v.contains('sedan')) {
      return Icons.directions_car;
    }
    if (v.contains('auto') || v.contains('rickshaw')) {
      return Icons.electric_rickshaw;
    }
    return Icons.two_wheeler;
  }

  void _focusOnDriver(double lat, double lng) {
    _mapController?.animateCamera(
      gmaps.CameraUpdate.newCameraPosition(
        gmaps.CameraPosition(
          target: gmaps.LatLng(lat, lng),
          zoom: 16.0,
          tilt: 20,
        ),
      ),
    );
  }

  Future<void> _makeCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String phone, String name) async {
    final clean = phone.replaceAll(RegExp(r'[^\d]'), '');
    final uri = Uri.parse('https://wa.me/$clean?text=Hello%20$name,%20message%20from%20ShanGo%20Admin%20Radar.');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield, color: C.black),
            SizedBox(width: 8),
            Text('Admin Navigation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: const Text(
          'Would you like to switch to Passenger Map Mode or exit ShanGo?',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Stay on Radar', style: TextStyle(color: Colors.black54)),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: C.black),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, 'passenger'),
            child: const Text('Passenger Mode', style: TextStyle(color: C.black, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, 'exit'),
            child: const Text('Exit App', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result == 'passenger') {
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
      }
      return false;
    } else if (result == 'exit') {
      SystemNavigator.pop();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onWillPop();
      },
      child: Scaffold(
        body: StreamBuilder<List<OnlineRiderInfo>>(
          stream: _rideService.streamOnlineRiderDetails(),
          builder: (context, onlineSnap) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _rideService.streamUsers(role: 'rider'),
              builder: (context, allDriversSnap) {
                return StreamBuilder<List<RideModel>>(
                  stream: _rideService.streamAllRides(),
                  builder: (context, ridesSnap) {
                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _rideService.streamAllIntercityBookings(),
                      builder: (context, intercitySnap) {
                        final onlineRiders = onlineSnap.data ?? [];
                        final allDrivers = allDriversSnap.data ?? [];
                        final allRides = ridesSnap.data ?? [];
                        final allIntercity = intercitySnap.data ?? [];

                        // Map uid -> driver user document
                        final Map<String, Map<String, dynamic>> driverProfiles = {
                          for (final d in allDrivers) (d['uid'] ?? ''): d,
                        };

                        // Map uid -> Active ride info (if on a ride)
                        final Map<String, Map<String, dynamic>> activeRidesByDriver = {};
                        for (final r in allRides) {
                          if ((r.status == 'accepted' || r.status == 'started' || r.status == 'in_progress') &&
                              r.riderId != null) {
                            activeRidesByDriver[r.riderId!] = {
                              'type': 'local',
                              'pickup': r.pickupAddress,
                              'drop': r.dropAddress,
                              'customerName': r.customerName,
                              'customerPhone': r.customerPhone,
                              'fare': r.estimatedFare,
                              'status': r.status,
                            };
                          }
                        }
                        for (final b in allIntercity) {
                          final rId = b['riderId'] as String?;
                          final status = b['status'] as String?;
                          if (rId != null && (status == 'assigned' || status == 'in_progress')) {
                            activeRidesByDriver[rId] = {
                              'type': 'intercity',
                              'route': '${b["fromCity"] ?? "City"} ➔ ${b["toCity"] ?? "City"}',
                              'customerName': b['customerName'],
                              'customerPhone': b['customerPhone'],
                              'fare': b['fare'],
                              'status': status,
                            };
                          }
                        }

                        // Combine into enriched driver list
                        final List<Map<String, dynamic>> enrichedOnlineDrivers = [];
                        for (final info in onlineRiders) {
                          final profile = driverProfiles[info.uid] ?? {};
                          final bool isSuspended = profile['isSuspended'] == true;
                          if (isSuspended) continue; // Hide suspended drivers from radar

                          final activeTrip = activeRidesByDriver[info.uid];
                          final bool isOnTrip = activeTrip != null;

                          final rawName = profile['name'] ?? 'Driver';
                          final String dName = (rawName.toString().trim().isNotEmpty && rawName.toString().toLowerCase() != 'null')
                              ? rawName.toString().trim()
                              : 'Driver (${profile['phone'] ?? 'No Phone'})';

                          enrichedOnlineDrivers.add({
                            'uid': info.uid,
                            'name': dName,
                            'phone': profile['phone'] ?? 'No Phone',
                            'email': profile['email'] ?? '',
                            'vehicleType': profile['vehicleType'] ?? info.vehicleType,
                            'vehicleModel': profile['vehicleModel'] ?? info.vehicleModel,
                            'plateNumber': profile['plateNumber'] ?? '',
                            'rating': (profile['rating'] as num?)?.toDouble() ?? 5.0,
                            'totalRatings': (profile['totalRatings'] as num?)?.toInt() ?? 1,
                            'lat': info.location.latitude,
                            'lng': info.location.longitude,
                            'isOnTrip': isOnTrip,
                            'activeTrip': activeTrip,
                            'rawProfile': profile,
                          });
                        }

                        // Counts for filters
                        final int totalOnline = enrichedOnlineDrivers.length;
                        final int bikeCount = enrichedOnlineDrivers.where((d) => _matchesVehicle(d['vehicleType'] as String?, 'bike')).length;
                        final int carCount = enrichedOnlineDrivers.where((d) => _matchesVehicle(d['vehicleType'] as String?, 'car')).length;
                        final int autoCount = enrichedOnlineDrivers.where((d) => _matchesVehicle(d['vehicleType'] as String?, 'auto')).length;
                        final int onTripCount = enrichedOnlineDrivers.where((d) => d['isOnTrip'] == true).length;

                        // Filter drivers by category
                        final filteredDrivers = enrichedOnlineDrivers.where((d) {
                          if (_vehicleFilter == 'on_trip') {
                            if (d['isOnTrip'] != true) return false;
                          } else if (!_matchesVehicle(d['vehicleType'] as String?, _vehicleFilter)) {
                            return false;
                          }

                          if (_searchQuery.isNotEmpty) {
                            final q = _searchQuery.toLowerCase();
                            final name = (d['name'] ?? '').toString().toLowerCase();
                            final phone = (d['phone'] ?? '').toString().toLowerCase();
                            final model = (d['vehicleModel'] ?? '').toString().toLowerCase();
                            final plate = (d['plateNumber'] ?? '').toString().toLowerCase();
                            return name.contains(q) || phone.contains(q) || model.contains(q) || plate.contains(q);
                          }

                          return true;
                        }).toList();

                        // Build Map Markers
                        final Set<gmaps.Marker> markers = {};
                        for (final d in filteredDrivers) {
                          final double lat = d['lat'] as double;
                          final double lng = d['lng'] as double;
                          final String uid = d['uid'] as String;
                          final String vType = (d['vehicleType'] as String? ?? 'Bike').toLowerCase();
                          final bool isOnTrip = d['isOnTrip'] == true;

                          gmaps.BitmapDescriptor iconToUse = _bikeMarker ?? gmaps.BitmapDescriptor.defaultMarker;
                          if (isOnTrip && _busyMarker != null) {
                            iconToUse = _busyMarker!;
                          } else if (vType.contains('car') || vType.contains('taxi') || vType.contains('sedan')) {
                            iconToUse = _carMarker ?? iconToUse;
                          } else if (vType.contains('auto') || vType.contains('rickshaw')) {
                            iconToUse = _autoMarker ?? iconToUse;
                          }

                          markers.add(
                            gmaps.Marker(
                              markerId: gmaps.MarkerId(uid),
                              position: gmaps.LatLng(lat, lng),
                              icon: iconToUse,
                              zIndexInt: isOnTrip ? 3 : 2,
                              infoWindow: gmaps.InfoWindow(
                                title: d['name'] as String?,
                                snippet: isOnTrip
                                    ? '🔴 ON TRIP • ${d["vehicleType"]}'
                                    : '🟢 ONLINE • ${d["vehicleType"]}: ${d["vehicleModel"]}',
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedDriverData = d;
                                });
                                _focusOnDriver(lat, lng);
                              },
                            ),
                          );
                        }

                        return Stack(
                          children: [
                            // 1. Fullscreen Google Map
                            gmaps.GoogleMap(
                              initialCameraPosition: const gmaps.CameraPosition(
                                target: gmaps.LatLng(32.9861, 70.6042), // Bannu default
                                zoom: 13.0,
                              ),
                              mapType: _mapType,
                              myLocationEnabled: true,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              compassEnabled: true,
                              markers: markers,
                              onMapCreated: (ctrl) {
                                _mapController = ctrl;
                                if (filteredDrivers.isNotEmpty) {
                                  _focusOnDriver(filteredDrivers.first['lat'] as double, filteredDrivers.first['lng'] as double);
                                }
                              },
                              onTap: (_) {
                                if (_selectedDriverData != null) {
                                  setState(() {
                                    _selectedDriverData = null;
                                  });
                                }
                              },
                            ),

                            // 2. Floating Top Header
                            Positioned(
                              top: MediaQuery.of(context).padding.top + 8,
                              left: 14,
                              right: 14,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.12),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        // Pulse Radar Icon
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: C.black,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(Icons.radar_rounded, color: Color(0xFFFFCC00), size: 22),
                                        ),
                                        const SizedBox(width: 10),

                                        // Titles & Live Indicator
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Row(
                                                children: [
                                                  Text(
                                                    'Fleet Radar',
                                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: Colors.black87),
                                                  ),
                                                  SizedBox(width: 6),
                                                  Icon(Icons.fiber_manual_record, size: 10, color: Color(0xFF10B981)),
                                                  SizedBox(width: 2),
                                                  Text(
                                                    'LIVE',
                                                    style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w900, fontSize: 10),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                '$totalOnline Online Drivers • $onTripCount in Progress',
                                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Map Layer Toggle
                                        IconButton(
                                          icon: Icon(
                                            _mapType == gmaps.MapType.normal ? Icons.layers_outlined : Icons.map_outlined,
                                            color: Colors.black87,
                                            size: 22,
                                          ),
                                          tooltip: 'Toggle Satellite / Map',
                                          onPressed: () {
                                            setState(() {
                                              _mapType = _mapType == gmaps.MapType.normal
                                                  ? gmaps.MapType.hybrid
                                                  : gmaps.MapType.normal;
                                            });
                                          },
                                        ),

                                        // Admin Console Button
                                        StreamBuilder<int>(
                                          stream: _notificationService.streamAdminUnreadCount(),
                                          builder: (context, notifSnap) {
                                            final unread = notifSnap.data ?? 0;
                                            return ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: C.yellow,
                                                foregroundColor: C.black,
                                                elevation: 0,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                              icon: Badge(
                                                isLabelVisible: unread > 0,
                                                label: Text('$unread', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                                                backgroundColor: Colors.red,
                                                child: const Icon(Icons.admin_panel_settings, size: 18, color: C.black),
                                              ),
                                              label: const Text(
                                                'Console',
                                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                              ),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // 3. Floating Filter Chips Row
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _buildFilterChip('All Drivers ($totalOnline)', 'all', Icons.commute),
                                        const SizedBox(width: 6),
                                        _buildFilterChip('Bikes ($bikeCount)', 'bike', Icons.two_wheeler),
                                        const SizedBox(width: 6),
                                        _buildFilterChip('Cars ($carCount)', 'car', Icons.directions_car),
                                        const SizedBox(width: 6),
                                        _buildFilterChip('Auto ($autoCount)', 'auto', Icons.electric_rickshaw),
                                        const SizedBox(width: 6),
                                        _buildFilterChip('On Trip ($onTripCount)', 'on_trip', Icons.alt_route, activeColor: Colors.red.shade700),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 4. Quick Action Floating Buttons (Right Side)
                            Positioned(
                              right: 14,
                              bottom: _selectedDriverData != null ? 240 : 100,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Switch to Passenger Mode
                                  FloatingActionButton.small(
                                    heroTag: 'fab_passenger_mode',
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black87,
                                    tooltip: 'Switch to Passenger Mode',
                                    onPressed: () {
                                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
                                    },
                                    child: const Icon(Icons.person_pin_circle_outlined, size: 20),
                                  ),
                                  const SizedBox(height: 8),

                                  // Recenter to Bannu / First Driver
                                  FloatingActionButton.small(
                                    heroTag: 'fab_recenter',
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black87,
                                    tooltip: 'Re-center Radar',
                                    onPressed: () {
                                      if (filteredDrivers.isNotEmpty) {
                                        _focusOnDriver(filteredDrivers.first['lat'] as double, filteredDrivers.first['lng'] as double);
                                      } else {
                                        _mapController?.animateCamera(
                                          gmaps.CameraUpdate.newLatLngZoom(const gmaps.LatLng(32.9861, 70.6042), 13.0),
                                        );
                                      }
                                    },
                                    child: const Icon(Icons.my_location, size: 20),
                                  ),
                                ],
                              ),
                            ),

                            // 5. Selected Driver Floating Card (When marker tapped)
                            if (_selectedDriverData != null)
                              Positioned(
                                left: 14,
                                right: 14,
                                bottom: 20,
                                child: _buildSelectedDriverCard(_selectedDriverData!),
                              ),

                            // 6. Collapsible Fleet Bottom Bar (When no driver selected)
                            if (_selectedDriverData == null)
                              Positioned(
                                left: 14,
                                right: 14,
                                bottom: 16,
                                child: _buildBottomFleetBar(filteredDrivers),
                              ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, IconData icon, {Color? activeColor}) {
    final bool isSelected = _vehicleFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _vehicleFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? (activeColor ?? C.yellow) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.black87 : Colors.grey.shade300,
            width: isSelected ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? (activeColor != null ? Colors.white : C.black) : Colors.black87,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? (activeColor != null ? Colors.white : C.black) : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedDriverCard(Map<String, dynamic> d) {
    final name = d['name'] as String? ?? 'Driver';
    final phone = d['phone'] as String? ?? 'No Phone';
    final vType = d['vehicleType'] as String? ?? 'Bike';
    final vModel = d['vehicleModel'] as String? ?? 'Vehicle';
    final plate = d['plateNumber'] as String? ?? '';
    final rating = (d['rating'] as num?)?.toDouble() ?? 5.0;
    final totalRatings = (d['totalRatings'] as num?)?.toInt() ?? 1;
    final bool isOnTrip = d['isOnTrip'] == true;
    final activeTrip = d['activeTrip'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOnTrip ? Colors.red.shade300 : const Color(0xFFF59E0B),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: C.black,
                child: Icon(_getVehicleIcon(vType), color: const Color(0xFFFFCC00), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black87),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isOnTrip ? Colors.red.shade100 : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isOnTrip ? '🔴 ON TRIP' : '🟢 READY',
                            style: TextStyle(
                              color: isOnTrip ? Colors.red.shade900 : const Color(0xFF166534),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$phone • $vModel${plate.isNotEmpty ? " ($plate)" : ""} • ★ ${rating.toStringAsFixed(1)} ($totalRatings)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _selectedDriverData = null;
                  });
                },
              ),
            ],
          ),

          // Active Trip Details (If on Trip)
          if (isOnTrip && activeTrip != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.navigation, size: 14, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      activeTrip['type'] == 'intercity'
                          ? 'Intercity: ${activeTrip["route"] ?? ""}'
                          : 'Pickup: ${activeTrip["pickup"] ?? "Trip in progress"}',
                      style: TextStyle(fontSize: 11.5, color: Colors.red.shade900, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Action Buttons
          Row(
            children: [
              // Locate Button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.black,
                    foregroundColor: const Color(0xFFFFCC00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.my_location, size: 16, color: Color(0xFFFFCC00)),
                  label: const Text('Locate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    _focusOnDriver(d['lat'] as double, d['lng'] as double);
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Dashboard Button
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.dashboard_outlined, size: 16),
                  label: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RiderDashboardScreen(
                          riderId: d['uid'] as String,
                          initialRiderData: (d['rawProfile'] as Map<String, dynamic>?) ?? d,
                          isAdminView: true,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Call Button
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: IconButton(
                  icon: const Icon(Icons.call, color: Colors.black87, size: 18),
                  tooltip: 'Call Driver',
                  onPressed: () => _makeCall(phone),
                ),
              ),
              const SizedBox(width: 8),

              // WhatsApp Button
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF22C55E), size: 18),
                  tooltip: 'WhatsApp',
                  onPressed: () => _openWhatsApp(phone, name),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomFleetBar(List<Map<String, dynamic>> drivers) {
    return GestureDetector(
      onTap: () => _showFleetListModal(drivers),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: C.black,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.format_list_bulleted, color: Color(0xFFFFCC00), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Fleet List (${drivers.length} Drivers Shown)',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.black87),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to view all driver cards, call, or locate',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Text('View', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  Icon(Icons.keyboard_arrow_up, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFleetListModal(List<Map<String, dynamic>> drivers) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final modalFiltered = drivers.where((d) {
            if (_searchQuery.isEmpty) return true;
            final q = _searchQuery.toLowerCase();
            final name = (d['name'] ?? '').toString().toLowerCase();
            final phone = (d['phone'] ?? '').toString().toLowerCase();
            final model = (d['vehicleModel'] ?? '').toString().toLowerCase();
            final plate = (d['plateNumber'] ?? '').toString().toLowerCase();
            return name.contains(q) || phone.contains(q) || model.contains(q) || plate.contains(q);
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Live Fleet Roster', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                          Text('${modalFiltered.length} online drivers matched', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search driver by name, phone, or vehicle...',
                      hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                      prefixIcon: const Icon(Icons.search, size: 20, color: Colors.black54),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setModalState(() => _searchQuery = '');
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) {
                      setModalState(() => _searchQuery = val.trim());
                      setState(() => _searchQuery = val.trim());
                    },
                  ),
                ),

                // Driver List
                Expanded(
                  child: modalFiltered.isEmpty
                      ? Center(
                          child: Text(
                            'No drivers found matching "$_searchQuery"',
                            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: modalFiltered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final d = modalFiltered[idx];
                            final name = d['name'] as String? ?? 'Driver';
                            final phone = d['phone'] as String? ?? '';
                            final vType = d['vehicleType'] as String? ?? 'Bike';
                            final vModel = d['vehicleModel'] as String? ?? '';
                            final bool isOnTrip = d['isOnTrip'] == true;

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: C.black,
                                    child: Icon(_getVehicleIcon(vType), color: const Color(0xFFFFCC00), size: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                name,
                                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: isOnTrip ? Colors.red.shade100 : const Color(0xFFDCFCE7),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                isOnTrip ? 'ON TRIP' : 'ONLINE',
                                                style: TextStyle(
                                                  color: isOnTrip ? Colors.red.shade900 : const Color(0xFF166534),
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$phone • $vType: $vModel',
                                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: C.yellow,
                                      foregroundColor: C.black,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(modalCtx);
                                      setState(() {
                                        _selectedDriverData = d;
                                      });
                                      _focusOnDriver(d['lat'] as double, d['lng'] as double);
                                    },
                                    child: const Text('Locate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
