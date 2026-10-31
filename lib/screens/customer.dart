import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/live_map_view.dart';
import 'auth.dart';
import 'complete_profile_screen.dart';
import 'intercity_screen.dart';
import 'ride.dart';


class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  final RideService _rideService = RideService();
  String pickup = 'Locating GPS...';
  LatLng pickupLocation = LocationService.defaultLocation;
  String? drop;
  LatLng? dropLocation;
  bool _loadingLocation = true;
  RouteDetails? _routeDetails;
  bool _calculatingRoute = false;
  List<LatLng> _onlineRiders = [];
  StreamSubscription<List<LatLng>>? _onlineRidersSub;
  double _baseFare = 150.0;
  double _perKmRate = 40.0;
  StreamSubscription<Map<String, dynamic>>? _localPricingSub;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
    _onlineRidersSub = _rideService.streamOnlineRiders().listen((riders) {
      if (mounted) {
        setState(() => _onlineRiders = riders);
      }
    });
    _localPricingSub = _rideService.streamLocalPricing().listen((pricing) {
      if (mounted) {
        setState(() {
          _baseFare = (pricing['baseFare'] as num?)?.toDouble() ?? 150.0;
          _perKmRate = (pricing['perKmRate'] as num?)?.toDouble() ?? 40.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _onlineRidersSub?.cancel();
    _localPricingSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation({bool userInitiated = false}) async {
    setState(() {
      _loadingLocation = true;
      pickup = 'Locating GPS...';
    });

    final pos = await LocationService.getCurrentPosition();
    if (mounted) {
      if (pos != null) {
        final loc = LatLng(pos.latitude, pos.longitude);
        setState(() {
          pickupLocation = loc;
          pickup = 'Detecting city & street...';
          _loadingLocation = false;
        });

        // Automatically resolve city and street name from GPS location
        final address = await LocationService.getAddressFromCoordinates(loc);
        if (mounted) {
          setState(() {
            pickup = address;
          });
        }
      } else {
        setState(() {
          pickup = 'Bannu Cantt (Default)';
          _loadingLocation = false;
        });
        if (userInitiated) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable GPS / Location services on your phone.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      if (dropLocation != null) {
        _updateRouteInfo();
      }
    }
  }

  Future<void> _updateRouteInfo() async {
    if (dropLocation == null) return;
    setState(() => _calculatingRoute = true);
    final details = await LocationService.getRouteDetails(pickupLocation, dropLocation!);
    if (mounted) {
      setState(() {
        _routeDetails = details;
        _calculatingRoute = false;
      });
    }
  }

  Future<void> _onMapTapped(LatLng point) async {
    setState(() {
      dropLocation = point;
      drop = 'Locating area...';
    });
    _updateRouteInfo();

    final address = await LocationService.getAddressFromCoordinates(point);
    if (mounted && dropLocation == point) {
      setState(() {
        drop = address;
      });
    }
  }

  void _showWhatsAppLocationExtractorDialog({required bool isDropLocation}) {
    final urlController = TextEditingController();
    bool extracting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
                child: const Icon(Icons.share_location, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isDropLocation ? 'Import Destination Location' : 'Import Pickup Location',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDropLocation
                      ? 'Paste the Google Maps link or WhatsApp message received for Destination:'
                      : 'Paste the Google Maps link or WhatsApp message received for Pickup:',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'e.g. https://maps.app.goo.gl/xxxx or 32.986, 70.604',
                    filled: true,
                    fillColor: C.grey,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: 'Paste from clipboard',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          setModalState(() {
                            urlController.text = data!.text!;
                          });
                        }
                      },
                    ),
                  ),
                ),
                if (extracting) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator(color: C.yellow)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
              icon: const Icon(Icons.pin_drop, size: 18),
              label: const Text('Extract & Set Location'),
              onPressed: extracting
                  ? null
                  : () async {
                      final text = urlController.text.trim();
                      if (text.isEmpty) return;

                      final nav = Navigator.of(ctx);
                      final messenger = ScaffoldMessenger.of(context);

                      setModalState(() => extracting = true);
                      final result = await LocationService.parseLocationFromMapsLink(text);
                      setModalState(() => extracting = false);

                      if (result != null) {
                        nav.pop();
                        setState(() {
                          if (isDropLocation) {
                            drop = result.name;
                            dropLocation = result.location;
                          } else {
                            pickup = result.name;
                            pickupLocation = result.location;
                          }
                        });
                        _updateRouteInfo();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('📍 ${isDropLocation ? "Destination" : "Pickup"} resolved: ${result.name} (${result.location.latitude.toStringAsFixed(4)}, ${result.location.longitude.toStringAsFixed(4)})'),
                                ),
                              ],
                            ),
                            backgroundColor: Colors.green.shade700,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Could not extract coordinates from link. Please verify and try again.'),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLocation(bool isPickup) async {
    final result = await Navigator.push<PlaceItem>(
      context,
      MaterialPageRoute(
        builder: (_) => SearchLocationScreen(
          isPickup: isPickup,
          currentPickup: pickupLocation,
          currentAddress: pickup,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (isPickup) {
          pickup = result.name;
          pickupLocation = result.location;
        } else {
          drop = result.name;
          dropLocation = result.location;
        }
      });
      _updateRouteInfo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final distMeters = _routeDetails?.distanceMeters ?? (dropLocation != null ? LocationService.getDistanceBetween(pickupLocation, dropLocation!) : 0.0);
    final durationSecs = _routeDetails?.durationSeconds ?? (distMeters / 8.33);
    final distKm = distMeters / 1000;
    final fare = _baseFare.round() + (distKm * _perKmRate).round();

    return Stack(
      children: [
        Positioned.fill(
          child: LiveMapView(
            pickupLocation: pickupLocation,
            dropLocation: dropLocation,
            nearbyRiders: _onlineRiders,
            showRoute: dropLocation != null,
            onMapTap: _onMapTapped,
          ),
        ),

        // Floating Top Banners (Offline Warning + City to City / Trip Overview)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OfflineBanner(),
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 16, right: 70),
                  child: dropLocation == null
                      ? InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const IntercityBookingScreen()),
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: C.black,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                              ],
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.airport_shuttle, color: C.yellow, size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'City to City (Bannu ⇄ Peshawar ⇄ Isb)',
                                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, color: C.yellow, size: 12),
                              ],
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: C.black,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.directions_car, color: C.yellow, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _calculatingRoute ? 'Calculating route...' : 'Trip Overview',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    Text(
                                      _calculatingRoute
                                          ? 'Please wait'
                                          : '${LocationService.formatDistance(distMeters)}  •  ${LocationService.formatDuration(durationSecs)}',
                                      style: const TextStyle(color: C.yellow, fontWeight: FontWeight.w800, fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),

                // Live Nearby Drivers Indicator Capsule
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 16, right: 70),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _onlineRiders.isNotEmpty
                            ? Colors.black.withValues(alpha: 0.85)
                            : Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _onlineRiders.isNotEmpty ? C.yellow : Colors.white24,
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _onlineRiders.isNotEmpty ? const Color(0xFF10B981) : Colors.amber,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.two_wheeler,
                            size: 14,
                            color: _onlineRiders.isNotEmpty ? C.yellow : Colors.white70,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _onlineRiders.isNotEmpty
                                ? '${_onlineRiders.length} ${_onlineRiders.length == 1 ? 'Driver' : 'Drivers'} Online Nearby'
                                : 'Searching for nearby drivers...',
                            style: TextStyle(
                              color: _onlineRiders.isNotEmpty ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        Align(
          alignment: Alignment.bottomCenter,
          child: BottomCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LocField(
                  icon: Icons.circle,
                  color: Colors.green,
                  text: _loadingLocation ? 'Locating GPS...' : pickup,
                  onTap: () => _pickLocation(true),
                  onWhatsAppTap: () => _showWhatsAppLocationExtractorDialog(isDropLocation: false),
                ),
                const SizedBox(height: 10),
                _LocField(
                  icon: Icons.square,
                  color: C.yellow,
                  text: drop ?? 'Where to?',
                  onTap: () => _pickLocation(false),
                  onWhatsAppTap: () => _showWhatsAppLocationExtractorDialog(isDropLocation: true),
                  onClear: dropLocation != null
                      ? () {
                          setState(() {
                            dropLocation = null;
                            drop = null;
                            _routeDetails = null;
                          });
                        }
                      : null,
                ),
                if (dropLocation != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: Color(0xFF1E7E34)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '📍 Destination GPS Coordinates: ${dropLocation!.latitude.toStringAsFixed(5)}, ${dropLocation!.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF1E7E34), fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setState(() {
                              dropLocation = null;
                              drop = null;
                              _routeDetails = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.close, size: 12, color: Colors.red),
                                SizedBox(width: 2),
                                Text('Clear', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => _fetchCurrentLocation(userInitiated: true),
                      icon: const Icon(Icons.my_location, color: C.black, size: 18),
                      label: const Text('Use GPS location', style: TextStyle(color: C.black, fontSize: 13)),
                    ),
                    if (dropLocation != null)
                      Text(
                        'Est: PKR $fare',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: C.black),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                PrimaryButton(
                  'Continue',
                  onTap: dropLocation == null ? null : () => _showFare(context, distMeters, durationSecs, fare, distKm),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showFare(BuildContext context, double distMeters, double durationSecs, int fare, double distKm) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bottomSheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ride summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text('$pickup  →  $drop', style: const TextStyle(color: Colors.black54)),
            const Divider(height: 24),
            _Row('Distance', LocationService.formatDistance(distMeters)),
            _Row('Estimated travel time', LocationService.formatDuration(durationSecs)),
            _Row('Estimated fare', 'PKR $fare'),
            const _Row('Payment method', 'Cash'),
            const SizedBox(height: 20),
            PrimaryButton('Request Ride', onTap: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              // 1. If not logged in, prompt user to Login/Signup before requesting
              var user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                final didLogin = await nav.push<bool>(
                  MaterialPageRoute(builder: (_) => const LoginScreen(asModal: true)),
                );
                if (didLogin != true) return;
                user = FirebaseAuth.instance.currentUser;
              }

              // 2. Ensure profile details (phone number) are completed
              final authUser = user;
              if (authUser != null) {
                final authService = AuthService();
                final data = await authService.getUserData(authUser.uid);

                // Check if passenger account is suspended
                if (data?['isSuspended'] == true) {
                  if (context.mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Your account has been suspended by Admin. Please contact helpline.'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  return;
                }

                if (!AuthService.isProfileComplete(data)) {
                  final didComplete = await nav.push<bool>(
                    MaterialPageRoute(
                      builder: (_) => CompleteProfileScreen(
                        uid: authUser.uid,
                        initialName: authUser.displayName,
                        initialEmail: authUser.email,
                        initialPhone: authUser.phoneNumber,
                        asModal: true,
                      ),
                    ),
                  );
                  if (didComplete != true) return;
                }
              }

              if (!context.mounted) return;
              Navigator.pop(bottomSheetContext);
              try {
                final curUser = FirebaseAuth.instance.currentUser;
                final authService = AuthService();
                final userData = curUser != null ? await authService.getUserData(curUser.uid) : null;
                final custName = userData?['name'] ?? curUser?.displayName ?? 'Customer';
                final custPhone = userData?['phone'] ?? curUser?.phoneNumber ?? '';

                final rideId = await _rideService.requestRide(
                  customerId: curUser?.uid ?? 'guest_cust',
                  customerName: custName,
                  customerPhone: custPhone,
                  pickupAddress: pickup,
                  dropAddress: drop!,
                  pickupLocation: pickupLocation,
                  dropLocation: dropLocation!,
                  estimatedFare: fare.toDouble(),
                  distanceKm: distKm,
                );
                if (mounted) {
                  nav.push(
                    MaterialPageRoute(builder: (_) => SearchingScreen(rideId: rideId)),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Firebase error: $e'),
                      backgroundColor: Colors.red.shade800,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            }),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String a, b;
  const _Row(this.a, this.b);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: const TextStyle(color: Colors.black54, fontSize: 14)),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      );
}

class _LocField extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
  final VoidCallback? onWhatsAppTap;
  final VoidCallback? onClear;
  const _LocField({
    required this.icon,
    required this.color,
    required this.text,
    required this.onTap,
    this.onWhatsAppTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: C.grey, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onClear != null)
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.black45, size: 20),
                tooltip: 'Clear destination',
                onPressed: onClear,
              ),
            if (onWhatsAppTap != null) ...[
              Container(
                height: 24,
                width: 1,
                color: Colors.grey.shade300,
              ),
              IconButton(
                icon: const Icon(Icons.share_location, color: Color(0xFF25D366), size: 20),
                tooltip: 'Import WhatsApp / Google Maps link',
                onPressed: onWhatsAppTap,
              ),
            ],
          ],
        ),
      );
}

class SearchLocationScreen extends StatefulWidget {
  final bool isPickup;
  final LatLng? currentPickup;
  final String? currentAddress;
  const SearchLocationScreen({
    super.key,
    this.isPickup = false,
    this.currentPickup,
    this.currentAddress,
  });

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;
  List<PlaceItem> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  List<PlaceItem> _popularPlaces = LocationService.localLandmarks;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _focusNode.requestFocus();
    });
    _loadPopularPlaces();
  }

  Future<void> _loadPopularPlaces() async {
    final places = await LocationService.getLocalPlaces();
    if (!mounted) return;
    final sorted = List<PlaceItem>.from(places);
    if (widget.currentPickup != null) {
      sorted.sort((a, b) {
        final distA = LocationService.getDistanceBetween(widget.currentPickup!, a.location);
        final distB = LocationService.getDistanceBetween(widget.currentPickup!, b.location);
        return distA.compareTo(distB);
      });
    }
    setState(() {
      _popularPlaces = sorted;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showWhatsAppLocationExtractorDialog() {
    final urlController = TextEditingController();
    bool extracting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
                child: const Icon(Icons.share_location, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.isPickup ? 'Import Pickup Location' : 'Import Destination Location',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isPickup
                      ? 'Paste the Google Maps link or WhatsApp message received for Pickup:'
                      : 'Paste the Google Maps link or WhatsApp message received for Destination:',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'e.g. https://maps.app.goo.gl/xxxx or 32.986, 70.604',
                    filled: true,
                    fillColor: C.grey,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: 'Paste from clipboard',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          setModalState(() {
                            urlController.text = data!.text!;
                          });
                        }
                      },
                    ),
                  ),
                ),
                if (extracting) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator(color: C.yellow)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
              icon: const Icon(Icons.pin_drop, size: 18),
              label: const Text('Extract & Set Location'),
              onPressed: extracting
                  ? null
                  : () async {
                      final text = urlController.text.trim();
                      if (text.isEmpty) return;

                      final nav = Navigator.of(ctx);
                      final rootNav = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);

                      setModalState(() => extracting = true);
                      final result = await LocationService.parseLocationFromMapsLink(text);
                      setModalState(() => extracting = false);

                      if (result != null) {
                        nav.pop();
                        rootNav.pop(result);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('📍 Location resolved: ${result.name} (${result.location.latitude.toStringAsFixed(4)}, ${result.location.longitude.toStringAsFixed(4)})'),
                                ),
                              ],
                            ),
                            backgroundColor: Colors.green.shade700,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Could not extract coordinates from link. Please verify and try again.'),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _hasSearched = false;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 320), () async {
      final results = await LocationService.searchPlaces(
        trimmed,
        proximity: widget.currentPickup,
      );

      // If user's query relates to current / existing location, ensure existing location appears first
      final lower = trimmed.toLowerCase();
      final isCurrentLocQuery = lower.contains('current') ||
          lower.contains('existing') ||
          lower.contains('my location') ||
          lower.contains('here') ||
          lower.contains('present') ||
          lower.contains('gps') ||
          (widget.currentAddress != null &&
              widget.currentAddress!.toLowerCase().contains(lower));

      if (isCurrentLocQuery && widget.currentPickup != null) {
        final currentPlace = PlaceItem(
          name: (widget.currentAddress != null && !widget.currentAddress!.contains('Locating'))
              ? widget.currentAddress!
              : 'Your Current Location',
          subtitle: 'Current GPS Location',
          location: widget.currentPickup!,
        );
        results.removeWhere((p) => p.name == currentPlace.name);
        results.insert(0, currentPlace);
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
          _hasSearched = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isPickup ? 'Set pickup location' : 'Select destination';
    final showSuggestions = _searchController.text.trim().isEmpty;
    final isLinkOrCoords = _searchController.text.contains('http') ||
        _searchController.text.contains('maps.') ||
        _searchController.text.contains('goo.gl') ||
        RegExp(r'-?\d{1,3}\.\d+.*,\s*-?\d{1,3}\.\d+').hasMatch(_searchController.text);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Input Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.isPickup ? 'Search pickup or paste Google Maps link...' : 'Search destination or paste Google Maps link...',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: C.black),
                suffixIcon: _searchController.text.isNotEmpty
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isSearching)
                            const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: C.black),
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          ),
                        ],
                      )
                    : null,
                filled: true,
                fillColor: C.grey,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          // Action banner when Maps link / Coordinates is detected directly in search input
          if (isLinkOrCoords)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.share_location, color: Color(0xFF25D366), size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Google Maps Link / GPS Coordinates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E7E34))),
                        Text('Extract exact GPS pin and address', style: TextStyle(fontSize: 11, color: Colors.black87)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final rootNav = Navigator.of(context);
                      final result = await LocationService.parseLocationFromMapsLink(_searchController.text.trim());
                      if (result != null) {
                        rootNav.pop(result);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('📍 Location resolved: ${result.name}'),
                            backgroundColor: Colors.green.shade700,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Could not extract coordinates from link.'),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: const Text('Extract', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          if (_isSearching && _searchResults.isEmpty)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: C.grey,
              color: C.yellow,
            ),

          Expanded(
            child: showSuggestions
                ? ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      // 1. Existing / Current GPS Location (Top Priority)
                      if (widget.currentPickup != null) ...[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.green.shade400, width: 1.5),
                            ),
                            child: const Icon(Icons.my_location, color: Colors.green, size: 22),
                          ),
                          title: const Text(
                            'Your Current Location',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black87),
                          ),
                          subtitle: Text(
                            (widget.currentAddress != null && !widget.currentAddress!.contains('Locating'))
                                ? widget.currentAddress!
                                : 'Existing GPS Location (${widget.currentPickup!.latitude.toStringAsFixed(4)}, ${widget.currentPickup!.longitude.toStringAsFixed(4)})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Use This',
                              style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                          onTap: () {
                            final placeName = (widget.currentAddress != null && !widget.currentAddress!.contains('Locating'))
                                ? widget.currentAddress!
                                : 'Current Location';
                            Navigator.pop(
                              context,
                              PlaceItem(
                                name: placeName,
                                subtitle: 'Current GPS Location',
                                location: widget.currentPickup!,
                              ),
                            );
                          },
                        ),
                        const Divider(height: 16, indent: 18, endIndent: 18),
                      ],

                      // 2. Interactive Map Selection Option
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: C.yellow.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.map, color: Colors.black87, size: 20),
                        ),
                        title: Text(
                          widget.isPickup ? 'Choose pickup on map' : 'Choose destination on map',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        subtitle: Text(
                          'Tap anywhere directly on the interactive map',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                        trailing: const Icon(Icons.touch_app, size: 20, color: Colors.black54),
                        onTap: () => Navigator.pop(context),
                      ),
                      const Divider(height: 16, indent: 18, endIndent: 18),

                      // 3. WhatsApp Map Link Import Option
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Color(0xFF25D366),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.share_location, color: Colors.white, size: 20),
                        ),
                        title: const Text(
                          'Import from WhatsApp Google Maps Link',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E7E34)),
                        ),
                        subtitle: const Text(
                          'Paste maps.app.goo.gl link, WhatsApp pin or raw GPS coordinates',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Paste Link',
                            style: TextStyle(color: Color(0xFF1E7E34), fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        onTap: _showWhatsAppLocationExtractorDialog,
                      ),
                      const Divider(height: 16, indent: 18, endIndent: 18),

                      // 4. Popular Places in the Area Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                        child: Row(
                          children: [
                            Icon(Icons.stars_rounded, size: 18, color: Colors.orange.shade700),
                            const SizedBox(width: 6),
                            const Text(
                              'Popular Places in Bannu',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      ..._popularPlaces.take(10).map((place) => _buildPlaceTile(place, isSuggested: true)),

                      const Divider(height: 24, indent: 18, endIndent: 18),

                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.travel_explore, color: Colors.blue.shade700, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Live Places Search & Proximity Bias',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Type any address, road, shop, or landmark above to find it in real-time prioritized near your location.',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : _searchResults.isNotEmpty
                    ? ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => Divider(height: 1, indent: 64, color: Colors.grey.shade200),
                        itemBuilder: (_, index) => _buildPlaceTile(_searchResults[index]),
                      )
                    : _hasSearched && !_isSearching
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_off_outlined, size: 56, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No places found for "${_searchController.text.trim()}"',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try checking the spelling or search by city name (e.g. Bannu, Cantt, Bazaar).',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceTile(PlaceItem place, {bool isSuggested = false}) {
    String distanceText = '';
    if (widget.currentPickup != null) {
      final meters = LocationService.getDistanceBetween(widget.currentPickup!, place.location);
      distanceText = LocationService.formatDistance(meters);
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: place.subtitle == 'Current GPS Location'
              ? Colors.green.shade50
              : isSuggested
                  ? C.yellow.withValues(alpha: 0.2)
                  : C.grey,
          shape: BoxShape.circle,
        ),
        child: Icon(
          place.subtitle == 'Current GPS Location'
              ? Icons.my_location
              : isSuggested
                  ? Icons.near_me_outlined
                  : Icons.location_on,
          color: place.subtitle == 'Current GPS Location' ? Colors.green.shade700 : Colors.black87,
          size: 20,
        ),
      ),
      title: Text(
        place.name,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      subtitle: place.subtitle.isNotEmpty
          ? Text(
              place.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (distanceText.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                distanceText,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.black87),
              ),
            ),
          const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.black38),
        ],
      ),
      onTap: () => Navigator.pop(context, place),
    );
  }
}

class SearchingScreen extends StatefulWidget {
  final String rideId;
  const SearchingScreen({super.key, required this.rideId});

  @override
  State<SearchingScreen> createState() => _SearchingScreenState();
}

class _SearchingScreenState extends State<SearchingScreen> {
  final RideService _rideService = RideService();
  StreamSubscription<RideModel?>? _sub;
  Timer? _searchTimeoutTimer;
  bool _isAccepted = false;
  bool _isDismissed = false;

  void _safeClose({String? snackBarMessage}) {
    if (_isDismissed) return;
    _isDismissed = true;
    _searchTimeoutTimer?.cancel();
    _sub?.cancel();
    if (mounted) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (snackBarMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackBarMessage),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // 90-second search timeout: Auto-expire/cancel if no driver accepts
    _searchTimeoutTimer = Timer(const Duration(seconds: 90), () async {
      if (!_isAccepted && !_isDismissed && mounted) {
        await _rideService.cancelRide(widget.rideId);
        _safeClose(
          snackBarMessage: 'No riders accepted within 90s. Please try requesting again.',
        );
      }
    });

    _sub = _rideService.streamRide(widget.rideId).listen((ride) {
      if (ride != null && (ride.status == 'accepted' || ride.status == 'in_progress')) {
        _isAccepted = true;
        _isDismissed = true;
        _searchTimeoutTimer?.cancel();
        _sub?.cancel();
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ActiveRideScreen(rideId: widget.rideId, rider: false),
            ),
          );
        }
      } else if (ride != null && (ride.status == 'cancelled' || ride.status == 'expired')) {
        _safeClose(
          snackBarMessage: ride.status == 'expired'
              ? 'Ride request timed out. Please try requesting again.'
              : 'Ride request was cancelled.',
        );
      }
    });
  }

  @override
  void dispose() {
    _isDismissed = true;
    _searchTimeoutTimer?.cancel();
    _sub?.cancel();
    if (!_isAccepted) {
      // Clean up orphaned requested ride from Firestore if user backed out
      _rideService.cancelRide(widget.rideId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            _isDismissed = true;
            _searchTimeoutTimer?.cancel();
            _sub?.cancel();
            if (!_isAccepted) {
              _rideService.cancelRide(widget.rideId);
            }
          }
        },
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(width: 90, height: 90, child: CircularProgressIndicator(color: C.yellow, strokeWidth: 8)),
                const SizedBox(height: 28),
                const Text('Finding nearby riders…', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Looking for nearby drivers (up to 90s)…', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 40),
                PrimaryButton(
                  'Cancel request',
                  bg: C.black,
                  fg: C.white,
                  onTap: () async {
                    _searchTimeoutTimer?.cancel();
                    _sub?.cancel();
                    await _rideService.cancelRide(widget.rideId);
                    _safeClose(snackBarMessage: 'Ride request was cancelled.');
                  },
                ),
              ]),
            ),
          ),
        ),
      );
}
