import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/live_map_view.dart';

class ActiveRideScreen extends StatefulWidget {
  final String rideId;
  final bool rider;
  const ActiveRideScreen({super.key, required this.rideId, required this.rider});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  final RideService _rideService = RideService();
  StreamSubscription<Position>? _gpsSub;
  Timer? _simulationTimer;
  double _simProgress = 0.0;
  bool _hasNavigatedAway = false;

  @override
  void initState() {
    super.initState();
    if (widget.rider) {
      _startRiderGpsTracking();
    }
  }

  void _startRiderGpsTracking() {
    _gpsSub = LocationService.getPositionStream(distanceFilter: 3).listen((pos) {
      _rideService.updateRiderLocation(widget.rideId, LatLng(pos.latitude, pos.longitude));
    });
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone number is not available')),
        );
      }
      return;
    }
    final clean = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching phone call: $e');
    }
  }

  /// Helper to test/simulate rider movement along the route
  void _toggleSimulation(LatLng start, LatLng target) {
    if (_simulationTimer != null && _simulationTimer!.isActive) {
      _simulationTimer?.cancel();
      _simulationTimer = null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulation paused')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulating live rider movement...')));
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _simProgress += 0.05;
      if (_simProgress >= 1.0) {
        _simProgress = 1.0;
        timer.cancel();
      }
      final curLat = start.latitude + (target.latitude - start.latitude) * _simProgress;
      final curLng = start.longitude + (target.longitude - start.longitude) * _simProgress;
      _rideService.updateRiderLocation(widget.rideId, LatLng(curLat, curLng));
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _simulationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RideModel?>(
      stream: _rideService.streamRide(widget.rideId),
      builder: (context, snapshot) {
        final ride = snapshot.data;

        if (ride == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: C.yellow)),
          );
        }

        // If completed by either party, navigate to completed screen
        if (ride.status == 'completed') {
          if (!_hasNavigatedAway) {
            _hasNavigatedAway = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompletedScreen(
                      rider: widget.rider,
                      fare: ride.estimatedFare,
                      rideId: widget.rideId,
                      riderId: ride.riderId,
                      riderName: ride.riderName,
                      customerId: ride.customerId,
                      customerName: ride.customerName,
                    ),
                  ),
                );
              }
            });
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: C.yellow)),
          );
        }

        // If cancelled by either party, navigate back safely
        if (ride.status == 'cancelled') {
          if (!_hasNavigatedAway) {
            _hasNavigatedAway = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ride has been cancelled.'),
                    backgroundColor: Colors.red,
                  ),
                );
                if (Navigator.canPop(context)) {
                  Navigator.popUntil(context, (r) => r.isFirst);
                }
              }
            });
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: C.yellow)),
          );
        }

        // Calculate live remaining distance between rider and destination
        final effectiveRiderLoc = ride.riderLocation ?? ride.pickupLocation;
        final targetLoc = (ride.status == 'accepted') ? ride.pickupLocation : ride.dropLocation;
        final remainingMeters = LocationService.getDistanceBetween(effectiveRiderLoc, targetLoc);
        final formattedDistance = LocationService.formatDistance(remainingMeters);

        final int stepIndex = (ride.status == 'requested')
            ? 0
            : (ride.status == 'accepted'
                ? 1
                : (ride.status == 'in_progress' ? 2 : 3));

        String topBadgeTitle;
        if (ride.status == 'accepted') {
          topBadgeTitle = widget.rider ? 'Proceeding to passenger pickup' : 'Rider arriving in';
        } else if (ride.status == 'in_progress') {
          topBadgeTitle = 'Heading to destination';
        } else {
          topBadgeTitle = 'Ride requested';
        }

        // Dynamic subtitle with real vehicle model and plate number for passenger
        String subtitle;
        if (widget.rider) {
          subtitle = ride.customerPhone.isNotEmpty ? ride.customerPhone : 'Passenger';
        } else {
          final parts = <String>[];
          if (ride.riderPhone != null && ride.riderPhone!.isNotEmpty) {
            parts.add(ride.riderPhone!);
          }
          if (ride.vehicleModel != null && ride.vehicleModel!.isNotEmpty) {
            parts.add(ride.vehicleModel!);
          }
          if (ride.plateNumber != null && ride.plateNumber!.isNotEmpty) {
            parts.add('(${ride.plateNumber!})');
          }
          subtitle = parts.isNotEmpty ? parts.join(' • ') : (ride.riderPhone ?? '03001234567');
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.rider ? 'Driver Mode' : 'Live Ride Tracking'),
            actions: [
              if (widget.rider)
                IconButton(
                  tooltip: 'Simulate Live Movement',
                  icon: const Icon(Icons.play_circle_outline, color: C.black),
                  onPressed: () => _toggleSimulation(effectiveRiderLoc, targetLoc),
                ),
            ],
          ),
          body: Stack(
            children: [
              // 1. Live Interactive Map
              Positioned.fill(
                child: LiveMapView(
                  pickupLocation: ride.pickupLocation,
                  dropLocation: (ride.status == 'accepted') ? ride.pickupLocation : ride.dropLocation,
                  riderLocation: ride.riderLocation,
                  showRoute: true,
                ),
              ),

              // 0. Offline Cached Map Warning Banner
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(child: OfflineBanner()),
              ),

              // 2. Live Decreasing Distance Badge at Top
              Positioned(
                top: 16,
                left: 16,
                right: 70,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: C.black,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.navigation, color: C.yellow, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              topBadgeTitle,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Text(
                              '$formattedDistance remaining',
                              style: const TextStyle(color: C.yellow, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Bottom Card with Info, Driver Rating & Reviews & Actions
              Align(
                alignment: Alignment.bottomCenter,
                child: BottomCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Stepper(current: stepIndex),
                      const SizedBox(height: 14),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(backgroundColor: C.yellow, child: Icon(Icons.person, color: C.black)),
                        title: Text(
                          widget.rider ? 'Passenger: ${ride.customerName}' : 'Driver: ${ride.riderName ?? "Rider"}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(subtitle),
                        trailing: InkWell(
                          onTap: () => _makePhoneCall(widget.rider ? ride.customerPhone : ride.riderPhone),
                          borderRadius: BorderRadius.circular(24),
                          child: const CircleAvatar(
                            backgroundColor: C.black,
                            child: Icon(Icons.call, color: C.yellow),
                          ),
                        ),
                      ),

                      // Driver Rating & Reviews Preview for Passenger
                      if (!widget.rider && ride.riderId != null) ...[
                        const SizedBox(height: 6),
                        _DriverReviewSummary(
                          riderId: ride.riderId!,
                          riderName: ride.riderName ?? 'Driver',
                          onViewReviews: () => _showRiderReviewsBottomSheet(
                            context,
                            ride.riderId!,
                            ride.riderName ?? 'Driver',
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Rider Action Buttons
                      if (widget.rider) ...[
                        if (ride.status == 'accepted')
                          PrimaryButton(
                            'Passenger Picked Up / Start Journey',
                            onTap: () async {
                              await _rideService.startTrip(widget.rideId);
                            },
                          )
                        else if (ride.status == 'in_progress')
                          PrimaryButton(
                            'Complete Ride',
                            bg: Colors.green.shade700,
                            fg: C.white,
                            onTap: () async {
                              await _rideService.completeRide(widget.rideId);
                            },
                          ),
                      ]
                      // Passenger Action Buttons
                      else ...[
                        if (ride.status == 'accepted')
                          PrimaryButton(
                            'Cancel Ride',
                            bg: Colors.red.shade700,
                            fg: C.white,
                            onTap: () async {
                              if (_hasNavigatedAway) return;
                              _hasNavigatedAway = true;
                              await _rideService.cancelRide(widget.rideId);
                              if (context.mounted && Navigator.canPop(context)) {
                                Navigator.popUntil(context, (r) => r.isFirst);
                              }
                            },
                          )
                        else if (ride.status == 'in_progress')
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.directions_bike, color: Colors.green.shade700, size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  'Journey in progress to destination',
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRiderReviewsBottomSheet(BuildContext context, String riderId, String riderName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reviews for $riderName',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 16),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _rideService.streamRiderReviews(riderId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: C.yellow));
                    }
                    final reviews = snapshot.data ?? [];
                    if (reviews.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text(
                              'No reviews yet for this driver',
                              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Reviews from other passengers will appear here.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      itemCount: reviews.length,
                      separatorBuilder: (_, __) => const Divider(height: 20),
                      itemBuilder: (context, index) {
                        final r = reviews[index];
                        final customerName = r['customerName'] ?? 'Passenger';
                        final rating = (r['rating'] as num?)?.toDouble() ?? 5.0;
                        final message = r['message'] ?? '';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: C.grey,
                                  child: Text(
                                    customerName.isNotEmpty ? customerName[0].toUpperCase() : 'P',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: C.black),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    customerName,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      rating.toStringAsFixed(1),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (message.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Text(
                                  '"$message"',
                                  style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey.shade800),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget to display driver rating summary and latest passenger review
class _DriverReviewSummary extends StatelessWidget {
  final String riderId;
  final String riderName;
  final VoidCallback onViewReviews;

  const _DriverReviewSummary({
    required this.riderId,
    required this.riderName,
    required this.onViewReviews,
  });

  @override
  Widget build(BuildContext context) {
    final rideService = RideService();
    return StreamBuilder<Map<String, dynamic>?>(
      stream: rideService.streamRiderProfile(riderId),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final rating = (data?['rating'] as num?)?.toDouble() ?? 5.0;
        final totalRatings = (data?['totalRatings'] as num?)?.toInt() ?? 0;
        final latestReview = data?['latestReview'] as Map<String, dynamic>?;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    rating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '($totalRatings ${totalRatings == 1 ? "review" : "reviews"})',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: onViewReviews,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View all reviews',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.blueAccent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, size: 10, color: Colors.blueAccent),
                      ],
                    ),
                  ),
                ],
              ),
              if (latestReview != null && (latestReview['message'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.format_quote_rounded, size: 16, color: Colors.amber),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '"${latestReview['message']}" - ${latestReview['customerName'] ?? "Passenger"}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade800),
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
  }
}

class _Stepper extends StatelessWidget {
  final int current; // 0 requested, 1 accepted, 2 in_progress, 3 completed
  const _Stepper({required this.current});

  @override
  Widget build(BuildContext context) {
    const labels = ['Requested', 'Accepted', 'On Trip', 'Completed'];
    return Row(children: [
      for (var i = 0; i < 4; i++) ...[
        Expanded(
          child: Column(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: i <= current ? C.yellow : C.grey,
              child: Icon(i < current ? Icons.check : Icons.circle, size: 14, color: C.black),
            ),
            const SizedBox(height: 4),
            Text(
              labels[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                color: i == current ? C.black : Colors.black54,
              ),
            ),
          ]),
        ),
      ],
    ]);
  }
}

class CompletedScreen extends StatefulWidget {
  final bool rider;
  final double fare;
  final String? rideId;
  final String? riderId;
  final String? riderName;
  final String? customerId;
  final String? customerName;

  const CompletedScreen({
    super.key,
    required this.rider,
    this.fare = 380,
    this.rideId,
    this.riderId,
    this.riderName,
    this.customerId,
    this.customerName,
  });

  @override
  State<CompletedScreen> createState() => _CompletedScreenState();
}

class _CompletedScreenState extends State<CompletedScreen> {
  final RideService _rideService = RideService();
  double _selectedRating = 5.0;
  final TextEditingController _reviewController = TextEditingController();
  bool _submitting = false;
  bool _reviewed = false;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  String _getRatingMood(double r) {
    if (r >= 5) return 'Excellent! ⭐⭐⭐⭐⭐';
    if (r >= 4) return 'Very Good! ⭐⭐⭐⭐';
    if (r >= 3) return 'Good ⭐⭐⭐';
    if (r >= 2) return 'Fair ⭐⭐';
    return 'Poor ⭐';
  }

  Future<void> _submitReview() async {
    if (widget.rideId == null || widget.riderId == null) {
      Navigator.popUntil(context, (r) => r.isFirst);
      return;
    }

    setState(() => _submitting = true);
    try {
      await _rideService.submitRideReview(
        rideId: widget.rideId!,
        riderId: widget.riderId!,
        customerId: widget.customerId ?? 'guest',
        customerName: widget.customerName ?? 'Passenger',
        rating: _selectedRating,
        message: _reviewController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _submitting = false;
          _reviewed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you! Your review has been submitted.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            Navigator.popUntil(context, (r) => r.isFirst);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit review: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              const CircleAvatar(
                radius: 40,
                backgroundColor: C.yellow,
                child: Icon(Icons.check_circle_outline, size: 50, color: C.black),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ride Completed!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'PKR ${widget.fare.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                widget.rider ? 'Collect cash from the customer' : 'Pay cash to the rider',
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 24),

              // If Passenger: Show Star Rating & Feedback Form
              if (!widget.rider) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                    ],
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Rate Driver: ${widget.riderName ?? "Rider"}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _getRatingMood(_selectedRating),
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          final starVal = (index + 1).toDouble();
                          return IconButton(
                            iconSize: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            icon: Icon(
                              _selectedRating >= starVal ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                            ),
                            onPressed: _reviewed
                                ? null
                                : () {
                                    setState(() => _selectedRating = starVal);
                                  },
                          );
                        }),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _reviewController,
                        enabled: !_reviewed,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Leave a review message for other passengers (e.g. Arrived fast, safe ride, polite)...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                          filled: true,
                          fillColor: C.grey,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_submitting)
                        const CircularProgressIndicator(color: C.yellow)
                      else
                        PrimaryButton(
                          _reviewed ? 'Review Submitted ✓' : 'Submit Review',
                          onTap: _reviewed ? null : _submitReview,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                  child: const Text('Done / Skip for now', style: TextStyle(color: Colors.black54)),
                ),
              ] else ...[
                const SizedBox(height: 20),
                PrimaryButton(
                  'Cash Received',
                  onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
