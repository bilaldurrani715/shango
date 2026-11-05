import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/live_map_view.dart';
import 'auth.dart';
import 'complete_profile_screen.dart';
import 'incoming_ride_screen.dart';
import 'ride.dart';
import 'rider_dashboard_screen.dart';

class RiderHome extends StatefulWidget {
  const RiderHome({super.key});
  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> with WidgetsBindingObserver {
  final RideService _rideService = RideService();
  bool online = false;
  LatLng riderLocation = LocationService.defaultLocation;
  StreamSubscription<List<RideModel>>? _ridesSub;
  StreamSubscription<Position>? _riderGpsSub;
  StreamSubscription<RideModel?>? _promptedRideSub;
  StreamSubscription<Map<String, dynamic>>? _fcmRideSub;
  Timer? _heartbeatTimer;
  String? _currentPromptedRideId;
  BuildContext? _requestSheetContext;
  bool _isSheetShowing = false;
  bool _isOnActiveRide = false;
  final Set<String> _dismissedRideIds = {};

  // Maximum radius in meters to consider a ride request "nearby"
  static const double maxRadiusMeters = 7000; // 7 km radius

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchRiderLocation();
    _checkInitialOnlineStatus();

    // Listen to foreground FCM ride broadcast events
    _fcmRideSub = NotificationService.incomingRideStream.stream.listen((event) {
      if (!online || !mounted || _isOnActiveRide) return;
      final type = event['type'];
      final rideId = (event['ride_request_id'] ?? event['rideId']) as String?;

      if (type == 'NEW_RIDE_REQUEST' && rideId != null) {
        if (!_isSheetShowing && !_dismissedRideIds.contains(rideId)) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IncomingRideRequestScreen(
                rideId: rideId,
                riderLocation: riderLocation,
              ),
            ),
          );
        }
      } else if ((type == 'RIDE_CANCELLED' || type == 'RIDE_NO_LONGER_AVAILABLE') && rideId != null) {
        if (_currentPromptedRideId == rideId) {
          _dismissCurrentRequest(reason: 'Ride was accepted by another rider or cancelled.');
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Note: Do not mark rider offline when app is detached/minimized,
    // so the rider remains online in Firestore and continues receiving
    // high-priority ride requests via Railway push notifications while closed.
  }

  Future<void> _checkInitialOnlineStatus() async {
    final curUid = FirebaseAuth.instance.currentUser?.uid;
    if (curUid != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('online_riders').doc(curUid).get();
        if (doc.exists && doc.data()?['isOnline'] == true && mounted) {
          _toggleOnline(true);
        }
      } catch (e) {
        debugPrint('Error restoring rider online status: $e');
      }
    }
  }

  Future<void> _fetchRiderLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() {
        riderLocation = loc;
      });
      final curUid = FirebaseAuth.instance.currentUser?.uid;
      if (curUid != null && online) {
        _rideService.updateOnlineRiderPosition(uid: curUid, location: loc);
      }
    }
  }

  Future<void> _makeCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching call: $e');
    }
  }

  Future<void> _openWhatsApp(String phone, String text) async {
    final clean = phone.replaceAll(RegExp(r'[^\d]'), '');
    final url = 'https://wa.me/$clean?text=${Uri.encodeComponent(text)}';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching WhatsApp: $e');
    }
  }

  Future<void> _toggleOnline(bool v) async {
    if (v) {
      var user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final didLogin = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen(asModal: true)),
        );
        if (didLogin != true) return;
      }

      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        final authService = AuthService();
        final data = await authService.getUserData(authUser.uid);
        if (!AuthService.isProfileComplete(data)) {
          if (!mounted) return;
          final didComplete = await Navigator.push<bool>(
            context,
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

        // Check if driver account is suspended
        if (data?['isSuspended'] == true) {
          if (!mounted) return;
          final contact = await _rideService.getAdminContactInfo();
          final adminPhone = contact['adminPhone'] ?? '+923451234567';
          final adminWhatsApp = contact['adminWhatsApp'] ?? adminPhone;
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.block, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Account Suspended', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: const Text(
                'Your driver account has been suspended by ShanGo Admin. Please contact the official admin helpline for assistance.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                TextButton.icon(
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Call Admin'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _makeCall(adminPhone);
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text('Admin WhatsApp'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openWhatsApp(adminWhatsApp, 'Hello ShanGo Admin, my driver account has been suspended. Please assist me.');
                  },
                ),
              ],
            ),
          );
          return;
        }

        // Check if driver account is approved by admin
        if (data?['isApproved'] != true) {
          if (!mounted) return;
          final contact = await _rideService.getAdminContactInfo();
          final adminPhone = contact['adminPhone'] ?? '+923451234567';
          final adminWhatsApp = contact['adminWhatsApp'] ?? adminPhone;
          final driverName = data?['name'] ?? data?['displayName'] ?? 'Driver';
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.pending_actions, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Pending Admin Approval', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your driver account is currently under review by ShanGo Admin.\n\nOnce approved from the Admin Panel, you will be able to go online and receive nearby ride requests.',
                    style: TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9E6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.support_agent, color: Colors.orange, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Admin Helpline:', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
                              Text(adminPhone, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.black87)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
                TextButton.icon(
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Call'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _makeCall(adminPhone);
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text('WhatsApp Admin'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openWhatsApp(adminWhatsApp, 'Hello ShanGo Admin, I am $driverName. I have created a driver account and am waiting for admin approval.');
                  },
                ),
              ],
            ),
          );
          return;
        }

        // If location is still default fallback, attempt quick GPS fix
        if (riderLocation.latitude == LocationService.defaultLocation.latitude &&
            riderLocation.longitude == LocationService.defaultLocation.longitude) {
          final quickPos = await LocationService.getCurrentPosition();
          if (quickPos != null) {
            riderLocation = LatLng(quickPos.latitude, quickPos.longitude);
          }
        }

        // Register online rider in Firestore
        await _rideService.setRiderOnlineStatus(
          uid: authUser.uid,
          isOnline: true,
          location: riderLocation,
          vehicleType: data?['vehicleType'],
          vehicleModel: data?['vehicleModel'],
        );

        // Refresh & save FCM token to users and online_riders
        await NotificationService().saveUserFcmToken(authUser.uid);
      }
    } else {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        await _rideService.setRiderOnlineStatus(uid: authUser.uid, isOnline: false);
      }
    }

    setState(() => online = v);
    if (v) {
      // Clean up any stale or dummy requests left behind in Firestore
      _rideService.purgeStaleRequestedRides();

      final curUid = FirebaseAuth.instance.currentUser?.uid;
      _riderGpsSub = LocationService.getPositionStream(distanceFilter: 5).listen((pos) {
        final newLoc = LatLng(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() => riderLocation = newLoc);
        }
        if (curUid != null) {
          _rideService.updateOnlineRiderPosition(uid: curUid, location: newLoc);
        }
      });

      // Heartbeat every 40s to keep rider online freshness timestamp valid
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 40), (_) {
        if (curUid != null && online) {
          _rideService.updateOnlineRiderPosition(uid: curUid, location: riderLocation);
        }
      });

      _ridesSub = _rideService.streamAvailableRides().listen((rides) {
        if (!online || !mounted || _isOnActiveRide) return;

        // Clean up dismissed IDs that are no longer active requested rides in the system
        _dismissedRideIds.removeWhere((id) => !rides.any((r) => r.id == id));

        // If a request is currently shown, check if it was accepted by another rider or cancelled
        if (_currentPromptedRideId != null && _isSheetShowing) {
          final isStillRequested = rides.any((r) => r.id == _currentPromptedRideId);
          if (!isStillRequested) {
            _dismissCurrentRequest(reason: 'Ride was accepted by another rider or cancelled.');
            return;
          }
        }

        // If no sheet is currently showing, look for nearby fresh available rides
        if (!_isSheetShowing) {
          final now = DateTime.now();
          final nearbyRides = rides.where((ride) {
            if (_dismissedRideIds.contains(ride.id)) return false;
            // Prevent old/dummy requests from showing
            final ageSeconds = now.difference(ride.createdAt).inSeconds;
            if (ageSeconds > RideService.maxRideRequestAgeSeconds) return false;

            final distToPickup = LocationService.getDistanceBetween(riderLocation, ride.pickupLocation);
            return distToPickup <= maxRadiusMeters;
          }).toList();

          if (nearbyRides.isNotEmpty) {
            final ride = nearbyRides.first;
            _showRequest(ride);
          }
        }
      });
    } else {
      _dismissCurrentRequest();
      _ridesSub?.cancel();
      _riderGpsSub?.cancel();
      _heartbeatTimer?.cancel();
      // Keep dismissed IDs active in memory so toggling off/on does not immediately re-prompt rejected rides
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dismissCurrentRequest();
    _fcmRideSub?.cancel();
    _ridesSub?.cancel();
    _riderGpsSub?.cancel();
    _heartbeatTimer?.cancel();
    // Do not mark offline in Firestore on dispose so background receiving continues
    super.dispose();
  }

  void _dismissCurrentRequest({String? reason}) {
    _promptedRideSub?.cancel();
    _promptedRideSub = null;

    if (_isSheetShowing && _requestSheetContext != null && _requestSheetContext!.mounted) {
      Navigator.of(_requestSheetContext!).pop();
    }
    _isSheetShowing = false;
    _requestSheetContext = null;
    _currentPromptedRideId = null;

    if (reason != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reason,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showRequest(RideModel ride) {
    if (_isSheetShowing || _isOnActiveRide || !mounted) return;

    _isSheetShowing = true;
    _currentPromptedRideId = ride.id;

    // Direct real-time listener on the prompted ride document.
    // If accepted by another rider or cancelled by passenger, auto-dismiss instantly!
    _promptedRideSub?.cancel();
    _promptedRideSub = _rideService.streamRide(ride.id).listen((liveRide) {
      if (liveRide != null && liveRide.status != 'requested') {
        final reason = (liveRide.status == 'accepted')
            ? 'This ride was accepted by another rider.'
            : 'This ride request is no longer active.';
        _dismissCurrentRequest(reason: reason);
      }
    });

    final distanceToPickup = LocationService.getDistanceBetween(riderLocation, ride.pickupLocation);

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        _requestSheetContext = sheetContext;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('New ride request', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      '${LocationService.formatDistance(distanceToPickup)} away',
                      style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RideRequestTimerBar(
                totalSeconds: 20,
                onTimeout: () {
                  if (_isSheetShowing && _currentPromptedRideId == ride.id) {
                    _dismissedRideIds.add(ride.id);
                    _dismissCurrentRequest();
                  }
                },
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.circle, color: Colors.green, size: 14),
                title: Text(ride.pickupAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Pickup point', style: TextStyle(fontSize: 12)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.square, color: C.yellow, size: 14),
                title: Text(ride.dropAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Drop destination', style: TextStyle(fontSize: 12)),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Trip: ${LocationService.formatDistance(ride.distanceKm * 1000)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                  Text(
                    'PKR ${ride.estimatedFare.toStringAsFixed(0)} (Cash)',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.black),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      'Reject',
                      bg: Colors.red.shade600,
                      fg: C.white,
                      onTap: () {
                        _dismissedRideIds.add(ride.id);
                        _dismissCurrentRequest();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      'Accept',
                      bg: Colors.green.shade600,
                      fg: C.white,
                      onTap: () async {
                        // Dismiss prompt sheet cleanly
                        _promptedRideSub?.cancel();
                        _promptedRideSub = null;
                        if (_isSheetShowing && _requestSheetContext != null && _requestSheetContext!.mounted) {
                          Navigator.of(_requestSheetContext!).pop();
                        }
                        _isSheetShowing = false;
                        _requestSheetContext = null;
                        _currentPromptedRideId = null;

                        final user = FirebaseAuth.instance.currentUser;
                        final authService = AuthService();
                        final userData = user != null ? await authService.getUserData(user.uid) : null;

                        final riderName = userData?['name'] ?? user?.displayName ?? 'Rider';
                        final riderPhone = userData?['phone'] ?? user?.phoneNumber ?? '';
                        final vehicleType = userData?['vehicleType'] ?? 'Bike';
                        final vehicleModel = userData?['vehicleModel'] ?? 'Motorbike';
                        final plateNumber = userData?['plateNumber'] ?? '';

                        final accepted = await _rideService.acceptRide(
                          rideId: ride.id,
                          riderId: user?.uid ?? 'rider_1',
                          riderName: riderName,
                          riderPhone: riderPhone,
                          vehicleType: vehicleType,
                          vehicleModel: vehicleModel,
                          plateNumber: plateNumber,
                          riderLocation: riderLocation,
                        );

                        if (accepted) {
                          if (mounted) {
                            _isOnActiveRide = true;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ActiveRideScreen(rideId: ride.id, rider: true),
                              ),
                            );
                            _isOnActiveRide = false;
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.white, size: 20),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'This ride was already accepted by another rider!',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: Colors.red.shade700,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      _promptedRideSub?.cancel();
      _promptedRideSub = null;
      _isSheetShowing = false;
      _requestSheetContext = null;
      _currentPromptedRideId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final curUser = FirebaseAuth.instance.currentUser;

    return Stack(
      children: [
        Positioned.fill(
          child: LiveMapView(
            riderLocation: riderLocation,
          ),
        ),

        // 0. Offline Cached Map Warning Banner
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(child: OfflineBanner()),
        ),

        // Floating Scheduled Intercity Trips Banner for Driver
        if (curUser != null)
          Positioned(
            top: 16,
            left: 16,
            right: 70,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('intercity_bookings')
                  .where('riderId', isEqualTo: curUser.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final activeDocs = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final status = data['status'] ?? '';
                  return status == 'confirmed' || status == 'in_progress' || status == 'scheduled';
                }).toList();

                if (activeDocs.isEmpty) {
                  return const SizedBox.shrink();
                }

                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => RiderAssignedIntercityScreen(uid: curUser.uid)),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: C.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: C.yellow, width: 1.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: C.yellow, shape: BoxShape.circle),
                          child: const Icon(Icons.airport_shuttle, color: C.black, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${activeDocs.length} Scheduled Intercity Trip(s)',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                              ),
                              Text(
                                'Assigned by Admin • Tap to view & contact passenger',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, color: C.yellow, size: 12),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

        Align(
          alignment: Alignment.bottomCenter,
          child: BottomCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: C.black,
                  activeTrackColor: C.yellow,
                  title: Text(
                    online ? "You're online" : "You're offline",
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  subtitle: Text(online ? 'Searching within 7 km radius…' : 'Go online to receive nearby requests'),
                  value: online,
                  onChanged: _toggleOnline,
                ),
                const Divider(),
                Builder(
                  builder: (_) {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      return const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Stat('Today rides', '0'),
                          _Stat('Today earnings', 'PKR 0'),
                        ],
                      );
                    }
                    return StreamBuilder<Map<String, num>>(
                      stream: _rideService.streamRiderTodayStats(user.uid),
                      builder: (context, snapshot) {
                        final count = snapshot.data?['rides']?.toInt() ?? 0;
                        final earnings = snapshot.data?['earnings']?.toDouble() ?? 0.0;
                        return Column(
                          children: [
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RiderDashboardScreen(riderId: user.uid),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _Stat('Today rides', '$count'),
                                    Container(height: 30, width: 1, color: Colors.grey.shade300),
                                    _Stat('Today earnings', 'PKR ${earnings.toStringAsFixed(0)}'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RiderDashboardScreen(riderId: user.uid),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: C.black,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.dashboard_rounded, color: C.yellow, size: 16),
                                    SizedBox(width: 8),
                                    Text(
                                      'View Full Dashboard & Earnings',
                                      style: TextStyle(color: C.yellow, fontWeight: FontWeight.w900, fontSize: 13),
                                    ),
                                    SizedBox(width: 6),
                                    Icon(Icons.arrow_forward_ios, color: C.yellow, size: 11),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String a, b;
  const _Stat(this.a, this.b);
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(b, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(a, style: const TextStyle(color: Colors.black54)),
        ],
      );
}

// =========================================================================
// SCREEN: DRIVER'S ASSIGNED SCHEDULED INTERCITY TRIPS
// =========================================================================
class RiderAssignedIntercityScreen extends StatefulWidget {
  final String? uid;
  const RiderAssignedIntercityScreen({super.key, this.uid});

  @override
  State<RiderAssignedIntercityScreen> createState() => _RiderAssignedIntercityScreenState();
}

class _RiderAssignedIntercityScreenState extends State<RiderAssignedIntercityScreen> {
  final RideService _rideService = RideService();
  final AuthService _authService = AuthService();

  Future<void> _makeCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching call: $e');
    }
  }

  Future<void> _openWhatsApp(String phone, String text) async {
    final clean = phone.replaceAll(RegExp(r'[^\d]'), '');
    final url = 'https://wa.me/$clean?text=${Uri.encodeComponent(text)}';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching WhatsApp: $e');
    }
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error opening maps: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final curUid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid;

    if (curUid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Scheduled Trips')),
        body: const Center(child: Text('Please log in as a driver.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Assigned Intercity Trips',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          // 1. Driver Availability Toggle Card
          StreamBuilder<Map<String, dynamic>?>(
            stream: _authService.streamUserProfile(curUid),
            builder: (context, profileSnap) {
              final profileData = profileSnap.data ?? {};
              final bool isAvailable = profileData['isAvailableForScheduled'] ?? true;

              return Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isAvailable ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isAvailable ? const Color(0xFF86EFAC) : const Color(0xFFFECACA),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isAvailable ? const Color(0xFF166534) : Colors.red.shade700,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isAvailable ? Icons.schedule : Icons.event_busy,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAvailable ? 'Available for Scheduled Rides' : 'Scheduled Rides Paused',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: isAvailable ? const Color(0xFF166534) : Colors.red.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isAvailable
                                ? 'Admin can assign you city-to-city rides'
                                : 'You are disabled for new admin bookings',
                            style: TextStyle(
                              fontSize: 11,
                              color: isAvailable ? const Color(0xFF15803D) : Colors.red.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isAvailable,
                      activeThumbColor: const Color(0xFF166534),
                      activeTrackColor: const Color(0xFFBBF7D0),
                      onChanged: (val) async {
                        await _authService.setDriverScheduledAvailability(curUid, val);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(val
                                  ? 'You are now AVAILABLE for scheduled rides.'
                                  : 'Scheduled rides PAUSED. Admin cannot assign you new trips.'),
                              backgroundColor: val ? Colors.green : Colors.black87,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          // 2. Assigned Trips List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('intercity_bookings')
                  .where('riderId', isEqualTo: curUid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: C.yellow));
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.airport_shuttle_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            'No Scheduled Trips Assigned',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'When Admin links and assigns you to an on-demand intercity trip, it will appear here with full passenger details, pickup map pins, and WhatsApp messaging.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final bookingId = doc.id;

              final from = data['fromCity'] ?? 'Bannu';
              final to = data['toCity'] ?? 'Peshawar';
              final fare = data['fare'] ?? 0;
              final vehicle = data['vehicleType'] ?? 'Car';
              final isRoundTrip = data['isRoundTrip'] == true || data['tripType'] == 'two_way';
              final dateStr = data['scheduledDate'] ?? '';
              final timeStr = data['scheduledTime'] ?? '';
              final returnDate = data['returnDate'];
              final returnTime = data['returnTime'];
              final status = data['status'] ?? 'confirmed';
              final customerName = data['customerName'] ?? 'Passenger';
              final customerPhone = data['customerPhone'] ?? '';
              final pickupAddress = data['pickupAddress'] ?? '';
              final dropAddress = data['dropAddress'] ?? '';
              final notes = data['notes'] as String?;
              final pickupCoordinates = data['pickupCoordinates'] as Map<String, dynamic>?;
              final dropCoordinates = data['dropCoordinates'] as Map<String, dynamic>?;

              Color statusBg = Colors.green.shade100;
              Color statusFg = Colors.green.shade900;
              if (status == 'completed') {
                statusBg = Colors.blue.shade100;
                statusFg = Colors.blue.shade900;
              } else if (status == 'in_progress') {
                statusBg = Colors.amber.shade100;
                statusFg = Colors.amber.shade900;
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            isRoundTrip ? '$from ⇄ $to' : '$from ➔ $to',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(10)),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(color: statusFg, fontWeight: FontWeight.w800, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '🗓 Departure: $dateStr at $timeStr • $vehicle',
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (isRoundTrip && returnDate != null)
                      Text(
                        '🔄 Return: $returnDate at ${returnTime ?? ""}',
                        style: TextStyle(color: Colors.green.shade800, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      'Trip Earning / Fare: PKR $fare (Cash)',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.black),
                    ),
                    const Divider(height: 18),

                    // Passenger Details & Direct Actions
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 14,
                                backgroundColor: Color(0xFF25D366),
                                child: Icon(Icons.person, color: Colors.white, size: 16),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Passenger: $customerName', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                    if (customerPhone.isNotEmpty)
                                      Text('Phone: $customerPhone', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: C.black,
                                    foregroundColor: C.yellow,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.call, size: 16),
                                  label: const Text('Call Passenger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: () => _makeCall(customerPhone),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.chat, size: 16),
                                  label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: () => _openWhatsApp(
                                    customerPhone,
                                    'Hello $customerName, I am your assigned ShanGo driver for your scheduled trip from $from to $to on $dateStr at $timeStr. Please share your pickup instructions.',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Pickup & Destination Address Details
                    if (pickupAddress.isNotEmpty || dropAddress.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: C.grey, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (pickupAddress.isNotEmpty)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on, size: 16, color: Colors.green),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Pickup: $pickupAddress',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (pickupCoordinates != null)
                                    InkWell(
                                      onTap: () => _openMaps(
                                        (pickupCoordinates['latitude'] as num).toDouble(),
                                        (pickupCoordinates['longitude'] as num).toDouble(),
                                      ),
                                      child: const Text('🗺️ Map', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            if (pickupAddress.isNotEmpty && dropAddress.isNotEmpty) const Divider(height: 8),
                            if (dropAddress.isNotEmpty)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.pin_drop, size: 16, color: Colors.red),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Destination: $dropAddress',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (dropCoordinates != null)
                                    InkWell(
                                      onTap: () => _openMaps(
                                        (dropCoordinates['latitude'] as num).toDouble(),
                                        (dropCoordinates['longitude'] as num).toDouble(),
                                      ),
                                      child: const Text('🗺️ Map', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],

                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('📝 Note: "$notes"', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade700)),
                    ],

                    // Driver status buttons
                    if (status != 'completed') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (status == 'confirmed')
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: C.yellow,
                                  foregroundColor: C.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.directions_car, size: 16),
                                label: const Text('Start Trip', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                                onPressed: () async {
                                  await _rideService.updateIntercityBookingStatus(bookingId, 'in_progress');
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip marked as In-Progress!')));
                                  }
                                },
                              ),
                            ),
                          if (status == 'confirmed') const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.check_circle, size: 16),
                              label: const Text('Mark Completed', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                              onPressed: () async {
                                await _rideService.updateIntercityBookingStatus(bookingId, 'completed');
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip marked as Completed!')));
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  ],
),
);
}
}

/// Device-independent countdown progress bar driven by wall-clock time
/// Resilient against Android 'Remove animations' setting and Developer Options animator scaling
class _RideRequestTimerBar extends StatefulWidget {
  final int totalSeconds;
  final VoidCallback onTimeout;

  const _RideRequestTimerBar({
    required this.totalSeconds,
    required this.onTimeout,
  });

  @override
  State<_RideRequestTimerBar> createState() => _RideRequestTimerBarState();
}

class _RideRequestTimerBarState extends State<_RideRequestTimerBar> {
  late final DateTime _endTime;
  Timer? _timer;
  double _progress = 1.0;
  int _secondsRemaining = 20;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.totalSeconds;
    _endTime = DateTime.now().add(Duration(seconds: widget.totalSeconds));

    // High-precision periodic timer based on real wall-clock physical time.
    // Completely immune to Android OS animator scale (0x/0.5x), refresh rate, and accessibility settings!
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final now = DateTime.now();
      final remainingMs = _endTime.difference(now).inMilliseconds;
      if (remainingMs <= 0) {
        t.cancel();
        if (mounted) {
          setState(() {
            _progress = 0.0;
            _secondsRemaining = 0;
          });
        }
        widget.onTimeout();
      } else {
        if (mounted) {
          setState(() {
            _progress = (remainingMs / (widget.totalSeconds * 1000)).clamp(0.0, 1.0);
            _secondsRemaining = (remainingMs / 1000).ceil();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = _secondsRemaining <= 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: isUrgent ? Colors.red.shade700 : Colors.black54,
                ),
                const SizedBox(width: 4),
                Text(
                  'Expires in ${_secondsRemaining}s',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isUrgent ? Colors.red.shade700 : Colors.black54,
                  ),
                ),
              ],
            ),
            if (isUrgent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Respond now!',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress,
            color: isUrgent ? Colors.red.shade600 : C.yellow,
            backgroundColor: C.grey,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

