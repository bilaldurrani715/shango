import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll hide Path;
import '../services/location_service.dart';
import '../theme.dart';

class LiveMapView extends StatefulWidget {
  final ll.LatLng? pickupLocation;
  final ll.LatLng? dropLocation;
  final ll.LatLng? riderLocation;
  final List<ll.LatLng>? nearbyRiders;
  final bool showRoute;
  final double initialZoom;
  final VoidCallback? onRecenter;
  final void Function(ll.LatLng point)? onMapTap;

  const LiveMapView({
    super.key,
    this.pickupLocation,
    this.dropLocation,
    this.riderLocation,
    this.nearbyRiders,
    this.showRoute = false,
    this.initialZoom = 14.5,
    this.onRecenter,
    this.onMapTap,
  });

  @override
  State<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends State<LiveMapView> {
  gmaps.GoogleMapController? _mapController;
  List<ll.LatLng> _routePoints = [];
  bool _fetchingRoute = false;
  gmaps.MapType _mapType = gmaps.MapType.normal;

  static gmaps.BitmapDescriptor? _pickupIcon;
  static gmaps.BitmapDescriptor? _dropIcon;
  static gmaps.BitmapDescriptor? _riderIcon;
  static gmaps.BitmapDescriptor? _nearbyRiderIcon;

  gmaps.LatLng _toG(ll.LatLng p) => gmaps.LatLng(p.latitude, p.longitude);
  ll.LatLng _toL(gmaps.LatLng p) => ll.LatLng(p.latitude, p.longitude);

  @override
  void initState() {
    super.initState();
    _loadCustomIcons(force: true);
    _loadRouteIfNeeded();
  }

  Future<void> _loadCustomIcons({bool force = false}) async {
    if (!force && _pickupIcon != null && _dropIcon != null && _riderIcon != null && _nearbyRiderIcon != null) {
      return;
    }
    try {
      _pickupIcon = await _createCustomPinBitmap(
        icon: Icons.person,
        pinColor: const Color(0xFF10B981),
        iconColor: Colors.white,
        size: 42,
        showPointer: true,
      );
      _dropIcon = await _createCustomPinBitmap(
        icon: Icons.flag,
        pinColor: const Color(0xFFEF4444),
        iconColor: Colors.white,
        size: 42,
        showPointer: true,
      );
      _riderIcon = await _createCustomPinBitmap(
        icon: Icons.two_wheeler,
        pinColor: C.black,
        iconColor: C.yellow,
        size: 44,
        showPointer: true,
      );
      _nearbyRiderIcon = await _createCustomPinBitmap(
        icon: Icons.two_wheeler,
        pinColor: C.black,
        iconColor: C.yellow,
        size: 38,
        showPointer: false,
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading custom marker icons: $e');
    }
  }

  static Future<gmaps.BitmapDescriptor> _createCustomPinBitmap({
    required IconData icon,
    required Color pinColor,
    required Color iconColor,
    required double size,
    bool showPointer = true,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double radius = size * (showPointer ? 0.38 : 0.44);
    final Offset center = Offset(size / 2, radius + 2);

    // Drop shadow
    final Paint shadowPaint = Paint()
      ..color = Colors.black38
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(center.translate(0, 1.5), radius, shadowPaint);

    // Pin circle
    final Paint pinPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, pinPaint);

    // Accent outer ring (Yellow for rider, white for others)
    final Color ringColor = (pinColor == C.black) ? C.yellow : Colors.white;
    final Paint borderPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, radius, borderPaint);

    double triH = 0;
    if (showPointer) {
      // Pointer needle triangle
      final double triW = size * 0.28;
      triH = size * 0.18;
      final Path pointer = Path()
        ..moveTo(center.dx - triW / 2, center.dy + radius - 1)
        ..lineTo(center.dx + triW / 2, center.dy + radius - 1)
        ..lineTo(center.dx, center.dy + radius + triH)
        ..close();
      canvas.drawPath(pointer, pinPaint);

      final Paint pointerBorder = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(pointer, pointerBorder);
    }

    // Center icon
    final TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * (showPointer ? 0.42 : 0.48),
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: iconColor,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );

    final int width = size.toInt();
    final int height = (showPointer ? center.dy + radius + triH + 3 : center.dy + radius + 3).ceil();
    final ui.Image img = await pictureRecorder.endRecording().toImage(width, height);
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    return gmaps.BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  @override
  void didUpdateWidget(covariant LiveMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showRoute &&
        (widget.pickupLocation != oldWidget.pickupLocation ||
            widget.dropLocation != oldWidget.dropLocation ||
            widget.riderLocation != oldWidget.riderLocation)) {
      _loadRouteIfNeeded();
    }
  }

  Future<void> _loadRouteIfNeeded() async {
    if (!widget.showRoute) return;

    final start = widget.riderLocation ?? widget.pickupLocation;
    final end = widget.dropLocation ?? widget.pickupLocation;

    if (start != null && end != null && start != end && !_fetchingRoute) {
      _fetchingRoute = true;
      final points = await LocationService.getRoutePoints(start, end);
      if (mounted) {
        final connected = List<ll.LatLng>.from(points);
        if (connected.isNotEmpty) {
          if (LocationService.getDistanceBetween(start, connected.first) > 8) {
            connected.insert(0, start);
          }
          if (LocationService.getDistanceBetween(connected.last, end) > 8) {
            connected.add(end);
          }
        } else {
          connected.addAll([start, end]);
        }

        setState(() {
          _routePoints = connected;
          _fetchingRoute = false;
        });

        _fitRouteBounds([start, end, ...connected]);
      }
    }
  }

  void _fitRouteBounds(List<ll.LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
    try {
      double minLat = points.first.latitude;
      double maxLat = points.first.latitude;
      double minLng = points.first.longitude;
      double maxLng = points.first.longitude;

      for (final p in points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }

      _mapController?.animateCamera(
        gmaps.CameraUpdate.newLatLngBounds(
          gmaps.LatLngBounds(
            southwest: gmaps.LatLng(minLat, minLng),
            northeast: gmaps.LatLng(maxLat, maxLng),
          ),
          65.0,
        ),
      );
    } catch (e) {
      debugPrint('Fit camera notice: $e');
    }
  }

  void _recenter() {
    final target = widget.riderLocation ?? widget.pickupLocation ?? LocationService.defaultLocation;
    _mapController?.animateCamera(
      gmaps.CameraUpdate.newLatLngZoom(_toG(target), widget.initialZoom),
    );
    if (widget.onRecenter != null) widget.onRecenter!();
  }

  void _fitNearbyDrivers() {
    if (widget.nearbyRiders == null || widget.nearbyRiders!.isEmpty) {
      _recenter();
      return;
    }
    final points = <ll.LatLng>[
      if (widget.pickupLocation != null) widget.pickupLocation!,
      ...widget.nearbyRiders!,
    ];
    _fitRouteBounds(points);
  }

  Set<gmaps.Marker> _buildMarkers() {
    final markers = <gmaps.Marker>{};

    // 1. Pickup Location Marker (Emerald Green Pin with Person icon)
    if (widget.pickupLocation != null) {
      markers.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('pickup'),
          position: _toG(widget.pickupLocation!),
          icon: _pickupIcon ?? gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueGreen),
          anchor: const Offset(0.5, 1.0),
          infoWindow: const gmaps.InfoWindow(title: 'Pickup Location', snippet: 'Passenger waiting here'),
        ),
      );
    }

    // 2. Drop / Destination Location Marker (Crimson Red Pin with Flag icon)
    if (widget.dropLocation != null) {
      markers.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('drop'),
          position: _toG(widget.dropLocation!),
          icon: _dropIcon ?? gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 1.0),
          infoWindow: const gmaps.InfoWindow(title: 'Destination', snippet: 'Trip destination'),
        ),
      );
    }

    // 3. Active En-Route Rider Marker (Black Pin with Gold Yellow Bike icon)
    if (widget.riderLocation != null) {
      markers.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('rider'),
          position: _toG(widget.riderLocation!),
          icon: _riderIcon ?? gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueOrange),
          anchor: const Offset(0.5, 1.0),
          infoWindow: const gmaps.InfoWindow(title: 'Assigned Driver', snippet: 'Live GPS location'),
        ),
      );
    }

    // 4. Nearby Available Drivers on Passenger Map (High-visibility Black & Gold Bike pins)
    if (widget.nearbyRiders != null) {
      for (int i = 0; i < widget.nearbyRiders!.length; i++) {
        markers.add(
          gmaps.Marker(
            markerId: gmaps.MarkerId('nearby_rider_$i'),
            position: _toG(widget.nearbyRiders![i]),
            icon: _nearbyRiderIcon ?? gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueYellow),
            anchor: const Offset(0.5, 0.5),
            infoWindow: gmaps.InfoWindow(
              title: 'ShanGo Driver #${i + 1}',
              snippet: '🟢 Available & Online Nearby',
            ),
          ),
        );
      }
    }

    return markers;
  }

  Set<gmaps.Polyline> _buildPolylines() {
    if (!widget.showRoute || _routePoints.isEmpty) return {};

    final isSatellite = _mapType == gmaps.MapType.satellite || _mapType == gmaps.MapType.hybrid;
    return {
      gmaps.Polyline(
        polylineId: const gmaps.PolylineId('ride_route'),
        points: _routePoints.map(_toG).toList(),
        width: 6,
        color: isSatellite ? C.yellow : Colors.blue.shade700,
        jointType: gmaps.JointType.round,
        startCap: gmaps.Cap.roundCap,
        endCap: gmaps.Cap.roundCap,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.riderLocation ?? widget.pickupLocation ?? LocationService.defaultLocation;

    return Stack(
      children: [
        gmaps.GoogleMap(
          initialCameraPosition: gmaps.CameraPosition(
            target: _toG(center),
            zoom: widget.initialZoom,
          ),
          mapType: _mapType,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: true,
          trafficEnabled: false,
          markers: _buildMarkers(),
          polylines: _buildPolylines(),
          onMapCreated: (controller) {
            _mapController = controller;
            if (_routePoints.isNotEmpty) {
              final start = widget.riderLocation ?? widget.pickupLocation;
              final end = widget.dropLocation ?? widget.pickupLocation;
              if (start != null && end != null) {
                _fitRouteBounds([start, end, ..._routePoints]);
              }
            }
          },
          onTap: (pos) => widget.onMapTap?.call(_toL(pos)),
        ),

        // Floating Action Buttons (Recenter & Satellite Toggle)
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Recenter Button
              FloatingActionButton.small(
                heroTag: null,
                backgroundColor: C.white,
                foregroundColor: C.black,
                elevation: 4,
                onPressed: _recenter,
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 10),

              // 2. Satellite / Street View Toggle
              FloatingActionButton.small(
                heroTag: null,
                backgroundColor: (_mapType == gmaps.MapType.normal) ? C.white : C.black,
                foregroundColor: (_mapType == gmaps.MapType.normal) ? C.black : C.yellow,
                elevation: 4,
                tooltip: (_mapType == gmaps.MapType.normal) ? 'Switch to Satellite View' : 'Switch to Street Map',
                onPressed: () {
                  setState(() {
                    _mapType = (_mapType == gmaps.MapType.normal) ? gmaps.MapType.hybrid : gmaps.MapType.normal;
                  });
                },
                child: Icon((_mapType == gmaps.MapType.normal) ? Icons.satellite_alt_outlined : Icons.map_outlined),
              ),

              // 3. View All Nearby Drivers
              if (widget.nearbyRiders != null && widget.nearbyRiders!.isNotEmpty) ...[
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: null,
                  backgroundColor: C.yellow,
                  foregroundColor: C.black,
                  elevation: 4,
                  tooltip: 'Show nearby drivers (${widget.nearbyRiders!.length})',
                  onPressed: _fitNearbyDrivers,
                  child: const Icon(Icons.two_wheeler, size: 20),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
