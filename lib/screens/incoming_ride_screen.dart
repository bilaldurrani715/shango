import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'ride.dart';

class IncomingRideRequestScreen extends StatefulWidget {
  final String rideId;
  final LatLng? riderLocation;

  const IncomingRideRequestScreen({
    super.key,
    required this.rideId,
    this.riderLocation,
  });

  @override
  State<IncomingRideRequestScreen> createState() => _IncomingRideRequestScreenState();
}

class _IncomingRideRequestScreenState extends State<IncomingRideRequestScreen>
    with SingleTickerProviderStateMixin {
  final RideService _rideService = RideService();
  final AuthService _authService = AuthService();

  StreamSubscription<RideModel?>? _rideSub;
  RideModel? _ride;
  bool _loading = true;
  bool _isAccepting = false;
  String? _statusNotice;

  // Countdown timer for request freshness (up to 45 seconds remaining)
  Timer? _countdownTimer;
  int _secondsLeft = 45;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _listenToRide();
  }

  void _listenToRide() {
    _rideSub = _rideService.streamRide(widget.rideId).listen((ride) {
      if (!mounted) return;

      if (ride == null) {
        setState(() {
          _loading = false;
          _statusNotice = 'This ride request was cancelled or no longer exists.';
        });
        _countdownTimer?.cancel();
        return;
      }

      setState(() {
        _ride = ride;
        _loading = false;
      });

      // Calculate real remaining seconds based on ride creation time
      final now = DateTime.now();
      final ageSeconds = now.difference(ride.createdAt).inSeconds;
      final remaining = (RideService.maxRideRequestAgeSeconds - ageSeconds).clamp(0, RideService.maxRideRequestAgeSeconds);

      if (remaining <= 0 || ride.status == 'expired') {
        setState(() {
          _secondsLeft = 0;
          _statusNotice = 'This ride request has expired.';
        });
        _countdownTimer?.cancel();
        NotificationService().cancelRideNotification(widget.rideId);
        return;
      }

      _secondsLeft = remaining;
      _startCountdown();

      if (ride.status == 'accepted') {
        final curUid = FirebaseAuth.instance.currentUser?.uid;
        if (ride.riderId != curUid) {
          setState(() {
            _statusNotice = 'This ride was already accepted by another driver.';
          });
          _countdownTimer?.cancel();
          NotificationService().cancelRideNotification(widget.rideId);
        }
      } else if (ride.status == 'cancelled') {
        setState(() {
          _statusNotice = 'The passenger has cancelled this ride request.';
        });
        _countdownTimer?.cancel();
        NotificationService().cancelRideNotification(widget.rideId);
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        setState(() {
          _secondsLeft = 0;
          _statusNotice = 'This ride request has expired.';
        });
        timer.cancel();
        NotificationService().cancelRideNotification(widget.rideId);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _rideSub?.cancel();
    super.dispose();
  }

  Future<void> _handleAccept() async {
    if (_ride == null || _isAccepting) return;
    if (_ride!.status != 'requested') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_statusNotice ?? 'This ride is no longer available.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      return;
    }

    setState(() => _isAccepting = true);

    final user = FirebaseAuth.instance.currentUser;
    final userData = user != null ? await _authService.getUserData(user.uid) : null;

    final riderName = userData?['name'] ?? user?.displayName ?? 'Rider';
    final riderPhone = userData?['phone'] ?? user?.phoneNumber ?? '';
    final vehicleType = userData?['vehicleType'] ?? 'Bike';
    final vehicleModel = userData?['vehicleModel'] ?? 'Motorbike';
    final plateNumber = userData?['plateNumber'] ?? '';

    // Determine current rider location
    LatLng currentLoc = widget.riderLocation ?? LocationService.defaultLocation;
    final livePos = await LocationService.getCurrentPosition();
    if (livePos != null) {
      currentLoc = LatLng(livePos.latitude, livePos.longitude);
    }

    final accepted = await _rideService.acceptRide(
      rideId: widget.rideId,
      riderId: user?.uid ?? 'rider_1',
      riderName: riderName,
      riderPhone: riderPhone,
      vehicleType: vehicleType,
      vehicleModel: vehicleModel,
      plateNumber: plateNumber,
      riderLocation: currentLoc,
    );

    if (!mounted) return;
    setState(() => _isAccepting = false);

    // Cancel notification banner/sound for this ride
    await NotificationService().cancelRideNotification(widget.rideId);
    if (!mounted) return;

    if (accepted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveRideScreen(rideId: widget.rideId, rider: true),
        ),
      );
    } else {
      setState(() {
        _statusNotice = 'This ride was already accepted by another driver!';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Another driver accepted this ride first!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _handleReject() {
    NotificationService().cancelRideNotification(widget.rideId);
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          NotificationService().cancelRideNotification(widget.rideId);
        }
      },
      child: Scaffold(
        backgroundColor: C.black,
        appBar: AppBar(
          backgroundColor: C.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _handleReject,
          ),
          title: const Text(
            'INCOMING RIDE REQUEST',
            style: TextStyle(
              color: C.yellow,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          centerTitle: true,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: C.yellow))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  children: [
                    // 1. Status Notice Banner (if expired or accepted by someone else)
                    if (_statusNotice != null) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.red.shade400, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _statusNotice!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 2. Animated Circular Expiry Countdown Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _statusNotice != null
                              ? Colors.grey.shade800
                              : C.yellow.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) => Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _statusNotice != null
                                        ? Colors.grey
                                        : C.yellow.withValues(alpha: 0.4 + _pulseController.value * 0.6),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _statusNotice != null
                                    ? 'REQUEST INACTIVE'
                                    : 'EXPIRES IN $_secondsLeft SECONDS',
                                style: TextStyle(
                                  color: _statusNotice != null ? Colors.grey : C.yellow,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: (_secondsLeft / RideService.maxRideRequestAgeSeconds).clamp(0.0, 1.0),
                              backgroundColor: Colors.white10,
                              color: _secondsLeft < 15 ? Colors.redAccent : C.yellow,
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Fare Highlight Card
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Guaranteed Fare',
                                      style: TextStyle(color: Colors.white60, fontSize: 12),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Cash on Delivery',
                                      style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'PKR ${(ride?.estimatedFare ?? 0).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: C.yellow,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. Passenger Profile Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: C.yellow,
                            child: Text(
                              (ride?.customerName.isNotEmpty == true)
                                  ? ride!.customerName[0].toUpperCase()
                                  : 'P',
                              style: const TextStyle(
                                color: C.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ride?.customerName.isNotEmpty == true
                                      ? ride!.customerName
                                      : 'Passenger Nearby',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    const Text(
                                      '4.9',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Verified Passenger',
                                        style: TextStyle(color: Colors.white70, fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 4. Route Details Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Pickup Point
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.green,
                                ),
                                child: const Icon(Icons.circle, size: 8, color: Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'PICKUP LOCATION',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      ride?.pickupAddress.isNotEmpty == true
                                          ? ride!.pickupAddress
                                          : 'Pickup Point',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 7),
                            child: Container(
                              height: 24,
                              width: 2,
                              color: Colors.white24,
                            ),
                          ),
                          // Drop Point
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: C.yellow,
                                ),
                                child: const Icon(Icons.square, size: 8, color: C.black),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'DESTINATION',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      ride?.dropAddress.isNotEmpty == true
                                          ? ride!.dropAddress
                                          : 'Drop Destination',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 28),
                          // Trip stats row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _TripMetric(
                                icon: Icons.straighten,
                                label: 'Distance',
                                value: '${(ride?.distanceKm ?? 0).toStringAsFixed(1)} km',
                              ),
                              Container(width: 1, height: 32, color: Colors.white12),
                              _TripMetric(
                                icon: Icons.timer_outlined,
                                label: 'Est. Trip',
                                value: '${((ride?.distanceKm ?? 0) * 3).toInt().clamp(5, 60)} mins',
                              ),
                              Container(width: 1, height: 32, color: Colors.white12),
                              const _TripMetric(
                                icon: Icons.payments_outlined,
                                label: 'Payment',
                                value: 'Cash',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 5. Action Buttons (Accept / Reject)
                    if (_statusNotice == null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.red.shade400, width: 1.5),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _isAccepting ? null : _handleReject,
                              child: Text(
                                'REJECT',
                                style: TextStyle(
                                  color: Colors.red.shade400,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 6,
                              ),
                              onPressed: _isAccepting ? null : _handleAccept,
                              child: _isAccepting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle, size: 20, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text(
                                          'ACCEPT RIDE',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryButton(
                          'Return to Dashboard',
                          bg: C.yellow,
                          fg: C.black,
                          onTap: _handleReject,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}

class _TripMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TripMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: C.yellow, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
