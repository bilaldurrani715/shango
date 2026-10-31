import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';

class RiderDashboardScreen extends StatefulWidget {
  final String riderId;
  final Map<String, dynamic>? initialRiderData;
  final bool isAdminView;

  const RiderDashboardScreen({
    super.key,
    required this.riderId,
    this.initialRiderData,
    this.isAdminView = false,
  });

  @override
  State<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends State<RiderDashboardScreen> with SingleTickerProviderStateMixin {
  final RideService _rideService = RideService();
  final AuthService _authService = AuthService();
  late TabController _tabController;

  // Timeframe filter: 'all', 'month', 'week', 'today'
  String _timeframe = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Call error: $e');
    }
  }

  Future<void> _openWhatsApp(String? phone, String message) async {
    if (phone == null || phone.trim().isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'[^\d]'), '');
    final url = 'https://wa.me/$clean?text=${Uri.encodeComponent(message)}';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('WhatsApp error: $e');
    }
  }

  bool _isWithinTimeframe(DateTime date) {
    final now = DateTime.now();
    if (_timeframe == 'today') {
      final startOfDay = DateTime(now.year, now.month, now.day);
      return date.isAfter(startOfDay);
    } else if (_timeframe == 'week') {
      // Last 7 days
      final startOfWeek = now.subtract(const Duration(days: 7));
      return date.isAfter(startOfWeek);
    } else if (_timeframe == 'month') {
      final startOfMonth = DateTime(now.year, now.month, 1);
      return date.isAfter(startOfMonth);
    }
    return true; // 'all'
  }

  String _formatDateTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$minuteStr $period';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.riderId).snapshots(),
      builder: (context, userSnap) {
        final userData = (userSnap.data?.data() as Map<String, dynamic>?) ?? widget.initialRiderData ?? {};

        return StreamBuilder<Map<String, dynamic>>(
          stream: _rideService.streamLocalPricing(),
          builder: (context, pricingSnap) {
            final pricing = pricingSnap.data ?? {'commissionPercent': 15.0};
            final commissionPercent = (pricing['commissionPercent'] as num?)?.toDouble() ?? 15.0;

            return StreamBuilder<List<RideModel>>(
              stream: _rideService.streamUserRides(uid: widget.riderId, isRider: true),
              builder: (context, cityRidesSnap) {
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _rideService.streamRiderIntercityBookings(widget.riderId),
                  builder: (context, intercitySnap) {
                    final allCityRides = cityRidesSnap.data ?? [];
                    final allIntercity = intercitySnap.data ?? [];

                    // Filter based on timeframe
                    final filteredCityRides = allCityRides.where((r) => _isWithinTimeframe(r.createdAt)).toList();
                    final filteredIntercity = allIntercity.where((b) {
                      final dt = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                      return _isWithinTimeframe(dt);
                    }).toList();

                    // Calculate Financial Totals
                    double cityGross = 0.0;
                    int cityCompleted = 0;
                    for (final r in filteredCityRides) {
                      if (r.status == 'completed') {
                        cityGross += r.estimatedFare;
                        cityCompleted++;
                      }
                    }

                    double intercityGross = 0.0;
                    int intercityCompleted = 0;
                    for (final b in filteredIntercity) {
                      final status = b['status'] as String? ?? '';
                      if (status == 'completed') {
                        final fare = (b['fare'] as num?)?.toDouble() ?? (b['standardFare'] as num?)?.toDouble() ?? 0.0;
                        intercityGross += fare;
                        intercityCompleted++;
                      }
                    }

                    final totalGrossFare = cityGross + intercityGross;
                    final totalCommission = totalGrossFare * (commissionPercent / 100);
                    final netEarnings = totalGrossFare - totalCommission;
                    final totalTrips = cityCompleted + intercityCompleted;

                    // Active list of trips for selected tab
                    final List<Map<String, dynamic>> activeTrips;
                    final String emptyMessage;

                    if (_tabController.index == 1) {
                      activeTrips = _getCityRidesList(cityRides: filteredCityRides);
                      emptyMessage = 'No in-city rides recorded in this timeframe.';
                    } else if (_tabController.index == 2) {
                      activeTrips = _getIntercityBookingsList(intercityBookings: filteredIntercity);
                      emptyMessage = 'No intercity scheduled trips recorded in this timeframe.';
                    } else {
                      activeTrips = _getCombinedTripsList(
                        cityRides: filteredCityRides,
                        intercityBookings: filteredIntercity,
                      );
                      emptyMessage = 'No trips recorded in this timeframe.';
                    }

                    return Scaffold(
                      backgroundColor: const Color(0xFFF8F9FA),
                      appBar: AppBar(
                        backgroundColor: C.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isAdminView ? 'Driver Dashboard' : 'My Earnings & Dashboard',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                            ),
                            Text(
                              '${userData['name'] ?? 'Driver'} • ShanGo Partner',
                              style: const TextStyle(color: C.yellow, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        actions: [
                          if (widget.isAdminView) ...[
                            IconButton(
                              icon: const Icon(Icons.call, color: Colors.white, size: 20),
                              tooltip: 'Call Driver',
                              onPressed: () => _makeCall(userData['phone']),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 20),
                              tooltip: 'WhatsApp Driver',
                              onPressed: () => _openWhatsApp(
                                userData['phone'],
                                'Hello ${userData['name'] ?? 'Driver'}, this is ShanGo Admin regarding your driver dashboard.',
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                        ],
                      ),
                      body: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity == null) return;
                          if (details.primaryVelocity! < -250) {
                            // Swiped left -> next tab
                            if (_tabController.index < 2) {
                              _tabController.animateTo(_tabController.index + 1);
                              setState(() {});
                            }
                          } else if (details.primaryVelocity! > 250) {
                            // Swiped right -> prev tab
                            if (_tabController.index > 0) {
                              _tabController.animateTo(_tabController.index - 1);
                              setState(() {});
                            }
                          }
                        },
                        child: CustomScrollView(
                          slivers: [
                            // 1. Driver Profile Header Card
                            SliverToBoxAdapter(
                              child: _buildDriverProfileHeader(userData),
                            ),

                            // 2. Timeframe Filter Selector
                            SliverToBoxAdapter(
                              child: _buildTimeframeSelector(),
                            ),

                            // 3. Key Financial Metrics (Gross, ShanGo Commission, Net Take-Home, Trips)
                            SliverToBoxAdapter(
                              child: _buildFinancialMetrics(
                                totalGross: totalGrossFare,
                                commission: totalCommission,
                                netEarnings: netEarnings,
                                totalTrips: totalTrips,
                                commissionPercent: commissionPercent,
                              ),
                            ),

                            // 4. Transparent Commission Split Bar
                            SliverToBoxAdapter(
                              child: _buildCommissionSplitCard(
                                totalGross: totalGrossFare,
                                commission: totalCommission,
                                netEarnings: netEarnings,
                                commissionPercent: commissionPercent,
                              ),
                            ),

                            // 5. Trip Breakdown Section Header & TabBar (Pinned for persistent tabs and smooth scroll)
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _SliverTabBarDelegate(
                                height: 62.0,
                                child: _buildTripTabsHeader(
                                  totalCount: filteredCityRides.length + filteredIntercity.length,
                                  cityCount: filteredCityRides.length,
                                  intercityCount: filteredIntercity.length,
                                ),
                              ),
                            ),

                            // 6. List of Trips based on Selected Tab (or Empty State)
                            if (activeTrips.isEmpty)
                              SliverToBoxAdapter(
                                child: _buildEmptyState(emptyMessage),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                sliver: SliverList.separated(
                                  itemCount: activeTrips.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (context, i) => _buildTripCard(activeTrips[i], commissionPercent),
                                ),
                              ),
                          ],
                        ),
                      ),
                      bottomNavigationBar: widget.isAdminView
                          ? _buildAdminBottomActionBar(userData)
                          : null,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // SECTION 1: DRIVER PROFILE HEADER
  // =========================================================================
  Widget _buildDriverProfileHeader(Map<String, dynamic> user) {
    final name = user['name'] ?? 'Driver Partner';
    final phone = user['phone'] ?? 'No Phone';
    final email = user['email'] ?? '';
    final vehicleModel = user['vehicleModel'] ?? 'Motorbike';
    final vehicleType = user['vehicleType'] ?? 'Bike';
    final plateNumber = user['plateNumber'] ?? 'No Plate';
    final rating = (user['rating'] as num?)?.toDouble() ?? 5.0;
    final totalRatings = (user['totalRatings'] as num?)?.toInt() ?? 0;
    final isApproved = user['isApproved'] == true;
    final isSuspended = user['isSuspended'] == true;
    final isDriverAdmin = user['isAdmin'] == true || user['role'] == 'admin';
    final isScheduledActive = user['isAvailableForScheduled'] ?? true;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.black,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: C.yellow,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'D',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: C.black),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isDriverAdmin)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('ADMIN', style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w900, fontSize: 9)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phone.isNotEmpty ? phone : email,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSuspended
                                ? Colors.red.shade900
                                : (isApproved ? Colors.green.shade800 : Colors.amber.shade900),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isSuspended ? 'SUSPENDED' : (isApproved ? 'APPROVED & ACTIVE' : 'PENDING APPROVAL'),
                            style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 14),
                            const SizedBox(width: 2),
                            Text(
                              '${rating.toStringAsFixed(1)} ($totalRatings)',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.two_wheeler, color: C.yellow, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$vehicleModel ($plateNumber) • $vehicleType',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isScheduledActive ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isScheduledActive ? Colors.green : Colors.red, width: 0.8),
                ),
                child: Text(
                  isScheduledActive ? 'Intercity: Online' : 'Intercity: Paused',
                  style: TextStyle(color: isScheduledActive ? Colors.greenAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION 2: TIMEFRAME SELECTOR CHIPS
  // =========================================================================
  Widget _buildTimeframeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildTimeframeChip('All Time', 'all'),
          const SizedBox(width: 8),
          _buildTimeframeChip('This Month', 'month'),
          const SizedBox(width: 8),
          _buildTimeframeChip('This Week', 'week'),
          const SizedBox(width: 8),
          _buildTimeframeChip('Today', 'today'),
        ],
      ),
    );
  }

  Widget _buildTimeframeChip(String label, String key) {
    final isSelected = _timeframe == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _timeframe = key),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? C.yellow : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? C.black : Colors.grey.shade300, width: isSelected ? 1.5 : 1),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              color: isSelected ? C.black : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // SECTION 3: KEY FINANCIAL METRICS CARDS
  // =========================================================================
  Widget _buildFinancialMetrics({
    required double totalGross,
    required double commission,
    required double netEarnings,
    required int totalTrips,
    required double commissionPercent,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Total Gross Fare',
                  value: 'PKR ${totalGross.toStringAsFixed(0)}',
                  subtitle: 'Total passenger fares collected',
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: Colors.teal.shade700,
                  bgColor: const Color(0xFFE6FFFA),
                  borderColor: const Color(0xFF81E6D9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: 'ShanGo Fee (${commissionPercent.toInt()}%)',
                  value: 'PKR ${commission.toStringAsFixed(0)}',
                  subtitle: 'Commission to ShanGo',
                  icon: Icons.pie_chart_rounded,
                  iconColor: const Color(0xFFB45309),
                  bgColor: const Color(0xFFFEF3C7),
                  borderColor: const Color(0xFFFCD34D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Net Driver Take-Home',
                  value: 'PKR ${netEarnings.toStringAsFixed(0)}',
                  subtitle: '${(100 - commissionPercent).toInt()}% net profit in pocket',
                  icon: Icons.payments_rounded,
                  iconColor: Colors.green.shade800,
                  bgColor: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFF86EFAC),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: 'Completed Trips',
                  value: '$totalTrips Trips',
                  subtitle: 'City & Intercity combined',
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: Colors.indigo.shade800,
                  bgColor: const Color(0xFFEEF2FF),
                  borderColor: const Color(0xFFA5B4FC),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: iconColor),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION 4: COMMISSION SPLIT VISUAL PROGRESS BAR & POLICY INFO
  // =========================================================================
  Widget _buildCommissionSplitCard({
    required double totalGross,
    required double commission,
    required double netEarnings,
    required double commissionPercent,
  }) {
    final driverPercent = 100 - commissionPercent;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Earnings & Commission Split',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: C.black),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: C.grey, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'Policy: ${commissionPercent.toInt()}% ShanGo Fee',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Split Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  Expanded(
                    flex: driverPercent.toInt(),
                    child: Container(color: Colors.green.shade600),
                  ),
                  Expanded(
                    flex: commissionPercent.toInt(),
                    child: Container(color: const Color(0xFFF59E0B)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.green.shade600, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Driver Net: ${driverPercent.toInt()}% (PKR ${netEarnings.toStringAsFixed(0)})',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'ShanGo: ${commissionPercent.toInt()}% (PKR ${commission.toStringAsFixed(0)})',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ShanGo fee covers GPS dispatch, customer acquisition, 24/7 helpline, and active platform maintenance.',
                    style: TextStyle(fontSize: 10.5, color: Colors.blueGrey.shade800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION 5: TRIP TABS HEADER
  // =========================================================================
  Widget _buildTripTabsHeader({
    required int totalCount,
    required int cityCount,
    required int intercityCount,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        onTap: (index) => setState(() {}),
        labelColor: C.black,
        indicatorColor: C.yellow,
        indicatorWeight: 4,
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        tabs: [
          Tab(text: 'All Trips ($totalCount)'),
          Tab(text: 'City Rides ($cityCount)'),
          Tab(text: 'Intercity ($intercityCount)'),
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION 6: TRIP DATA EXTRACTORS FOR UNIFIED SLIVER LIST
  // =========================================================================
  List<Map<String, dynamic>> _getCombinedTripsList({
    required List<RideModel> cityRides,
    required List<Map<String, dynamic>> intercityBookings,
  }) {
    final List<Map<String, dynamic>> combined = [];

    for (final r in cityRides) {
      combined.add({
        'type': 'city',
        'id': r.id,
        'date': r.createdAt,
        'pickup': r.pickupAddress,
        'drop': r.dropAddress,
        'status': r.status,
        'fare': r.estimatedFare,
        'distanceKm': r.distanceKm,
        'customerName': r.customerName,
        'customerPhone': r.customerPhone,
        'rating': r.rating,
        'review': r.reviewMessage,
      });
    }

    for (final b in intercityBookings) {
      final dt = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
      final fare = (b['fare'] as num?)?.toDouble() ?? (b['standardFare'] as num?)?.toDouble() ?? 0.0;
      combined.add({
        'type': 'intercity',
        'id': b['id'] ?? '',
        'date': dt,
        'pickup': '${b['fromCity'] ?? ''} (${b['pickupAddress'] ?? ''})',
        'drop': '${b['toCity'] ?? ''} (${b['dropAddress'] ?? ''})',
        'status': b['status'] ?? 'scheduled',
        'fare': fare,
        'distanceKm': 0.0,
        'customerName': b['customerName'] ?? 'Passenger',
        'customerPhone': b['customerPhone'] ?? '',
        'scheduledDate': b['scheduledDate'],
        'scheduledTime': b['scheduledTime'],
      });
    }

    combined.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return combined;
  }

  List<Map<String, dynamic>> _getCityRidesList({
    required List<RideModel> cityRides,
  }) {
    return cityRides.map((r) => {
      'type': 'city',
      'id': r.id,
      'date': r.createdAt,
      'pickup': r.pickupAddress,
      'drop': r.dropAddress,
      'status': r.status,
      'fare': r.estimatedFare,
      'distanceKm': r.distanceKm,
      'customerName': r.customerName,
      'customerPhone': r.customerPhone,
      'rating': r.rating,
      'review': r.reviewMessage,
    }).toList();
  }

  List<Map<String, dynamic>> _getIntercityBookingsList({
    required List<Map<String, dynamic>> intercityBookings,
  }) {
    final List<Map<String, dynamic>> list = [];
    for (final b in intercityBookings) {
      final dt = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
      final fare = (b['fare'] as num?)?.toDouble() ?? (b['standardFare'] as num?)?.toDouble() ?? 0.0;
      list.add({
        'type': 'intercity',
        'id': b['id'] ?? '',
        'date': dt,
        'pickup': '${b['fromCity'] ?? ''} (${b['pickupAddress'] ?? ''})',
        'drop': '${b['toCity'] ?? ''} (${b['dropAddress'] ?? ''})',
        'status': b['status'] ?? 'scheduled',
        'fare': fare,
        'distanceKm': 0.0,
        'customerName': b['customerName'] ?? 'Passenger',
        'customerPhone': b['customerPhone'] ?? '',
        'scheduledDate': b['scheduledDate'],
        'scheduledTime': b['scheduledTime'],
      });
    }
    list.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return list;
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_bike_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // SECTION 7: DETAILED TRIP CARD WITH EARNINGS & COMMISSION
  // =========================================================================
  Widget _buildTripCard(Map<String, dynamic> item, double commissionPercent) {
    final isCity = item['type'] == 'city';
    final date = item['date'] as DateTime;
    final status = (item['status'] as String? ?? '').toLowerCase();
    final fare = (item['fare'] as num?)?.toDouble() ?? 0.0;
    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled';
    final isInProgress = status == 'in_progress';

    final commAmount = fare * (commissionPercent / 100);
    final netAmount = fare - commAmount;

    Color statusColor;
    Color statusBg;
    if (isCompleted) {
      statusColor = Colors.green.shade800;
      statusBg = Colors.green.shade50;
    } else if (isCancelled) {
      statusColor = Colors.red.shade800;
      statusBg = Colors.red.shade50;
    } else if (isInProgress) {
      statusColor = Colors.blue.shade800;
      statusBg = Colors.blue.shade50;
    } else {
      statusColor = Colors.amber.shade900;
      statusBg = Colors.amber.shade50;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Type badge & Status & Date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCity ? C.yellow : C.black,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isCity ? 'IN-CITY RIDE' : 'INTERCITY TRIP',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: isCity ? C.black : C.yellow,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDateTime(date),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Route: Pickup and Drop
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.circle, size: 10, color: Colors.green),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item['pickup'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.square, size: 10, color: C.yellow),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item['drop'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const Divider(height: 18),

          // Financial Breakdown Strip (Gross, ShanGo Commission, Driver Net)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gross Fare', style: TextStyle(fontSize: 10, color: Colors.black54)),
                    Text('PKR ${fare.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('ShanGo (${commissionPercent.toInt()}%)', style: const TextStyle(fontSize: 10, color: Color(0xFFB45309))),
                    Text('-PKR ${commAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFB45309))),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Driver Net (${(100 - commissionPercent).toInt()}%)', style: const TextStyle(fontSize: 10, color: Colors.green)),
                    Text('+PKR ${netAmount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.green.shade800)),
                  ],
                ),
              ],
            ),
          ),

          // Passenger info & Quick Contact
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 14, color: Colors.black54),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${item['customerName']} • ${item['customerPhone']}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((item['customerPhone'] as String?)?.isNotEmpty == true) ...[
                    InkWell(
                      onTap: () => _makeCall(item['customerPhone']),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                        child: const Icon(Icons.call, size: 14, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _openWhatsApp(item['customerPhone'], 'Hello ${item['customerName']}, this is ShanGo regarding your ride.'),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                        child: const Icon(Icons.chat, size: 14, color: Color(0xFF16A34A)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          if (item['rating'] != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Passenger Rating: ${(item['rating'] as num).toStringAsFixed(1)}${item['review'] != null ? ' - "${item['review']}"' : ''}',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION 8: ADMIN ACTION BAR (when viewed by Admin)
  // =========================================================================
  Widget _buildAdminBottomActionBar(Map<String, dynamic> user) {
    final uid = widget.riderId;
    final name = user['name'] ?? 'Driver';
    final isApproved = user['isApproved'] == true;
    final isSuspended = user['isSuspended'] == true;
    final isDriverAdmin = user['isAdmin'] == true || user['role'] == 'admin';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (!isApproved && !isSuspended)
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Approve Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () async {
                    await _authService.setRiderApprovalStatus(uid, isApproved: true);
                    await NotificationService().notifyDriverAccountApproved(driverUid: uid, driverName: name);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name approved successfully!')));
                    }
                  },
                ),
              ),
            if (isApproved && !isSuspended)
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('Suspend Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () async {
                    await _authService.setUserSuspensionStatus(uid, isSuspended: true, reason: 'Suspended by Admin');
                    await NotificationService().notifyUserAccountSuspension(uid: uid, isSuspended: true, reason: 'Admin decision', role: 'rider');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name account suspended!')));
                    }
                  },
                ),
              ),
            if (isSuspended)
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Unsuspend Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () async {
                    await _authService.setUserSuspensionStatus(uid, isSuspended: false);
                    await _authService.setRiderApprovalStatus(uid, isApproved: true);
                    await NotificationService().notifyUserAccountSuspension(uid: uid, isSuspended: false, role: 'rider');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name account reactivated!')));
                    }
                  },
                ),
              ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: isDriverAdmin ? Colors.orange.shade800 : Colors.indigo.shade700,
                side: BorderSide(color: isDriverAdmin ? Colors.orange.shade300 : Colors.indigo.shade300),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(isDriverAdmin ? Icons.remove_moderator : Icons.admin_panel_settings, size: 16),
              label: Text(isDriverAdmin ? 'Revoke Admin' : 'Make Admin', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              onPressed: () async {
                final newStatus = !isDriverAdmin;
                await _authService.setUserAdminStatus(uid, isAdmin: newStatus);
                await NotificationService().notifyUserAdminStatusChanged(uid: uid, isAdmin: newStatus);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$name is ${newStatus ? 'now an Admin' : 'no longer an Admin'}.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _SliverTabBarDelegate({
    required this.child,
    this.height = 62.0,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFFF8F9FA),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return true;
  }
}
