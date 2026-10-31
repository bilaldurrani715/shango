import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import '../services/app_version_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'admin_fleet_map_screen.dart';
import 'notifications_screen.dart';
import 'rider_dashboard_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  final int initialTabIndex;
  const AdminPanelScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AuthService _authService = AuthService();
  final RideService _rideService = RideService();

  // Cached persistent streams to prevent rebuild flicker and keyboard closing
  late final Stream<List<Map<String, dynamic>>> _ridersStream = _rideService.streamUsers(role: 'rider');
  late final Stream<List<Map<String, dynamic>>> _usersStream = _rideService.streamUsers();

  // Dedicated focus nodes for search inputs
  final FocusNode _riderSearchFocusNode = FocusNode();
  final FocusNode _passengerSearchFocusNode = FocusNode();

  // Configurable owner commission percentage (default 15%)
  double _ownerCommissionPercent = 15.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 5),
    );
    NotificationService().startLiveNotificationListener('admin', isAdmin: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _riderSearchController.dispose();
    _passengerSearchController.dispose();
    _riderSearchFocusNode.dispose();
    _passengerSearchFocusNode.dispose();
    NotificationService().stopLiveNotificationListener();
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

  Future<void> _openMaps(dynamic lat, dynamic lng) async {
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Map launcher error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminFleetMapScreen()),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Fleet Map',
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminFleetMapScreen()),
                );
              }
            },
          ),
          title: const Text('ShanGo Admin Console', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          actions: [
            IconButton(
              icon: const Icon(Icons.radar_rounded, color: C.black),
              tooltip: 'Fleet Radar Map',
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminFleetMapScreen()),
                );
              },
            ),
            StreamBuilder<int>(
              stream: NotificationService().streamAdminUnreadCount(),
              builder: (context, notifSnap) {
                final unread = notifSnap.data ?? 0;
                return IconButton(
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.notifications_outlined, size: 24),
                  ),
                  tooltip: 'Admin Notifications',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(isAdminView: true),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _authService.streamSwitchRequests(),
              builder: (context, switchSnap) {
                final pendingSwitchCount = switchSnap.data?.length ?? 0;
                return TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: C.black,
                  indicatorColor: C.yellow,
                  indicatorWeight: 4,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  tabs: [
                    const Tab(icon: Icon(Icons.analytics_outlined), text: 'Dashboard & Revenue'),
                    const Tab(icon: Icon(Icons.two_wheeler), text: 'Riders & Approval'),
                    const Tab(icon: Icon(Icons.people_outline), text: 'Passengers'),
                    Tab(
                      icon: Badge(
                        isLabelVisible: pendingSwitchCount > 0,
                        label: Text('$pendingSwitchCount'),
                        backgroundColor: Colors.red,
                        child: const Icon(Icons.swap_horiz_rounded),
                      ),
                      text: pendingSwitchCount > 0 ? 'Switches ($pendingSwitchCount)' : 'Account Switches',
                    ),
                    const Tab(icon: Icon(Icons.alt_route), text: 'Intercity Dispatch'),
                    const Tab(icon: Icon(Icons.tune), text: 'Pricing & Helpline'),
                  ],
                );
              },
            ),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildDashboardTab(),
            _buildRidersTab(),
            _buildPassengersTab(),
            _buildAccountSwitchesTab(),
            _buildIntercityDispatchTab(),
            _buildRoutesAndPricingTab(),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: EXECUTIVE DASHBOARD & REVENUE SUMMARY
  // ==========================================
  Widget _buildDashboardTab() {
    return StreamBuilder<List<RideModel>>(
      stream: _rideService.streamAllRides(),
      builder: (context, ridesSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _rideService.streamUsers(),
          builder: (context, usersSnap) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _rideService.streamAllIntercityBookings(),
              builder: (context, intercitySnap) {
                if (ridesSnap.connectionState == ConnectionState.waiting &&
                    usersSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: C.yellow));
                }

                final allRides = ridesSnap.data ?? [];
                final allUsers = usersSnap.data ?? [];
                final allIntercity = intercitySnap.data ?? [];

                final riders = allUsers.where((u) => u['role'] == 'rider').toList();
                final passengers = allUsers.where((u) => u['role'] != 'rider').toList();

                final pendingRiders = riders.where((r) => r['isApproved'] != true).toList();
                final approvedRiders = riders.where((r) => r['isApproved'] == true && r['isSuspended'] != true).toList();
                final suspendedRiders = riders.where((r) => r['isSuspended'] == true).toList();
                final pendingSwitches = allUsers.where((u) {
                  final req = u['switchRequest'] as Map<String, dynamic>?;
                  return req != null && req['status'] == 'pending';
                }).toList();

                final completedLocalRides = allRides.where((r) => r.status == 'completed').toList();
                final completedIntercityRides = allIntercity.where((b) => b['status'] == 'completed').toList();

                double totalLocalGross = 0.0;
                for (final r in completedLocalRides) {
                  totalLocalGross += r.estimatedFare;
                }

                double totalIntercityGross = 0.0;
                for (final b in completedIntercityRides) {
                  totalIntercityGross += ((b['fare'] as num?)?.toDouble() ?? 0.0);
                }

                final double totalGrossVolume = totalLocalGross + totalIntercityGross;
                final double ownerCommissionAmount = totalGrossVolume * (_ownerCommissionPercent / 100);
                final double driverNetPayouts = totalGrossVolume - ownerCommissionAmount;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Revenue Banner
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: C.black,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Owner Revenue',
                                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(8)),
                                  child: Text(
                                    '${_ownerCommissionPercent.toInt()}% Commission',
                                    style: const TextStyle(color: C.black, fontWeight: FontWeight.w900, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'PKR ${ownerCommissionAmount.toStringAsFixed(0)}',
                              style: const TextStyle(color: C.yellow, fontSize: 32, fontWeight: FontWeight.w900),
                            ),
                            const Divider(color: Colors.white24, height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Gross Ride Volume', style: TextStyle(color: Colors.white60, fontSize: 11)),
                                    Text('PKR ${totalGrossVolume.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text('Driver Net Payouts', style: TextStyle(color: Colors.white60, fontSize: 11)),
                                    Text('PKR ${driverNetPayouts.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Commission Adjuster
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: C.grey,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Owner Commission:',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                            ),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<double>(
                                value: _ownerCommissionPercent,
                                isDense: true,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                items: const [
                                  DropdownMenuItem(value: 0.0, child: Text('0% (No Commission)')),
                                  DropdownMenuItem(value: 5.0, child: Text('5%')),
                                  DropdownMenuItem(value: 10.0, child: Text('10%')),
                                  DropdownMenuItem(value: 12.0, child: Text('12%')),
                                  DropdownMenuItem(value: 15.0, child: Text('15% (Default)')),
                                  DropdownMenuItem(value: 20.0, child: Text('20%')),
                                  DropdownMenuItem(value: 25.0, child: Text('25%')),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => _ownerCommissionPercent = v);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      const Text('System Overview', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 12),

                      // Grid Cards
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.4,
                        children: [
                          _buildStatCard(
                            title: 'Total Riders',
                            value: '${riders.length}',
                            subtitle: '${approvedRiders.length} Active • ${pendingRiders.length} Pending • ${suspendedRiders.length} Suspended',
                            icon: Icons.two_wheeler,
                            color: Colors.blue.shade700,
                          ),
                          _buildStatCard(
                            title: 'Total Passengers',
                            value: '${passengers.length}',
                            subtitle: 'Registered Customers',
                            icon: Icons.people,
                            color: Colors.green.shade700,
                          ),
                          _buildStatCard(
                            title: 'Completed Trips',
                            value: '${completedLocalRides.length + completedIntercityRides.length}',
                            subtitle: '${completedLocalRides.length} Local • ${completedIntercityRides.length} Intercity',
                            icon: Icons.check_circle,
                            color: Colors.amber.shade800,
                          ),
                          _buildStatCard(
                            title: 'Role Switch Requests',
                            value: '${pendingSwitches.length}',
                            subtitle: 'Pending admin approval',
                            icon: Icons.swap_horiz_rounded,
                            color: Colors.purple.shade700,
                          ),
                          _buildStatCard(
                            title: 'Pending Driver Signups',
                            value: '${pendingRiders.length}',
                            subtitle: 'New drivers awaiting review',
                            icon: Icons.pending_actions,
                            color: Colors.orange.shade800,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                      const Text('Recent Local Rides', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 10),

                      if (allRides.isEmpty)
                        const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No ride records yet.')))
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: allRides.take(5).length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final r = allRides[i];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: C.grey, borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: r.status == 'completed' ? Colors.green.shade100 : C.yellow,
                                    child: Icon(r.status == 'completed' ? Icons.check : Icons.directions_bike, color: C.black, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${r.pickupAddress} ➔ ${r.dropAddress}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                        Text('Passenger: ${r.customerName} • Driver: ${r.riderName ?? "Unassigned"}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('PKR ${r.estimatedFare.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                      Text(r.status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: r.status == 'completed' ? Colors.green.shade800 : Colors.black54)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey.shade700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, color: color, size: 20),
            ],
          ),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: RIDERS APPROVAL & MANAGEMENT
  // ==========================================
  String _riderFilter = 'all'; // 'all', 'pending', 'approved', 'suspended'
  String _vehicleTypeFilter = 'all'; // 'all', 'bike', 'car', 'auto', 'other'
  final TextEditingController _riderSearchController = TextEditingController();
  String _riderSearchQuery = '';

  // Tab 3: Passengers & Users search & filters
  final TextEditingController _passengerSearchController = TextEditingController();
  String _passengerSearchQuery = '';
  String _passengerRoleFilter = 'passenger'; // 'passenger', 'all', 'rider', 'admin', 'suspended'

  bool _matchesVehicle(String? vehicleType, String filterKey) {
    if (filterKey == 'all') return true;
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
    if (filterKey == 'other') {
      final isBike = v.contains('bike') || v.contains('motor') || v.contains('scooter') || v.isEmpty;
      final isCar = v.contains('car') || v.contains('taxi') || v.contains('sedan') || v.contains('cab');
      final isAuto = v.contains('auto') || v.contains('rickshaw');
      return !isBike && !isCar && !isAuto;
    }
    return true;
  }

  IconData _getVehicleIcon(String? vehicleType) {
    final v = (vehicleType ?? '').trim().toLowerCase();
    if (v.contains('car') || v.contains('taxi') || v.contains('sedan') || v.contains('cab')) {
      return Icons.directions_car;
    }
    if (v.contains('auto') || v.contains('rickshaw')) {
      return Icons.electric_rickshaw;
    }
    if (v.contains('hiace') || v.contains('van') || v.contains('shuttle')) {
      return Icons.airport_shuttle;
    }
    return Icons.two_wheeler;
  }

  Widget _buildRidersTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ridersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: C.yellow));
        }

        final allRiders = snapshot.data ?? [];
        final bikeCount = allRiders.where((r) => _matchesVehicle(r['vehicleType'] as String?, 'bike')).length;
        final carCount = allRiders.where((r) => _matchesVehicle(r['vehicleType'] as String?, 'car')).length;
        final autoCount = allRiders.where((r) => _matchesVehicle(r['vehicleType'] as String?, 'auto')).length;
        final otherCount = allRiders.where((r) => _matchesVehicle(r['vehicleType'] as String?, 'other')).length;

        final filteredRiders = allRiders.where((r) {
          final isApproved = r['isApproved'] == true;
          final isSuspended = r['isSuspended'] == true;
          if (_riderFilter == 'pending' && (isApproved || isSuspended)) return false;
          if (_riderFilter == 'approved' && (!isApproved || isSuspended)) return false;
          if (_riderFilter == 'suspended' && !isSuspended) return false;

          if (!_matchesVehicle(r['vehicleType'] as String?, _vehicleTypeFilter)) return false;

          if (_riderSearchQuery.isNotEmpty) {
            final name = (r['name'] as String? ?? '').toLowerCase();
            final phone = (r['phone'] as String? ?? '').toLowerCase();
            final plate = (r['vehiclePlate'] as String? ?? r['plateNumber'] as String? ?? r['vehicleNumber'] as String? ?? '').toLowerCase();
            final model = (r['vehicleModel'] as String? ?? '').toLowerCase();
            final cnic = (r['cnic'] as String? ?? r['cnicNumber'] as String? ?? '').toLowerCase();
            final email = (r['email'] as String? ?? '').toLowerCase();
            final city = (r['city'] as String? ?? '').toLowerCase();

            final q = _riderSearchQuery;
            final matches = name.contains(q) ||
                phone.contains(q) ||
                plate.contains(q) ||
                model.contains(q) ||
                cnic.contains(q) ||
                email.contains(q) ||
                city.contains(q);
            if (!matches) return false;
          }

          return true;
        }).toList();

        return Column(
          children: [
            // Filter & Search Bars Container
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Bar for Drivers
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _riderSearchQuery.isNotEmpty ? C.black : const Color(0xFFE5E7EB),
                        width: _riderSearchQuery.isNotEmpty ? 1.5 : 1,
                      ),
                    ),
                    child: TextField(
                      controller: _riderSearchController,
                      focusNode: _riderSearchFocusNode,
                      onChanged: (val) => setState(() => _riderSearchQuery = val.trim().toLowerCase()),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Search rider by name, phone, plate, CNIC...',
                        hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500, fontWeight: FontWeight.normal),
                        prefixIcon: const Icon(Icons.search, color: Colors.black54, size: 20),
                        suffixIcon: _riderSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: Colors.black54),
                                onPressed: () {
                                  _riderSearchController.clear();
                                  setState(() => _riderSearchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Row 1: Status Filter
                  Row(
                    children: [
                      const Text(
                        'STATUS:',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black54, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All Drivers (${allRiders.length})', 'all', Icons.people_alt_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('Pending Approval (${allRiders.where((r) => r['isApproved'] != true && r['isSuspended'] != true).length})', 'pending', Icons.access_time_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('Approved (${allRiders.where((r) => r['isApproved'] == true && r['isSuspended'] != true).length})', 'approved', Icons.check_circle_rounded),
                        const SizedBox(width: 8),
                        _buildFilterChip('Suspended (${allRiders.where((r) => r['isSuspended'] == true).length})', 'suspended', Icons.block_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Row 2: Vehicle Type Filter
                  Row(
                    children: [
                      const Text(
                        'VEHICLE TYPE:',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black54, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildVehicleFilterChip('All Vehicles (${allRiders.length})', 'all', Icons.commute),
                        const SizedBox(width: 8),
                        _buildVehicleFilterChip('Bikes ($bikeCount)', 'bike', Icons.two_wheeler),
                        const SizedBox(width: 8),
                        _buildVehicleFilterChip('Cars ($carCount)', 'car', Icons.directions_car),
                        const SizedBox(width: 8),
                        _buildVehicleFilterChip('Auto / Rickshaw ($autoCount)', 'auto', Icons.electric_rickshaw),
                        if (otherCount > 0) ...[
                          const SizedBox(width: 8),
                          _buildVehicleFilterChip('Others ($otherCount)', 'other', Icons.more_horiz),
                        ],
                      ],
                    ),
                  ),

                  // Search results banner
                  if (_riderSearchQuery.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCD34D)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 14, color: Color(0xFFB45309)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Found ${filteredRiders.length} matching rider${filteredRiders.length == 1 ? '' : 's'} for "$_riderSearchQuery"',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              _riderSearchController.clear();
                              setState(() => _riderSearchQuery = '');
                            },
                            child: const Text(
                              'Clear',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: filteredRiders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.filter_alt_off_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            _riderSearchQuery.isNotEmpty
                                ? 'No riders matching "$_riderSearchQuery"'
                                : 'No drivers found with current filters.',
                            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Status: ${_riderFilter.toUpperCase()} • Vehicle: ${_vehicleTypeFilter.toUpperCase()}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: Text(_riderSearchQuery.isNotEmpty ? 'Clear Search & Filters' : 'Reset Filters'),
                            onPressed: () => setState(() {
                              _riderSearchController.clear();
                              _riderSearchQuery = '';
                              _riderFilter = 'all';
                              _vehicleTypeFilter = 'all';
                            }),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredRiders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) => _buildRiderCard(filteredRiders[index]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String key, [IconData? icon]) {
    final isSelected = _riderFilter == key;
    return ChoiceChip(
      avatar: icon != null ? Icon(icon, size: 16, color: isSelected ? C.black : Colors.black54) : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          color: isSelected ? C.black : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: C.yellow,
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: isSelected ? Colors.amber.shade700 : Colors.grey.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (_) => setState(() => _riderFilter = key),
    );
  }

  Widget _buildVehicleFilterChip(String label, String key, IconData icon) {
    final isSelected = _vehicleTypeFilter == key;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: isSelected ? C.black : Colors.black54),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          color: isSelected ? C.black : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: C.yellow,
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: isSelected ? Colors.amber.shade700 : Colors.grey.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (_) => setState(() => _vehicleTypeFilter = key),
    );
  }

  Widget _buildRiderCard(Map<String, dynamic> rider) {
    final uid = rider['uid'] ?? '';
    final name = (rider['name'] ?? 'Driver').toString().trim();
    final phone = (rider['phone'] ?? 'No Phone').toString().trim();
    final email = (rider['email'] ?? '').toString().trim();
    final vehicleType = (rider['vehicleType'] ?? 'Bike').toString().trim();
    final vehicleModel = (rider['vehicleModel'] ?? '').toString().trim();
    final plateNumber = (rider['plateNumber'] ?? '').toString().trim();
    final rating = (rider['rating'] as num?)?.toDouble() ?? 5.0;
    final totalRatings = (rider['totalRatings'] as num?)?.toInt() ?? 1;
    final isApproved = rider['isApproved'] == true;
    final isSuspended = rider['isSuspended'] == true;
    final isDriverAdmin = rider['isAdmin'] == true || rider['role'] == 'admin';

    // Format vehicle summary: e.g. "Honda (FB3361) · Bike"
    String vehicleSummary;
    if (vehicleModel.isNotEmpty && plateNumber.isNotEmpty) {
      vehicleSummary = '$vehicleModel ($plateNumber) · $vehicleType';
    } else if (vehicleModel.isNotEmpty) {
      vehicleSummary = '$vehicleModel · $vehicleType';
    } else if (plateNumber.isNotEmpty) {
      vehicleSummary = '$plateNumber · $vehicleType';
    } else {
      vehicleSummary = 'Motorbike · $vehicleType';
    }

    Color badgeBg;
    Color badgeFg;
    String statusText;

    if (isSuspended) {
      badgeBg = const Color(0xFFFEE2E2);
      badgeFg = const Color(0xFF991B1B);
      statusText = 'SUSPENDED';
    } else if (isApproved) {
      badgeBg = const Color(0xFFDCFCE7);
      badgeFg = const Color(0xFF166534);
      statusText = 'APPROVED & ACTIVE';
    } else {
      badgeBg = const Color(0xFFFEF3C7);
      badgeFg = const Color(0xFFB45309);
      statusText = 'PENDING APPROVAL';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSuspended
              ? const Color(0xFFFCA5A5)
              : (isApproved ? const Color(0xFFE5E7EB) : const Color(0xFFFCD34D)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP HEADER ROW (Avatar with status dot, Name & Contacts, Status Badge)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: C.black,
                    child: Icon(_getVehicleIcon(vehicleType), color: const Color(0xFFFFCC00), size: 28),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isSuspended
                            ? const Color(0xFFEF4444)
                            : (isApproved ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.2),
                      ),
                    ),
                  ),
                ],
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
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: Colors.black87),
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
                              border: Border.all(color: const Color(0xFFF59E0B)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield, size: 11, color: Color(0xFFB45309)),
                                SizedBox(width: 2),
                                Text('ADMIN', style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w900, fontSize: 9)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 13, color: Colors.black54),
                        const SizedBox(width: 5),
                        Text(phone, style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.mail_outline, size: 13, color: Colors.black54),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            email.isNotEmpty ? email : 'No email provided',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: badgeFg.withValues(alpha: 0.15)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: badgeFg,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 2. DASHBOARD LINK ROW
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RiderDashboardScreen(
                    riderId: uid,
                    initialRiderData: rider,
                    isAdminView: true,
                  ),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.bar_chart_rounded, size: 18, color: Color(0xFF0284C7)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tap to view Driver Dashboard & all rides',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF0284C7)),
                ],
              ),
            ),
          ),
          const Divider(height: 18, thickness: 0.8, color: Color(0xFFE5E7EB)),

          // 3. VEHICLE & PASSENGER RATING ROW
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vehicle & Plate', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text(
                      vehicleSummary,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Passenger Rating', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '${rating.toStringAsFixed(1)} ($totalRatings reviews)',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.black87),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // 4. SCHEDULED TRIPS TAG
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (rider['isAvailableForScheduled'] ?? true) ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (rider['isAvailableForScheduled'] ?? true) ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  (rider['isAvailableForScheduled'] ?? true) ? Icons.check_circle : Icons.pause_circle_filled,
                  size: 15,
                  color: (rider['isAvailableForScheduled'] ?? true) ? const Color(0xFF166534) : Colors.red.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  (rider['isAvailableForScheduled'] ?? true)
                      ? 'Scheduled Trips: Active / Available'
                      : 'Scheduled Trips: Paused by Driver',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: (rider['isAvailableForScheduled'] ?? true) ? const Color(0xFF166534) : Colors.red.shade800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 5. ACTION BUTTONS ROW 1 (Driver Dashboard & Suspend/Approve)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.black,
                    foregroundColor: const Color(0xFFFFCC00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.grid_view_rounded, size: 17, color: Color(0xFFFFCC00)),
                  label: const Text(
                    'Driver Dashboard',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RiderDashboardScreen(
                          riderId: uid,
                          initialRiderData: rider,
                          isAdminView: true,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isSuspended
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text('Reactivate Account', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                        onPressed: () async {
                          await _authService.setUserSuspensionStatus(uid, isSuspended: false);
                          await _authService.setRiderApprovalStatus(uid, isApproved: true);
                          await NotificationService().notifyUserAccountSuspension(
                            uid: uid,
                            isSuspended: false,
                            role: 'rider',
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name account reactivated!')));
                          }
                        },
                      )
                    : (!isApproved
                        ? ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.check_circle, size: 17),
                            label: const Text('Approve Driver', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                            onPressed: () async {
                              await _authService.setRiderApprovalStatus(uid, isApproved: true);
                              await NotificationService().notifyDriverAccountApproved(
                                driverUid: uid,
                                driverName: name,
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name approved successfully!')));
                              }
                            },
                          )
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.do_not_disturb_alt_rounded, size: 17),
                            label: const Text('Suspend Account', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                            onPressed: () async {
                              await _authService.setUserSuspensionStatus(uid, isSuspended: true, reason: 'Suspended by Admin');
                              await NotificationService().notifyUserAccountSuspension(
                                uid: uid,
                                isSuspended: true,
                                reason: 'Violation of driver policies or admin decision.',
                                role: 'rider',
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name account has been suspended.')));
                              }
                            },
                          )),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 6. ACTION BUTTONS ROW 2 (Make Admin, Reviews, Call, WhatsApp)
          Row(
            children: [
              // 1. Make Admin
              Expanded(
                flex: 4,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: isDriverAdmin ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                    side: BorderSide(color: isDriverAdmin ? const Color(0xFFFCD34D) : const Color(0xFFE5E7EB), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                  ),
                  icon: Icon(
                    isDriverAdmin ? Icons.remove_moderator : Icons.admin_panel_settings_rounded,
                    size: 16,
                    color: isDriverAdmin ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                  ),
                  label: Text(
                    isDriverAdmin ? 'Revoke Admin' : 'Make Admin',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: isDriverAdmin ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => _toggleAdminStatus(uid, name, isDriverAdmin),
                ),
              ),
              const SizedBox(width: 8),

              // 2. Reviews
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                  ),
                  icon: const Icon(Icons.rate_review_outlined, size: 16, color: Colors.black87),
                  label: const Text(
                    'Reviews',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => _showDriverReviewsDialog(uid, name),
                ),
              ),
              const SizedBox(width: 8),

              // 3. Phone Call Button
              Container(
                width: 44,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.call, color: Colors.black87, size: 18),
                  tooltip: 'Call Driver',
                  onPressed: () => _makeCall(phone),
                ),
              ),
              const SizedBox(width: 8),

              // 4. WhatsApp Button
              Container(
                width: 44,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF22C55E), size: 18),
                  tooltip: 'WhatsApp Driver',
                  onPressed: () => _openWhatsApp(phone, 'Hello $name, message from ShanGo Admin Console.'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAdminStatus(String uid, String name, bool currentIsAdmin) async {
    final newStatus = !currentIsAdmin;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newStatus ? 'Promote to Admin?' : 'Revoke Admin Privileges?'),
        content: Text(
          newStatus
              ? 'Are you sure you want to make $name an Admin? They will be able to access the Admin Console, manage rides & pricing, and receive admin dispatch push notifications.'
              : 'Are you sure you want to remove Admin privileges for $name?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus ? Colors.indigo : Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(newStatus ? 'Make Admin' : 'Revoke Admin'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.setUserAdminStatus(uid, isAdmin: newStatus);
      await NotificationService().notifyUserAdminStatusChanged(
        uid: uid,
        isAdmin: newStatus,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus ? '$name is now an Admin!' : 'Admin access revoked for $name.'),
            backgroundColor: newStatus ? Colors.green : Colors.black87,
          ),
        );
      }
    }
  }

  void _showDriverReviewsDialog(String riderId, String riderName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Passenger Reviews for $riderName', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const Divider(height: 16),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _rideService.streamRiderReviews(riderId),
                  builder: (context, snapshot) {
                    final reviews = snapshot.data ?? [];
                    if (reviews.isEmpty) {
                      return const Center(child: Text('No passenger reviews yet for this driver.'));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: reviews.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        final r = reviews[i];
                        final customerName = r['customerName'] ?? 'Passenger';
                        final rating = (r['rating'] as num?)?.toDouble() ?? 5.0;
                        final message = r['message'] ?? '';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(backgroundColor: C.yellow, child: Icon(Icons.person, color: C.black)),
                          title: Text(customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: message.isNotEmpty ? Text('"$message"', style: const TextStyle(fontStyle: FontStyle.italic)) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
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
        ),
      ),
    );
  }

  // ==========================================
  // TAB 3: PASSENGER MANAGEMENT
  // ==========================================
  Widget _buildPassengersTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _usersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: C.yellow));
        }

        final allUsers = snapshot.data ?? [];
        final passengerCount = allUsers.where((u) => u['role'] != 'rider').length;
        final riderCount = allUsers.where((u) => u['role'] == 'rider').length;
        final adminCount = allUsers.where((u) => u['isAdmin'] == true || u['role'] == 'admin').length;
        final suspendedCount = allUsers.where((u) => u['isSuspended'] == true).length;

        final filteredUsers = allUsers.where((u) {
          final isRider = u['role'] == 'rider';
          final isAdmin = u['isAdmin'] == true || u['role'] == 'admin';
          final isSuspended = u['isSuspended'] == true;

          if (_passengerRoleFilter == 'passenger' && isRider) return false;
          if (_passengerRoleFilter == 'rider' && !isRider) return false;
          if (_passengerRoleFilter == 'admin' && !isAdmin) return false;
          if (_passengerRoleFilter == 'suspended' && !isSuspended) return false;

          if (_passengerSearchQuery.isNotEmpty) {
            final name = (u['name'] as String? ?? '').toLowerCase();
            final phone = (u['phone'] as String? ?? '').toLowerCase();
            final email = (u['email'] as String? ?? '').toLowerCase();
            final cnic = (u['cnic'] as String? ?? u['cnicNumber'] as String? ?? '').toLowerCase();
            final plate = (u['vehiclePlate'] as String? ?? u['plateNumber'] as String? ?? u['vehicleNumber'] as String? ?? '').toLowerCase();
            final model = (u['vehicleModel'] as String? ?? '').toLowerCase();
            final city = (u['city'] as String? ?? '').toLowerCase();
            final role = (u['role'] as String? ?? 'passenger').toLowerCase();

            final q = _passengerSearchQuery;
            final matches = name.contains(q) ||
                phone.contains(q) ||
                email.contains(q) ||
                cnic.contains(q) ||
                plate.contains(q) ||
                model.contains(q) ||
                city.contains(q) ||
                role.contains(q);
            if (!matches) return false;
          }

          return true;
        }).toList();

        return Column(
          children: [
            // Filter & Search Header Container
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Bar for Passengers & Riders
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _passengerSearchQuery.isNotEmpty ? C.black : const Color(0xFFE5E7EB),
                        width: _passengerSearchQuery.isNotEmpty ? 1.5 : 1,
                      ),
                    ),
                    child: TextField(
                      controller: _passengerSearchController,
                      focusNode: _passengerSearchFocusNode,
                      onChanged: (val) => setState(() => _passengerSearchQuery = val.trim().toLowerCase()),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Search passenger or rider by name, phone, plate...',
                        hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500, fontWeight: FontWeight.normal),
                        prefixIcon: const Icon(Icons.search, color: Colors.black54, size: 20),
                        suffixIcon: _passengerSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: Colors.black54),
                                onPressed: () {
                                  _passengerSearchController.clear();
                                  setState(() => _passengerSearchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildPassengerFilterChip('Passengers ($passengerCount)', 'passenger', Icons.people_outline),
                        const SizedBox(width: 8),
                        _buildPassengerFilterChip('All Users (${allUsers.length})', 'all', Icons.groups_outlined),
                        const SizedBox(width: 8),
                        _buildPassengerFilterChip('Riders ($riderCount)', 'rider', Icons.two_wheeler),
                        const SizedBox(width: 8),
                        _buildPassengerFilterChip('Admins ($adminCount)', 'admin', Icons.shield_outlined),
                        const SizedBox(width: 8),
                        _buildPassengerFilterChip('Suspended ($suspendedCount)', 'suspended', Icons.block_rounded),
                      ],
                    ),
                  ),

                  // Search results banner
                  if (_passengerSearchQuery.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCD34D)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 14, color: Color(0xFFB45309)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Found ${filteredUsers.length} matching user${filteredUsers.length == 1 ? '' : 's'} for "$_passengerSearchQuery"',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              _passengerSearchController.clear();
                              setState(() => _passengerSearchQuery = '');
                            },
                            child: const Text(
                              'Clear',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: filteredUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_search_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            _passengerSearchQuery.isNotEmpty
                                ? 'No users matching "$_passengerSearchQuery"'
                                : 'No users found in this category.',
                            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Category: ${_passengerRoleFilter.toUpperCase()}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: Text(_passengerSearchQuery.isNotEmpty ? 'Clear Search & Filters' : 'Reset Category'),
                            onPressed: () => setState(() {
                              _passengerSearchController.clear();
                              _passengerSearchQuery = '';
                              _passengerRoleFilter = 'passenger';
                            }),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final p = filteredUsers[index];
                        final uid = p['uid'] ?? '';
                        final name = p['name'] ?? 'User';
                        final phone = p['phone'] ?? 'No Phone';
                        final email = p['email'] ?? '';
                        final isRider = p['role'] == 'rider';
                        final isSuspended = p['isSuspended'] == true;
                        final isPassengerAdmin = p['isAdmin'] == true || p['role'] == 'admin';
                        final vehiclePlate = p['vehiclePlate'] ?? p['plateNumber'] ?? p['vehicleNumber'];
                        final vehicleModel = p['vehicleModel'] ?? (isRider ? 'Motorbike' : null);

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSuspended ? Colors.red.shade300 : Colors.grey.shade200),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: isRider ? const Color(0xFFFEF3C7) : C.yellow,
                                child: Icon(
                                  isRider ? Icons.two_wheeler : Icons.person,
                                  color: isRider ? const Color(0xFFB45309) : C.black,
                                  size: 24,
                                ),
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
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Role badge
                                        Container(
                                          margin: const EdgeInsets.only(left: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isRider ? const Color(0xFFE0E7FF) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: isRider ? const Color(0xFFA5B4FC) : const Color(0xFFCBD5E1)),
                                          ),
                                          child: Text(
                                            isRider ? 'RIDER' : 'PASSENGER',
                                            style: TextStyle(
                                              color: isRider ? const Color(0xFF4338CA) : Colors.blueGrey.shade800,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                        if (isPassengerAdmin)
                                          Container(
                                            margin: const EdgeInsets.only(left: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEF3C7),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFF59E0B)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.shield, size: 10, color: Color(0xFFB45309)),
                                                SizedBox(width: 2),
                                                Text('ADMIN', style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w900, fontSize: 9)),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text('$phone • $email', style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                                    if (isRider && (vehiclePlate != null || vehicleModel != null))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          '${vehicleModel ?? 'Vehicle'} • ${vehiclePlate ?? ''}',
                                          style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    if (isSuspended)
                                      Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                                        child: const Text('ACCOUNT SUSPENDED', style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                              ),
                              if (isRider)
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                  icon: const Icon(Icons.dashboard_outlined, size: 20, color: Colors.indigo),
                                  tooltip: 'Open Driver Dashboard',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RiderDashboardScreen(
                                          riderId: uid,
                                          initialRiderData: p,
                                          isAdminView: true,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                icon: const Icon(Icons.call, size: 20),
                                tooltip: isRider ? 'Call Rider' : 'Call Passenger',
                                onPressed: () => _makeCall(phone),
                              ),
                              const SizedBox(width: 2),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 20),
                                tooltip: 'WhatsApp',
                                onPressed: () => _openWhatsApp(phone, 'Hello $name, message from ShanGo Admin.'),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (val) async {
                                  if (val == 'dashboard') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RiderDashboardScreen(
                                          riderId: uid,
                                          initialRiderData: p,
                                          isAdminView: true,
                                        ),
                                      ),
                                    );
                                  } else if (val == 'suspend') {
                                    await _authService.setUserSuspensionStatus(uid, isSuspended: true);
                                    await NotificationService().notifyUserAccountSuspension(
                                      uid: uid,
                                      isSuspended: true,
                                      role: isRider ? 'rider' : 'customer',
                                    );
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name suspended.')));
                                  } else if (val == 'unsuspend') {
                                    await _authService.setUserSuspensionStatus(uid, isSuspended: false);
                                    await NotificationService().notifyUserAccountSuspension(
                                      uid: uid,
                                      isSuspended: false,
                                      role: isRider ? 'rider' : 'customer',
                                    );
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name unsuspended.')));
                                  } else if (val == 'toggle_admin') {
                                    await _toggleAdminStatus(uid, name, isPassengerAdmin);
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (isRider)
                                    const PopupMenuItem(
                                      value: 'dashboard',
                                      child: Row(
                                        children: [
                                          Icon(Icons.dashboard_customize_outlined, size: 18, color: Colors.indigo),
                                          SizedBox(width: 8),
                                          Text('Driver Dashboard'),
                                        ],
                                      ),
                                    ),
                                  PopupMenuItem(
                                    value: 'toggle_admin',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isPassengerAdmin ? Icons.remove_moderator : Icons.admin_panel_settings,
                                          size: 18,
                                          color: isPassengerAdmin ? Colors.orange.shade800 : Colors.indigo.shade700,
                                        ),
                                        SizedBox(width: 8),
                                        Text(isPassengerAdmin ? 'Revoke Admin' : 'Make Admin'),
                                      ],
                                    ),
                                  ),
                                  if (!isSuspended)
                                    const PopupMenuItem(value: 'suspend', child: Text('Suspend Account', style: TextStyle(color: Colors.red)))
                                  else
                                    const PopupMenuItem(value: 'unsuspend', child: Text('Unsuspend Account', style: TextStyle(color: Colors.green))),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPassengerFilterChip(String label, String key, IconData icon) {
    final isSelected = _passengerRoleFilter == key;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: isSelected ? C.black : Colors.black54),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          color: isSelected ? C.black : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: C.yellow,
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: isSelected ? Colors.amber.shade700 : Colors.grey.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (_) => setState(() => _passengerRoleFilter = key),
    );
  }

  // ==========================================
  // TAB 4: ACCOUNT SWITCH REQUESTS & APPROVAL
  // ==========================================
  Widget _buildAccountSwitchesTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _authService.streamSwitchRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: C.yellow));
        }

        final requests = snapshot.data ?? [];
        if (requests.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_circle_outline, size: 56, color: Colors.green.shade600),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Pending Account Switch Requests',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'When a user requests to switch their account type (Passenger ⇄ Driver), their application will appear here for verification and approval.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (context, index) => _buildSwitchRequestCard(requests[index]),
        );
      },
    );
  }

  Widget _buildSwitchRequestCard(Map<String, dynamic> user) {
    final uid = user['uid'] ?? '';
    final name = user['name'] ?? 'User';
    final email = user['email'] ?? '';
    final phone = user['phone'] ?? (user['switchRequest']?['userPhone'] ?? 'No Phone');
    final req = (user['switchRequest'] as Map<String, dynamic>?) ?? {};
    final currentRole = req['currentRole'] ?? user['role'] ?? 'customer';
    final requestedRole = req['requestedRole'] ?? 'rider';
    final vehicleType = req['vehicleType'] ?? user['vehicleType'] ?? 'Bike';
    final vehicleModel = req['vehicleModel'] ?? user['vehicleModel'] ?? 'N/A';
    final plateNumber = req['plateNumber'] ?? user['plateNumber'] ?? 'N/A';
    final reason = req['reason'] as String?;

    final isTargetDriver = requestedRole == 'rider';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade300, width: 1.2),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isTargetDriver ? C.black : C.yellow,
                child: Icon(
                  isTargetDriver ? Icons.two_wheeler : Icons.person,
                  color: isTargetDriver ? C.yellow : C.black,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('$phone • $email', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_top, size: 12, color: Color(0xFF856404)),
                    SizedBox(width: 4),
                    Text(
                      'PENDING',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF856404)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Role Switch Flow Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text('Current Role', style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      currentRole == 'rider' ? 'Driver / Rider' : 'Passenger',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black87),
                    ),
                  ],
                ),
                const Icon(Icons.arrow_forward_rounded, color: C.black, size: 20),
                Column(
                  children: [
                    const Text('Requested Role', style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      requestedRole == 'rider' ? 'Driver / Rider' : 'Passenger',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.blue.shade800),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // If applying to be Driver, display vehicle info
          if (isTargetDriver) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vehicle Application Details:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.electric_moped_outlined, size: 16, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text('Vehicle: $vehicleType ($vehicleModel)', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.badge_outlined, size: 16, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text('Number Plate: $plateNumber', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Note: "$reason"', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade700, fontSize: 12)),
          ],

          const SizedBox(height: 14),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Approve Switch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () async {
                    await _authService.approveAccountSwitchRequest(uid);
                    await NotificationService().notifyUserSwitchApproved(
                      uid: uid,
                      newRole: requestedRole,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Approved switch for $name to ${requestedRole == 'rider' ? 'Driver' : 'Passenger'}!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () => _showRejectSwitchDialog(uid, name),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.call, size: 20),
                tooltip: 'Call Applicant',
                onPressed: () => _makeCall(phone),
              ),
              IconButton(
                icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 20),
                tooltip: 'WhatsApp Applicant',
                onPressed: () => _openWhatsApp(phone, 'Hello $name, regarding your ShanGo account switch request.'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRejectSwitchDialog(String uid, String name) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Reject Switch for $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter reason for declining the account switch:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'e.g. Invalid vehicle documents or plate number',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _authService.rejectAccountSwitchRequest(uid, reason: reasonController.text.trim());
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Account switch declined for $name.')),
                );
              }
            },
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 5: INTERCITY DISPATCH & DRIVER LINKING
  // ==========================================
  String _intercityFilter = 'all'; // 'all', 'unassigned', 'confirmed', 'completed'

  Widget _buildIntercityDispatchTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _rideService.streamAllIntercityBookings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: C.yellow));
        }

        final allBookings = snapshot.data ?? [];
        if (allBookings.isEmpty) {
          return const Center(child: Text('No on-demand intercity requests found.'));
        }

        final unassignedCount = allBookings.where((b) => b['riderName'] == null && b['status'] != 'completed').length;
        final confirmedCount = allBookings.where((b) => b['riderName'] != null && b['status'] != 'completed').length;
        final completedCount = allBookings.where((b) => b['status'] == 'completed').length;

        final filteredBookings = allBookings.where((b) {
          if (_intercityFilter == 'unassigned') return b['riderName'] == null && b['status'] != 'completed';
          if (_intercityFilter == 'confirmed') return b['riderName'] != null && b['status'] != 'completed';
          if (_intercityFilter == 'completed') return b['status'] == 'completed';
          return true;
        }).toList();

        return Column(
          children: [
            // Filter Pills
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.white,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildIntercityFilterChip('All (${allBookings.length})', 'all'),
                    const SizedBox(width: 8),
                    _buildIntercityFilterChip('Needs Driver ($unassignedCount)', 'unassigned'),
                    const SizedBox(width: 8),
                    _buildIntercityFilterChip('Confirmed ($confirmedCount)', 'confirmed'),
                    const SizedBox(width: 8),
                    _buildIntercityFilterChip('Completed ($completedCount)', 'completed'),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: filteredBookings.isEmpty
                  ? Center(child: Text('No trips under $_intercityFilter category.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredBookings.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) => _buildIntercityBookingCard(filteredBookings[index]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIntercityFilterChip(String label, String key) {
    final isSelected = _intercityFilter == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500, color: isSelected ? C.black : Colors.black87)),
      selected: isSelected,
      selectedColor: C.yellow,
      backgroundColor: C.grey,
      onSelected: (_) => setState(() => _intercityFilter = key),
    );
  }

  Widget _buildIntercityBookingCard(Map<String, dynamic> booking) {
    final id = booking['id'] ?? '';
    final from = booking['fromCity'] ?? 'Bannu';
    final to = booking['toCity'] ?? 'Peshawar';
    final customerName = booking['customerName'] ?? 'Passenger';
    final customerPhone = booking['customerPhone'] ?? '';
    final isRoundTrip = booking['isRoundTrip'] == true || booking['tripType'] == 'two_way';
    final vehicle = booking['vehicleType'] ?? 'Car';
    final fare = (booking['fare'] as num?)?.toInt() ?? 0;
    final originalFare = (booking['originalFare'] as num?)?.toInt() ?? fare;
    final offeredFare = (booking['offeredFare'] as num?)?.toInt();
    final negotiationStatus = booking['negotiationStatus'] ?? 'standard';
    final adminMessage = booking['adminMessage'];
    final scheduledDate = booking['scheduledDate'] ?? '';
    final scheduledTime = booking['scheduledTime'] ?? '';
    final returnDate = booking['returnDate'];
    final returnTime = booking['returnTime'];
    final status = booking['status'] ?? 'scheduled';
    final riderName = booking['riderName'];
    final riderPhone = booking['riderPhone'];
    final pickupAddress = booking['pickupAddress'] ?? '';
    final dropAddress = booking['dropAddress'] ?? '';
    final pickupCoordinates = booking['pickupCoordinates'] as Map<String, dynamic>?;
    final dropCoordinates = booking['dropCoordinates'] as Map<String, dynamic>?;

    final bool isUnderReview = negotiationStatus == 'under_review' || status == 'under_negotiation';

    Color statusBg = Colors.amber.shade100;
    Color statusFg = Colors.amber.shade900;
    String statusLabel = 'SCHEDULED';

    if (status == 'confirmed' || riderName != null) {
      statusBg = const Color(0xFFDCFCE7);
      statusFg = const Color(0xFF166534);
      statusLabel = 'CONFIRMED';
    } else if (status == 'completed') {
      statusBg = const Color(0xFFDBEAFE);
      statusFg = const Color(0xFF1E40AF);
      statusLabel = 'COMPLETED';
    } else if (status == 'cancelled') {
      statusBg = const Color(0xFFFEE2E2);
      statusFg = const Color(0xFF991B1B);
      statusLabel = 'CANCELLED';
    } else if (isUnderReview) {
      statusBg = const Color(0xFFFEF3C7);
      statusFg = const Color(0xFF92400E);
      statusLabel = 'PRICE OFFER';
    } else if (riderName == null) {
      statusBg = const Color(0xFFFFEDD5);
      statusFg = const Color(0xFF9A3412);
      statusLabel = 'NEEDS DRIVER';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUnderReview
              ? Colors.amber.shade400
              : (riderName == null ? Colors.orange.shade300 : const Color(0xFFE5E7EB)),
          width: (isUnderReview || riderName == null) ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP HEADER: Route, Vehicle, RoundTrip badge, Status Badge, Agreed Fare
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '$from ➔ $to',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.black),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isRoundTrip ? 'Round Trip' : 'One Way',
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(Icons.event, size: 14, color: Colors.black54),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '$scheduledDate at $scheduledTime • $vehicle',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (isRoundTrip && returnDate != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '🔄 Return: $returnDate at ${returnTime ?? ""}',
                                style: TextStyle(color: Colors.green.shade800, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            statusLabel,
                            style: TextStyle(color: statusFg, fontWeight: FontWeight.w900, fontSize: 10.5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'PKR $fare',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.black),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Negotiation banner if passenger submitted a custom offer
          if (isUnderReview && offeredFare != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_offer, color: Color(0xFFD97706), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Passenger Proposed Fare: PKR $offeredFare (Standard: PKR $originalFare)',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            await _rideService.adminApproveNegotiatedPrice(id, offeredFare);
                            final passengerUid = booking['customerId'] ?? booking['userId'];
                            if (passengerUid != null && passengerUid.isNotEmpty) {
                              await NotificationService().notifyPassengerPriceAccepted(
                                passengerUid: passengerUid,
                                fromCity: from,
                                toCity: to,
                                acceptedFare: offeredFare,
                                bookingId: id,
                              );
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Offer of PKR $offeredFare accepted! Now assigning driver.')));
                              _showAssignDriverDialog(id, {...booking, 'fare': offeredFare});
                            }
                          },
                          child: Text('Accept PKR $offeredFare', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _showCounterOfferDialog(
                          id,
                          offeredFare,
                          originalFare,
                          passengerUid: booking['customerId'] ?? booking['userId'],
                          fromCity: from,
                          toCity: to,
                        ),
                        child: const Text('Counter', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        icon: const Icon(Icons.close, color: Colors.red, size: 18),
                        onPressed: () => _showRejectOfferDialog(id),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (negotiationStatus == 'admin_countered') ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Counter offer PKR $fare sent to passenger.${adminMessage != null ? " ($adminMessage)" : ""}',
                      style: TextStyle(fontSize: 11.5, color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 2. ROUTE STEPPER (Addresses)
          if (pickupAddress.isNotEmpty || dropAddress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  children: [
                    if (pickupAddress.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                text: 'Pickup: ',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                                children: [
                                  TextSpan(text: pickupAddress, style: const TextStyle(fontWeight: FontWeight.normal, color: Colors.black87)),
                                ],
                              ),
                            ),
                          ),
                          if (pickupCoordinates != null)
                            InkWell(
                              onTap: () => _openMaps(pickupCoordinates['latitude'], pickupCoordinates['longitude']),
                              child: Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                                child: const Text('Map 🗺️', style: TextStyle(color: Color(0xFF2563EB), fontSize: 10.5, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                    if (pickupAddress.isNotEmpty && dropAddress.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 3.5, top: 3, bottom: 3),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(width: 1, height: 10, color: const Color(0xFFD1D5DB)),
                        ),
                      ),
                    if (dropAddress.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                text: 'Dropoff: ',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                                children: [
                                  TextSpan(text: dropAddress, style: const TextStyle(fontWeight: FontWeight.normal, color: Colors.black87)),
                                ],
                              ),
                            ),
                          ),
                          if (dropCoordinates != null)
                            InkWell(
                              onTap: () => _openMaps(dropCoordinates['latitude'], dropCoordinates['longitude']),
                              child: Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                                child: const Text('Map 🗺️', style: TextStyle(color: Color(0xFF2563EB), fontSize: 10.5, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

          // 3. PASSENGER & DRIVER ROWS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // Passenger Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 13,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person, size: 15, color: C.black),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customerName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                            Text(customerPhone.isNotEmpty ? customerPhone : 'No Phone', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        icon: const Icon(Icons.call, size: 18, color: Colors.black87),
                        tooltip: 'Call Passenger',
                        onPressed: () => _makeCall(customerPhone),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 18),
                        tooltip: 'WhatsApp Passenger',
                        onPressed: () => _openWhatsApp(customerPhone, 'Hello $customerName, ShanGo Admin regarding your intercity ride from $from to $to.'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Driver Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: riderName != null ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: riderName != null ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: riderName != null ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                        child: Icon(
                          riderName != null ? Icons.two_wheeler : Icons.warning_amber_rounded,
                          size: 15,
                          color: riderName != null ? const Color(0xFF166534) : const Color(0xFFB45309),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              riderName != null ? 'Driver: $riderName' : 'Driver: Not Assigned',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: riderName != null ? const Color(0xFF166534) : const Color(0xFFB45309),
                              ),
                            ),
                            Text(
                              riderName != null ? (riderPhone ?? '') : 'Tap below to assign approved driver',
                              style: TextStyle(
                                fontSize: 11,
                                color: riderName != null ? const Color(0xFF15803D) : const Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (riderName != null) ...[
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          icon: const Icon(Icons.call, size: 18, color: Colors.black87),
                          tooltip: 'Call Driver',
                          onPressed: () => _makeCall(riderPhone),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 18),
                          tooltip: 'WhatsApp Driver',
                          onPressed: () => _openWhatsApp(riderPhone, 'Hello $riderName, ShanGo Intercity Trip assigned: $from to $to. Passenger: $customerName ($customerPhone).'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. ACTION BUTTONS
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: riderName == null ? C.yellow : C.black,
                      foregroundColor: riderName == null ? C.black : C.yellow,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      elevation: 0,
                    ),
                    icon: Icon(riderName == null ? Icons.add_link : Icons.swap_horiz_rounded, size: 18),
                    label: Text(
                      riderName == null ? 'Assign Driver & Link' : 'Reassign Driver',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                    onPressed: () => _showAssignDriverDialog(id, booking),
                  ),
                ),
                if (status != 'completed' && status != 'cancelled') ...[
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFDCFCE7),
                      foregroundColor: const Color(0xFF166534),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.all(10),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    tooltip: 'Mark Completed',
                    onPressed: () async {
                      await _rideService.updateIntercityBookingStatus(id, 'completed');
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking marked as completed!')));
                    },
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE2E2),
                      foregroundColor: const Color(0xFF991B1B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.all(10),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    tooltip: 'Cancel Booking',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Cancel Intercity Booking?'),
                          content: Text('Are you sure you want to cancel the booking for $from ➔ $to? Notifications will be sent to the passenger and driver.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, Keep')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Yes, Cancel Trip'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await _rideService.updateIntercityBookingStatus(id, 'cancelled');
                        await NotificationService().notifyTripCancelled(
                          fromCity: from,
                          toCity: to,
                          cancelledBy: 'Admin Dispatch',
                          passengerUid: booking['customerId'] ?? booking['userId'],
                          driverUid: booking['riderId'],
                          bookingId: id,
                          reason: 'Trip cancelled by Admin.',
                        );
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking cancelled.')));
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCounterOfferDialog(
    String bookingId,
    int offeredFare,
    int originalFare, {
    String? passengerUid,
    String? fromCity,
    String? toCity,
  }) {
    final counterController = TextEditingController(text: '${((offeredFare + originalFare) / 2).round()}');
    final noteController = TextEditingController(text: 'Admin counter offer');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Counter-Offer Fare', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Passenger offered PKR $offeredFare (Standard PKR $originalFare). Enter your counter-offer:'),
            const SizedBox(height: 14),
            TextField(
              controller: counterController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Counter Fare (PKR)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Message to passenger', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
            onPressed: () async {
              final val = int.tryParse(counterController.text.trim());
              if (val != null && val > 0) {
                Navigator.pop(ctx);
                await _rideService.adminCounterNegotiatedPrice(bookingId, val, adminMessage: noteController.text.trim());
                if (passengerUid != null && passengerUid.isNotEmpty) {
                  await NotificationService().notifyPassengerCounterOffer(
                    passengerUid: passengerUid,
                    counterFare: val,
                    fromCity: fromCity ?? 'Origin',
                    toCity: toCity ?? 'Destination',
                    bookingId: bookingId,
                    adminMessage: noteController.text.trim(),
                  );
                }
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Counter offer of PKR $val sent to passenger.')));
              }
            },
            child: const Text('Send Counter Offer'),
          ),
        ],
      ),
    );
  }

  void _showRejectOfferDialog(String bookingId) {
    final reasonController = TextEditingController(text: 'Offered price is too low for this route.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Price Offer', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The passenger will be informed and can re-submit an offer or proceed with the standard fare.'),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason / Message', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _rideService.adminRejectNegotiatedPrice(bookingId, adminMessage: reasonController.text.trim());
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer rejected and passenger notified.')));
            },
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 5: ROUTES, VEHICLES & PRICING MANAGEMENT
  // ==========================================
  Widget _buildRoutesAndPricingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Quick Action Buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune, color: C.yellow, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Cities, Vehicles & Pricing Control',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Add or update intercity routes, vehicle categories, and fixed pricing. Changes reflect instantly in the passenger on-demand booking screen.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_road, size: 16),
                      label: const Text('+ Add City Route', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: C.yellow, foregroundColor: C.black),
                      onPressed: () => _showAddEditRouteDialog(),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('+ Add Vehicle Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: C.black),
                      onPressed: () => _showAddEditVehicleDialog(),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                      label: const Text('Seed / Restore Defaults', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white30)),
                      onPressed: () async {
                        await _rideService.seedDefaultIntercityRoutesAndVehicles();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Default routes & vehicles seeded to Firestore!')));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section -1: Official Admin Helpline & WhatsApp Settings
          StreamBuilder<Map<String, dynamic>>(
            stream: _rideService.streamAdminContactInfo(),
            builder: (context, snapshot) {
              final contact = snapshot.data ?? RideService.defaultAdminContact;
              final adminPhone = (contact['adminPhone'] as String?)?.isNotEmpty == true
                  ? contact['adminPhone'] as String
                  : '+923451234567';
              final adminWhatsApp = (contact['adminWhatsApp'] as String?)?.isNotEmpty == true
                  ? contact['adminWhatsApp'] as String
                  : adminPhone;
              final adminEmail = (contact['adminEmail'] as String?)?.isNotEmpty == true
                  ? contact['adminEmail'] as String
                  : 'info@jabirulabs.com';
              final supportAddress = (contact['supportAddress'] as String?)?.isNotEmpty == true
                  ? contact['supportAddress'] as String
                  : 'Bannu / Peshawar, Khyber Pakhtunkhwa, Pakistan';

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF1E293B), Colors.grey.shade900],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.support_agent, color: Color(0xFF25D366), size: 24),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Official Admin Helpline & WhatsApp',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                              ),
                              Text(
                                'Riders & passengers connect to these numbers across the app',
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit, size: 14),
                          label: const Text('Edit Contact', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: C.yellow,
                            foregroundColor: C.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _showEditAdminContactDialog(
                            currentPhone: adminPhone,
                            currentWhatsApp: adminWhatsApp,
                            currentEmail: adminEmail,
                            currentAddress: supportAddress,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.phone, color: Colors.lightBlueAccent, size: 16),
                                    SizedBox(width: 6),
                                    Text('Helpline / Call', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  adminPhone,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _makeCall(adminPhone),
                                  child: const Text('Test Call ↗', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.chat, color: Color(0xFF25D366), size: 16),
                                    SizedBox(width: 6),
                                    Text('Admin WhatsApp', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  adminWhatsApp,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _openWhatsApp(adminWhatsApp, 'ShanGo Admin helpline test message.'),
                                  child: const Text('Test Chat ↗', style: TextStyle(color: Color(0xFF25D366), fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.email_outlined, color: Colors.white60, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Support Email: $adminEmail  •  Address: $supportAddress',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Section 0: Local In-City Fare & Commission Rates
          const Text('Local In-City GPS Fare & Commission', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),

          StreamBuilder<Map<String, dynamic>>(
            stream: _rideService.streamLocalPricing(),
            builder: (context, snapshot) {
              final pricing = snapshot.data ?? {'baseFare': 150.0, 'perKmRate': 40.0, 'commissionPercent': 15.0};
              final baseFare = (pricing['baseFare'] as num?)?.toDouble() ?? 150.0;
              final perKm = (pricing['perKmRate'] as num?)?.toDouble() ?? 40.0;
              final comm = (pricing['commissionPercent'] as num?)?.toDouble() ?? 15.0;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: C.yellow.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.calculate, color: C.black, size: 22),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Local Ride Live Calculation Rates', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              Text('Formula: Fare = Base Fare + (Distance in km × Per Km Rate)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit, size: 14),
                          label: const Text('Edit Rates', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
                          onPressed: () => _showEditLocalPricingDialog(baseFare, perKm, comm),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricMini(
                            'Base Starting Fare',
                            'PKR ${baseFare.toStringAsFixed(0)}',
                            Icons.flag,
                            Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricMini(
                            'Per-Kilometer Rate',
                            'PKR ${perKm.toStringAsFixed(0)} / km',
                            Icons.speed,
                            Colors.green.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricMini(
                            'Platform Fee',
                            '${comm.toStringAsFixed(0)}%',
                            Icons.percent,
                            Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Section 0.5: Remote App Version & Force Update Control
          const Text('App Version & Play Store Update Control', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),

          StreamBuilder<AppVersionInfo>(
            stream: AppVersionService().streamVersionInfo(),
            builder: (context, snapshot) {
              final info = snapshot.data ?? AppVersionInfo.defaultInfo();
              final isLocked = info.forceUpdate ||
                  info.minBuildNumber > AppVersionService.currentAppBuildNumber ||
                  AppVersionService.compareVersions(AppVersionService.currentAppVersion, info.minVersion) < 0;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isLocked ? Colors.red.shade300 : Colors.grey.shade300),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (isLocked ? Colors.red : Colors.green).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isLocked ? Icons.system_security_update_warning_rounded : Icons.system_update_rounded,
                            color: isLocked ? Colors.red.shade700 : Colors.green.shade700,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLocked ? 'Force Update ACTIVE (Older Apps Blocked)' : 'App Version Gate (Normal)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: isLocked ? Colors.red.shade900 : Colors.black87,
                                ),
                              ),
                              Text(
                                'Manage release version & update URLs in Firebase',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit, size: 14),
                          label: const Text('Configure', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
                          onPressed: () => _showEditVersionDialog(info),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricMini(
                            'Installed Version',
                            'v${AppVersionService.currentAppVersion}',
                            Icons.phone_android,
                            Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricMini(
                            'Required Min Version',
                            'v${info.minVersion}',
                            Icons.verified_outlined,
                            isLocked ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricMini(
                            'Build Code',
                            '#${info.minBuildNumber}',
                            Icons.numbers,
                            Colors.purple.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: C.grey,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            info.updateUrl.contains('play.google.com') ? Icons.shop_two_rounded : Icons.link_rounded,
                            size: 16,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              info.updateUrl,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Section 1: Configured Routes
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Intercity Routes & Base Fares', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _rideService.streamIntercityRoutes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: C.yellow)));
              }

              final routes = snapshot.data ?? [];
              if (routes.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.alt_route, size: 40, color: Colors.black38),
                        const SizedBox(height: 8),
                        const Text('No routes configured yet in database.', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text('Tap "Seed / Restore Defaults" above to load standard Bannu, Peshawar, Islamabad routes.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await _rideService.seedDefaultIntercityRoutesAndVehicles();
                            messenger.showSnackBar(const SnackBar(content: Text('Default routes loaded!')));
                          },
                          child: const Text('Seed Standard Rates'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: routes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final r = routes[index];
                  final routeId = r['id'] ?? '';
                  final from = r['from'] ?? 'Bannu';
                  final to = r['to'] ?? 'Peshawar';
                  final distance = r['distanceKm'] ?? 0;
                  final duration = r['durationText'] ?? '';
                  final baseFares = (r['baseFares'] as Map<String, dynamic>?) ?? {};

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.directions, color: C.black, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$from ➔ $to',
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                  tooltip: 'Edit Route & Pricing',
                                  onPressed: () => _showAddEditRouteDialog(r),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                  tooltip: 'Delete Route',
                                  onPressed: () => _showDeleteRouteDialog(routeId, from, to),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Text(
                          'Distance: $distance km • Duration: $duration',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                        ),
                        const Divider(height: 16),
                        const Text('Vehicle Fixed Fares:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: baseFares.entries.map((entry) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: C.grey,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${entry.key}: PKR ${entry.value}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),

          const SizedBox(height: 24),

          // Section 2: Configured Vehicle Types
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fleet & Vehicle Categories', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _rideService.streamIntercityVehicles(),
            builder: (context, snapshot) {
              final vehicles = snapshot.data ?? [];
              if (vehicles.isEmpty) {
                return const Text('No custom vehicle types configured.', style: TextStyle(fontSize: 12, color: Colors.black54));
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: vehicles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final v = vehicles[index];
                  final vehicleId = v['id'] ?? '';
                  final title = v['title'] ?? v['key'] ?? '';
                  final subtitle = v['subtitle'] ?? '';
                  final capacity = v['capacity'] ?? 4;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$title (Capacity: $capacity Pax)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                              if (subtitle.isNotEmpty)
                                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                              onPressed: () => _showAddEditVehicleDialog(v),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              onPressed: () async {
                                await _rideService.deleteIntercityVehicle(vehicleId);
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle type deleted.')));
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddEditRouteDialog([Map<String, dynamic>? existing]) {
    final isEditing = existing != null;
    final fromController = TextEditingController(text: existing?['from'] ?? 'Bannu');
    final toController = TextEditingController(text: existing?['to'] ?? 'Peshawar');
    final distanceController = TextEditingController(text: '${existing?["distanceKm"] ?? 180}');
    final durationController = TextEditingController(text: existing?['durationText'] ?? '3.5 Hours');

    final Map<String, dynamic> existingFares = (existing?['baseFares'] as Map<String, dynamic>?) ?? {};
    final sedanController = TextEditingController(text: '${existingFares["AC Sedan Car"] ?? 6500}');
    final economyController = TextEditingController(text: '${existingFares["Economy Car"] ?? 5000}');
    final bikeController = TextEditingController(text: '${existingFares["Bike / Express"] ?? 2800}');
    final hiaceController = TextEditingController(text: '${existingFares["HiAce / 7-Seater"] ?? 9500}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEditing ? 'Edit Intercity Route' : 'Add New Intercity Route', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: fromController,
                decoration: const InputDecoration(labelText: 'Origin / From City (e.g. Bannu)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: toController,
                decoration: const InputDecoration(labelText: 'Destination / To City (e.g. Islamabad)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: distanceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Distance (KM)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: durationController,
                      decoration: const InputDecoration(labelText: 'Duration (e.g. 4.0 Hours)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Fixed Fares (PKR):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: sedanController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'AC Sedan Car Fare (PKR)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: economyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Economy Car Fare (PKR)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car_outlined)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: bikeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Bike / Express Fare (PKR)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.two_wheeler)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: hiaceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'HiAce / 7-Seater Fare (PKR)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.airport_shuttle)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
            onPressed: () async {
              final from = fromController.text.trim();
              final to = toController.text.trim();
              if (from.isEmpty || to.isEmpty) return;

              final routeData = {
                'from': from,
                'to': to,
                'distanceKm': double.tryParse(distanceController.text.trim()) ?? 100,
                'durationText': durationController.text.trim(),
                'baseFares': {
                  'AC Sedan Car': int.tryParse(sedanController.text.trim()) ?? 6500,
                  'Economy Car': int.tryParse(economyController.text.trim()) ?? 5000,
                  'Bike / Express': int.tryParse(bikeController.text.trim()) ?? 2800,
                  'HiAce / 7-Seater': int.tryParse(hiaceController.text.trim()) ?? 9500,
                },
              };

              Navigator.pop(ctx);
              if (isEditing) {
                await _rideService.updateIntercityRoute(existing['id'], routeData);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Route $from ➔ $to updated!')));
              } else {
                await _rideService.addIntercityRoute(routeData);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Route $from ➔ $to added successfully!')));
              }
            },
            child: Text(isEditing ? 'Save Changes' : 'Add Route'),
          ),
        ],
      ),
    );
  }

  void _showDeleteRouteDialog(String routeId, String from, String to) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Route', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete the route $from ➔ $to?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _rideService.deleteIntercityRoute(routeId);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Route $from ➔ $to deleted.')));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddEditVehicleDialog([Map<String, dynamic>? existing]) {
    final isEditing = existing != null;
    final keyController = TextEditingController(text: existing?['key'] ?? '');
    final titleController = TextEditingController(text: existing?['title'] ?? '');
    final subtitleController = TextEditingController(text: existing?['subtitle'] ?? '');
    final capacityController = TextEditingController(text: '${existing?["capacity"] ?? 4}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEditing ? 'Edit Vehicle Type' : 'Add Vehicle Category', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(labelText: 'Unique Key (e.g. Luxury SUV)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Display Title (e.g. Prado / Land Cruiser)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: subtitleController,
              decoration: const InputDecoration(labelText: 'Subtitle (e.g. 4x4 Luxury, 6-7 Pax)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: capacityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Passenger Capacity', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
            onPressed: () async {
              final key = keyController.text.trim();
              if (key.isEmpty) return;

              final data = {
                'key': key,
                'title': titleController.text.trim().isNotEmpty ? titleController.text.trim() : key,
                'subtitle': subtitleController.text.trim(),
                'capacity': int.tryParse(capacityController.text.trim()) ?? 4,
              };

              Navigator.pop(ctx);
              if (isEditing) {
                await _rideService.updateIntercityVehicle(existing['id'], data);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vehicle $key updated.')));
              } else {
                await _rideService.addIntercityVehicle(data);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vehicle $key added.')));
              }
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _showEditAdminContactDialog({
    required String currentPhone,
    required String currentWhatsApp,
    required String currentEmail,
    required String currentAddress,
  }) {
    final phoneController = TextEditingController(text: currentPhone);
    final waController = TextEditingController(text: currentWhatsApp);
    final emailController = TextEditingController(text: currentEmail);
    final addressController = TextEditingController(text: currentAddress);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.support_agent, color: Color(0xFF25D366)),
            SizedBox(width: 8),
            Text('Admin Contact & Helpline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set the official phone number and WhatsApp where drivers and passengers can reach ShanGo Admin. Changes reflect immediately across all user apps:',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Admin Helpline Phone (Calls)',
                  hintText: 'e.g. +923440986366 or 03440986366',
                  prefixIcon: Icon(Icons.phone, color: Colors.blue),
                  border: OutlineInputBorder(),
                  helperText: 'Dials when users tap Call Helpline',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: waController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Admin WhatsApp Number',
                  hintText: 'e.g. +923440986366',
                  prefixIcon: Icon(Icons.chat, color: Color(0xFF25D366)),
                  border: OutlineInputBorder(),
                  helperText: 'Opens WhatsApp chat when users tap Admin WhatsApp',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Support Email',
                  hintText: 'e.g. info@jabirulabs.com',
                  prefixIcon: Icon(Icons.email, color: Colors.purple),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: addressController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Support / Office Address',
                  hintText: 'e.g. Bannu / Peshawar, KPK',
                  prefixIcon: Icon(Icons.location_on, color: Colors.red),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
            onPressed: () async {
              final newPhone = phoneController.text.trim();
              final newWa = waController.text.trim();
              final newEmail = emailController.text.trim();
              final newAddress = addressController.text.trim();

              if (newPhone.isEmpty || newWa.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide both Phone and WhatsApp number.')),
                );
                return;
              }

              Navigator.pop(ctx);
              await _rideService.updateAdminContactInfo(
                adminPhone: newPhone,
                adminWhatsApp: newWa,
                adminEmail: newEmail.isNotEmpty ? newEmail : null,
                supportAddress: newAddress.isNotEmpty ? newAddress : null,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Admin contact info saved! Phone: $newPhone, WhatsApp: $newWa'),
                    backgroundColor: Colors.green.shade800,
                  ),
                );
              }
            },
            child: const Text('Save Contact Info', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditLocalPricingDialog(double currentBase, double currentPerKm, double currentComm) {
    final baseController = TextEditingController(text: currentBase.toStringAsFixed(0));
    final perKmController = TextEditingController(text: currentPerKm.toStringAsFixed(0));
    final commController = TextEditingController(text: currentComm.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_road, color: C.black),
            SizedBox(width: 8),
            Text('Local GPS Ride Pricing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Update real-time live map calculations for in-city passenger ride requests:',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: baseController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Base Starting Fare (PKR)',
                  hintText: 'e.g. 150',
                  prefixIcon: Icon(Icons.flag, color: Colors.blue),
                  border: OutlineInputBorder(),
                  helperText: 'Fixed starting charge per trip',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: perKmController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Per-Kilometer Rate (PKR / km)',
                  hintText: 'e.g. 40',
                  prefixIcon: Icon(Icons.speed, color: Colors.green),
                  border: OutlineInputBorder(),
                  helperText: 'Added for each kilometer travelled',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: commController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Platform Fee (%)',
                  hintText: 'e.g. 15',
                  prefixIcon: Icon(Icons.percent, color: Colors.orange),
                  border: OutlineInputBorder(),
                  helperText: 'Default platform commission on rides',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
            onPressed: () async {
              final newBase = double.tryParse(baseController.text.trim()) ?? currentBase;
              final newPerKm = double.tryParse(perKmController.text.trim()) ?? currentPerKm;
              final newComm = double.tryParse(commController.text.trim()) ?? currentComm;

              Navigator.pop(ctx);
              await _rideService.updateLocalPricing(
                baseFare: newBase,
                perKmRate: newPerKm,
                commissionPercent: newComm,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Local pricing updated: Base PKR ${newBase.toStringAsFixed(0)} + PKR ${newPerKm.toStringAsFixed(0)}/km!'),
                    backgroundColor: Colors.green.shade800,
                  ),
                );
              }
            },
            child: const Text('Save Pricing', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditVersionDialog(AppVersionInfo current) {
    final minVerController = TextEditingController(text: current.minVersion);
    final minBuildController = TextEditingController(text: current.minBuildNumber.toString());
    final latestVerController = TextEditingController(text: current.latestVersion);
    final urlController = TextEditingController(text: current.updateUrl);
    final titleController = TextEditingController(text: current.title);
    final msgController = TextEditingController(text: current.message);
    final notesController = TextEditingController(text: current.releaseNotes);
    bool forceUpdate = current.forceUpdate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.system_update_rounded, color: C.black),
              SizedBox(width: 8),
              Text('App Release & Version Gate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'When you release an update on Google Play or website, set the minimum required version below. Older apps will immediately stop working and direct users to update.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minVerController,
                        decoration: const InputDecoration(
                          labelText: 'Min Version',
                          hintText: 'e.g. 1.0.1',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: minBuildController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Min Build Code',
                          hintText: 'e.g. 2',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: latestVerController,
                  decoration: const InputDecoration(
                    labelText: 'Latest Display Version',
                    hintText: 'e.g. 1.0.1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'Play Store or Website URL',
                    hintText: 'https://play.google.com/store/apps/details?id=com.jabirulabs.shango',
                    border: OutlineInputBorder(),
                    helperText: 'Opens Play Store app or browser on click',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Popup Alert Title',
                    hintText: 'New Update Available!',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Popup Message',
                    hintText: 'Please update the app to continue using our services.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Release Notes (Optional)',
                    hintText: '• Improved live GPS tracking\n• Bug fixes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: forceUpdate ? Colors.red.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: forceUpdate ? Colors.red.shade300 : Colors.grey.shade300),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Force Update Kill Switch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(
                      forceUpdate
                          ? 'ACTIVE: Blocks all current app instances immediately!'
                          : 'INACTIVE: Blocks only apps below the Min Version.',
                      style: TextStyle(fontSize: 11, color: forceUpdate ? Colors.red.shade900 : Colors.black54),
                    ),
                    value: forceUpdate,
                    thumbColor: const WidgetStatePropertyAll(Colors.red),
                    onChanged: (val) => setDialogState(() => forceUpdate = val),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
              onPressed: () async {
                final minVer = minVerController.text.trim();
                final minBuild = int.tryParse(minBuildController.text.trim()) ?? 1;
                final latestVer = latestVerController.text.trim();
                final url = urlController.text.trim();
                final title = titleController.text.trim();
                final msg = msgController.text.trim();
                final notes = notesController.text.trim();

                Navigator.pop(ctx);
                await AppVersionService().updateVersionSettings(
                  minVersion: minVer.isNotEmpty ? minVer : '1.0.0',
                  minBuildNumber: minBuild,
                  latestVersion: latestVer.isNotEmpty ? latestVer : minVer,
                  forceUpdate: forceUpdate,
                  updateUrl: url.isNotEmpty ? url : 'https://play.google.com/store/apps/details?id=com.jabirulabs.shango',
                  title: title.isNotEmpty ? title : 'New Update Available!',
                  message: msg.isNotEmpty ? msg : 'Please update the app to continue using ShanGo.',
                  releaseNotes: notes,
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Version settings saved! Min Version: $minVer (Build #$minBuild)'),
                      backgroundColor: Colors.green.shade800,
                    ),
                  );
                }
              },
              child: const Text('Save & Broadcast', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricMini(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showAssignDriverDialog(String bookingId, Map<String, dynamic> booking) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => AssignDriverModal(
        bookingId: bookingId,
        booking: booking,
        onAssigned: () {
          Navigator.pop(ctx);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Driver assigned and linked with passenger!'), backgroundColor: Colors.green),
            );
          }
        },
      ),
    );
  }
}

class AssignDriverModal extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> booking;
  final VoidCallback onAssigned;

  const AssignDriverModal({
    super.key,
    required this.bookingId,
    required this.booking,
    required this.onAssigned,
  });

  @override
  State<AssignDriverModal> createState() => _AssignDriverModalState();
}

class _AssignDriverModalState extends State<AssignDriverModal> {
  final RideService _rideService = RideService();
  final TextEditingController _driverNameController = TextEditingController();
  final TextEditingController _driverPhoneController = TextEditingController();
  final TextEditingController _fareController = TextEditingController();
  final TextEditingController _driverSearchController = TextEditingController();
  String? _selectedRiderUid;
  bool _saving = false;
  String _selectedVehicleFilter = 'all';
  String _driverSearchQuery = '';

  bool _matchesVehicle(String? vehicleType, String filterKey) {
    if (filterKey == 'all') return true;
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

  IconData _getDriverVehicleIcon(String? vehicleType) {
    final v = (vehicleType ?? '').trim().toLowerCase();
    if (v.contains('car') || v.contains('taxi') || v.contains('sedan') || v.contains('cab')) {
      return Icons.directions_car;
    }
    if (v.contains('auto') || v.contains('rickshaw')) {
      return Icons.electric_rickshaw;
    }
    return Icons.two_wheeler;
  }

  String _safeDriverName(Map<String, dynamic> driver) {
    final rawName = driver['name'];
    if (rawName != null &&
        rawName.toString().trim().isNotEmpty &&
        rawName.toString().trim().toLowerCase() != 'null') {
      return rawName.toString().trim();
    }
    return 'Driver (${driver['phone'] ?? 'No Phone'})';
  }

  void _selectDriver(Map<String, dynamic> driver) {
    final name = _safeDriverName(driver);
    final phone = (driver['phone'] ?? '').toString().trim();

    setState(() {
      _selectedRiderUid = driver['uid'];
      _driverNameController.text = name;
      _driverPhoneController.text = phone;
      _driverSearchQuery = '';
      _driverSearchController.clear();
    });
  }

  Widget _buildDriverTile(
    Map<String, dynamic> d,
    Map<String, List<Map<String, dynamic>>> driverActiveTrips, {
    VoidCallback? onSelected,
  }) {
    final uid = d['uid'] as String? ?? '';
    final bool isAvailableForScheduled = d['isAvailableForScheduled'] ?? true;
    final activeTrips = driverActiveTrips[uid] ?? [];
    final bool isBusy = activeTrips.isNotEmpty;
    final bool canSelect = !isBusy && isAvailableForScheduled;
    final bool isSelected = _selectedRiderUid == uid;

    final activeTrip = isBusy ? activeTrips.first : null;
    final String routeInfo = isBusy
        ? '${activeTrip!["fromCity"] ?? "City"} ➔ ${activeTrip["toCity"] ?? "City"}'
        : '';

    final dVehicle = (d['vehicleType'] as String?) ?? 'Bike';
    final dModel = (d['vehicleModel'] as String?) ?? 'Vehicle';
    final dPlate = (d['plateNumber'] as String?) ?? '';
    final dPhone = (d['phone'] as String?) ?? 'No Phone';
    final vIcon = _getDriverVehicleIcon(dVehicle);
    final driverName = _safeDriverName(d);

    return InkWell(
      onTap: () {
        if (canSelect) {
          _selectDriver(d);
          onSelected?.call();
        } else if (isBusy) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$driverName is already busy with trip: $routeInfo'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$driverName has paused scheduled trips.'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFEF9C3)
              : (canSelect ? Colors.white : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : (canSelect ? Colors.grey.shade300 : Colors.grey.shade200),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: canSelect ? C.black : Colors.grey.shade300,
              child: Icon(
                vIcon,
                color: canSelect ? const Color(0xFFFFCC00) : Colors.grey.shade600,
                size: 19,
              ),
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
                          driverName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: canSelect ? Colors.black87 : Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('SELECTED', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.phone, size: 11, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Text(
                        dPhone,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 6),
                      Text('•', style: TextStyle(color: Colors.grey.shade400)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$dVehicle: $dModel${dPlate.isNotEmpty ? " ($dPlate)" : ""}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (isBusy) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.do_not_disturb_on, size: 12, color: Colors.red),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'BUSY: $routeInfo',
                              style: TextStyle(color: Colors.red.shade800, fontSize: 10, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (!isAvailableForScheduled) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause_circle_filled, size: 12, color: Colors.orange),
                          SizedBox(width: 4),
                          Text(
                            'PAUSED by Driver',
                            style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (canSelect)
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? const Color(0xFF10B981) : Colors.grey.shade400,
                size: 20,
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Unavailable',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDriverPicker(
    BuildContext context,
    List<Map<String, dynamic>> allApproved,
    Map<String, List<Map<String, dynamic>>> driverActiveTrips,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final carCount = allApproved.where((d) => _matchesVehicle(d['vehicleType'] as String?, 'car')).length;
            final bikeCount = allApproved.where((d) => _matchesVehicle(d['vehicleType'] as String?, 'bike')).length;
            final autoCount = allApproved.where((d) => _matchesVehicle(d['vehicleType'] as String?, 'auto')).length;

            final vehicleFiltered = allApproved.where((d) => _matchesVehicle(d['vehicleType'] as String?, _selectedVehicleFilter)).toList();

            final searched = vehicleFiltered.where((d) {
              if (_driverSearchQuery.isEmpty) return true;
              final rawName = (d['name'] ?? '').toString().toLowerCase();
              final phone = (d['phone'] ?? '').toString().toLowerCase();
              final vType = (d['vehicleType'] ?? '').toString().toLowerCase();
              final vModel = (d['vehicleModel'] ?? '').toString().toLowerCase();
              final plate = (d['plateNumber'] ?? '').toString().toLowerCase();
              return rawName.contains(_driverSearchQuery) ||
                  phone.contains(_driverSearchQuery) ||
                  vType.contains(_driverSearchQuery) ||
                  vModel.contains(_driverSearchQuery) ||
                  plate.contains(_driverSearchQuery);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
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
                            const Text(
                              'Select Approved Driver',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Trip: ${widget.booking["fromCity"]} ➔ ${widget.booking["toCity"]}',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                            ),
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

                  // Search Bar inside picker
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: TextField(
                      controller: _driverSearchController,
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: 'Search by driver name, phone, or vehicle...',
                        hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                        prefixIcon: const Icon(Icons.search, size: 20, color: Colors.black54),
                        suffixIcon: _driverSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _driverSearchController.clear();
                                  setPickerState(() => _driverSearchQuery = '');
                                  setState(() => _driverSearchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onChanged: (val) {
                        setPickerState(() => _driverSearchQuery = val.trim().toLowerCase());
                        setState(() => _driverSearchQuery = val.trim().toLowerCase());
                      },
                    ),
                  ),

                  // Vehicle Type Filter Chips inside picker
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        ChoiceChip(
                          avatar: Icon(Icons.commute, size: 14, color: _selectedVehicleFilter == 'all' ? C.black : Colors.black54),
                          label: Text('All (${allApproved.length})'),
                          selected: _selectedVehicleFilter == 'all',
                          selectedColor: C.yellow,
                          onSelected: (_) {
                            setPickerState(() => _selectedVehicleFilter = 'all');
                            setState(() => _selectedVehicleFilter = 'all');
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          avatar: Icon(Icons.directions_car, size: 14, color: _selectedVehicleFilter == 'car' ? C.black : Colors.black54),
                          label: Text('Cars ($carCount)'),
                          selected: _selectedVehicleFilter == 'car',
                          selectedColor: C.yellow,
                          onSelected: (_) {
                            setPickerState(() => _selectedVehicleFilter = 'car');
                            setState(() => _selectedVehicleFilter = 'car');
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          avatar: Icon(Icons.two_wheeler, size: 14, color: _selectedVehicleFilter == 'bike' ? C.black : Colors.black54),
                          label: Text('Bikes ($bikeCount)'),
                          selected: _selectedVehicleFilter == 'bike',
                          selectedColor: C.yellow,
                          onSelected: (_) {
                            setPickerState(() => _selectedVehicleFilter = 'bike');
                            setState(() => _selectedVehicleFilter = 'bike');
                          },
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          avatar: Icon(Icons.electric_rickshaw, size: 14, color: _selectedVehicleFilter == 'auto' ? C.black : Colors.black54),
                          label: Text('Auto ($autoCount)'),
                          selected: _selectedVehicleFilter == 'auto',
                          selectedColor: C.yellow,
                          onSelected: (_) {
                            setPickerState(() => _selectedVehicleFilter = 'auto');
                            setState(() => _selectedVehicleFilter = 'auto');
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 12),

                  // Driver List
                  Expanded(
                    child: searched.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  _driverSearchQuery.isNotEmpty
                                      ? 'No drivers match "$_driverSearchQuery"'
                                      : 'No approved drivers with ${_selectedVehicleFilter.toUpperCase()}',
                                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: searched.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 4),
                            itemBuilder: (context, idx) {
                              return _buildDriverTile(
                                searched[idx],
                                driverActiveTrips,
                                onSelected: () => Navigator.pop(modalCtx),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalVehicleChip(String label, String key, IconData icon) {
    final isSelected = _selectedVehicleFilter == key;
    return ChoiceChip(
      avatar: Icon(icon, size: 14, color: isSelected ? C.black : Colors.black54),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          color: isSelected ? C.black : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: C.yellow,
      backgroundColor: C.grey,
      onSelected: (_) => setState(() => _selectedVehicleFilter = key),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedRiderUid = widget.booking['riderId'];
    _driverNameController.text = widget.booking['riderName'] ?? '';
    _driverPhoneController.text = widget.booking['riderPhone'] ?? '';
    _fareController.text = '${widget.booking["fare"] ?? 6000}';

    // Auto-detect passenger's requested vehicle type for smart initial selection
    final bookedVehicle = ((widget.booking['vehicleType'] ?? widget.booking['vehicle'] ?? '') as String).toLowerCase();
    if (bookedVehicle.contains('car') || bookedVehicle.contains('sedan') || bookedVehicle.contains('taxi') || bookedVehicle.contains('alto')) {
      _selectedVehicleFilter = 'car';
    } else if (bookedVehicle.contains('bike') || bookedVehicle.contains('scooter') || bookedVehicle.contains('motor')) {
      _selectedVehicleFilter = 'bike';
    } else if (bookedVehicle.contains('auto') || bookedVehicle.contains('rickshaw')) {
      _selectedVehicleFilter = 'auto';
    } else {
      _selectedVehicleFilter = 'all';
    }
  }

  @override
  void dispose() {
    _driverNameController.dispose();
    _driverPhoneController.dispose();
    _fareController.dispose();
    _driverSearchController.dispose();
    super.dispose();
  }

  Future<void> _notifyDriverWhatsApp(String phone, String driverName) async {
    final clean = phone.replaceAll(RegExp(r'[^\d]'), '');
    final msg = 'Hello $driverName! You have been assigned an Intercity Trip on ShanGo.\n\n'
        '• Route: ${widget.booking["fromCity"]} ➔ ${widget.booking["toCity"]}\n'
        '• Date & Time: ${widget.booking["departureDate"] ?? ""} ${widget.booking["departureTime"] ?? ""}\n'
        '• Passenger: ${widget.booking["customerName"] ?? "Passenger"} (${widget.booking["customerPhone"] ?? ""})\n'
        '• Pickup: ${widget.booking["pickupAddress"] ?? ""}\n'
        '• Dropoff: ${widget.booking["dropAddress"] ?? ""}\n'
        '• Confirmed Fare: PKR ${_fareController.text.trim()}\n\n'
        'Please open your ShanGo Driver App under "My Scheduled Trips" to view live pickup location & navigation.';

    final uri = Uri.parse('https://wa.me/$clean?text=${Uri.encodeComponent(msg)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Assign Approved Driver', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 6),
            Text('Link driver to trip: ${widget.booking["fromCity"]} ➔ ${widget.booking["toCity"]}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const Divider(height: 18),

            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _rideService.streamAllIntercityBookings(),
              builder: (context, bookingsSnapshot) {
                final allBookings = bookingsSnapshot.data ?? [];

                // Map driver UID -> List of active scheduled bookings (not completed & not cancelled)
                final Map<String, List<Map<String, dynamic>>> driverActiveTrips = {};
                for (final b in allBookings) {
                  final rId = b['riderId'] as String?;
                  final bId = b['id'] as String?;
                  final status = b['status'] as String?;
                  if (rId != null &&
                      rId.isNotEmpty &&
                      rId != 'admin_assigned' &&
                      bId != widget.bookingId &&
                      status != 'completed' &&
                      status != 'cancelled') {
                    driverActiveTrips.putIfAbsent(rId, () => []).add(b);
                  }
                }

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _rideService.streamUsers(role: 'rider'),
                  builder: (context, snapshot) {
                    final approved = (snapshot.data ?? []).where((r) => r['isApproved'] == true && r['isSuspended'] != true).toList();
                    if (approved.isEmpty) {
                      return const Text('No approved drivers online yet. Enter details manually below.', style: TextStyle(fontSize: 12, color: Colors.black54));
                    }

                    final carCount = approved.where((d) => _matchesVehicle(d['vehicleType'] as String?, 'car')).length;
                    final bikeCount = approved.where((d) => _matchesVehicle(d['vehicleType'] as String?, 'bike')).length;
                    final autoCount = approved.where((d) => _matchesVehicle(d['vehicleType'] as String?, 'auto')).length;

                    final filteredApproved = approved.where((d) => _matchesVehicle(d['vehicleType'] as String?, _selectedVehicleFilter)).toList();

                    // Currently selected driver object
                    Map<String, dynamic>? selectedDriver;
                    if (_selectedRiderUid != null) {
                      final matches = approved.where((d) => d['uid'] == _selectedRiderUid);
                      if (matches.isNotEmpty) {
                        selectedDriver = matches.first;
                      }
                    }

                    // Matching search results for inline quick selection
                    final searchMatches = filteredApproved.where((d) {
                      if (_driverSearchQuery.isEmpty) return true;
                      final rawName = (d['name'] ?? '').toString().toLowerCase();
                      final phone = (d['phone'] ?? '').toString().toLowerCase();
                      final vType = (d['vehicleType'] ?? '').toString().toLowerCase();
                      final vModel = (d['vehicleModel'] ?? '').toString().toLowerCase();
                      final plate = (d['plateNumber'] ?? '').toString().toLowerCase();
                      return rawName.contains(_driverSearchQuery) ||
                          phone.contains(_driverSearchQuery) ||
                          vType.contains(_driverSearchQuery) ||
                          vModel.contains(_driverSearchQuery) ||
                          plate.contains(_driverSearchQuery);
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Vehicle Selection Row
                        Row(
                          children: [
                            const Icon(Icons.tune, size: 16, color: Colors.black54),
                            const SizedBox(width: 6),
                            const Text('Filter By Vehicle Type:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            if (widget.booking['vehicleType'] != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.shade300),
                                ),
                                child: Text(
                                  'Req: ${widget.booking['vehicleType']}',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildModalVehicleChip('All (${approved.length})', 'all', Icons.commute),
                              const SizedBox(width: 6),
                              _buildModalVehicleChip('Cars ($carCount)', 'car', Icons.directions_car),
                              const SizedBox(width: 6),
                              _buildModalVehicleChip('Bikes ($bikeCount)', 'bike', Icons.two_wheeler),
                              const SizedBox(width: 6),
                              _buildModalVehicleChip('Auto ($autoCount)', 'auto', Icons.electric_rickshaw),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 2. Search Section Header & Search Bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Search & Select Driver:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            if (selectedDriver != null)
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 24),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _selectedRiderUid = null;
                                    _driverNameController.clear();
                                    _driverPhoneController.clear();
                                  });
                                },
                                child: const Text('Clear Selection', style: TextStyle(fontSize: 11.5, color: Colors.red)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Search Input
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: TextField(
                            controller: _driverSearchController,
                            decoration: InputDecoration(
                              hintText: 'Search driver by name, phone, or vehicle...',
                              hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                              prefixIcon: const Icon(Icons.search, size: 20, color: Colors.black54),
                              suffixIcon: _driverSearchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18, color: Colors.black54),
                                      onPressed: () {
                                        _driverSearchController.clear();
                                        setState(() => _driverSearchQuery = '');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            onChanged: (val) => setState(() => _driverSearchQuery = val.trim().toLowerCase()),
                          ),
                        ),

                        // Inline search results when actively typing
                        if (_driverSearchQuery.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: searchMatches.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: Text(
                                        'No drivers found matching "$_driverSearchQuery"',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.all(8),
                                    itemCount: searchMatches.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (context, idx) {
                                      final d = searchMatches[idx];
                                      return _buildDriverTile(d, driverActiveTrips);
                                    },
                                  ),
                          ),
                        ],

                        const SizedBox(height: 10),

                        // 3. Modern Driver Dropdown / Selector Card
                        InkWell(
                          onTap: () => _openDriverPicker(context, approved, driverActiveTrips),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: selectedDriver != null ? const Color(0xFFFEF9C3) : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selectedDriver != null ? const Color(0xFFF59E0B) : Colors.grey.shade300,
                                width: selectedDriver != null ? 1.4 : 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: selectedDriver != null ? C.black : Colors.grey.shade100,
                                  child: Icon(
                                    selectedDriver != null
                                        ? _getDriverVehicleIcon(selectedDriver['vehicleType'] as String?)
                                        : Icons.person_search_rounded,
                                    color: selectedDriver != null ? const Color(0xFFFFCC00) : Colors.black54,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: selectedDriver == null
                                      ? Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Choose an Approved Driver (${filteredApproved.length})',
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.black87),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Tap to search or browse driver list',
                                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        )
                                      : Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    _safeDriverName(selectedDriver),
                                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.black87),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFDCFCE7),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: const Color(0xFFBBF7D0)),
                                                  ),
                                                  child: const Text('SELECTED', style: TextStyle(color: Color(0xFF166534), fontSize: 9, fontWeight: FontWeight.w900)),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${selectedDriver['phone'] ?? 'No Phone'} • ${selectedDriver['vehicleType'] ?? 'Bike'}: ${selectedDriver['vehicleModel'] ?? ''}',
                                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: selectedDriver != null ? Colors.amber.shade200 : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        selectedDriver != null ? 'Change' : 'Select',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: selectedDriver != null ? Colors.amber.shade900 : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        size: 18,
                                        color: selectedDriver != null ? Colors.amber.shade900 : Colors.black87,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (_selectedRiderUid != null && driverActiveTrips[_selectedRiderUid]?.isNotEmpty == true)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'This driver is already booked for another scheduled trip. Please choose an available driver.',
                                    style: TextStyle(color: Colors.red.shade800, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 14),
            TextField(
              controller: _driverNameController,
              decoration: InputDecoration(
                labelText: 'Driver Name',
                prefixIcon: const Icon(Icons.person),
                filled: true,
                fillColor: C.grey,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _driverPhoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Driver Phone Number',
                prefixIcon: const Icon(Icons.phone),
                filled: true,
                fillColor: C.grey,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _fareController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Final Confirmed Fare (PKR)',
                prefixIcon: const Icon(Icons.attach_money),
                filled: true,
                fillColor: C.grey,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 18),

            if (_saving)
              const Center(child: CircularProgressIndicator(color: C.yellow))
            else
              Column(
                children: [
                  PrimaryButton(
                    'Confirm Assignment & Link',
                    onTap: () async {
                      if (_driverNameController.text.trim().isEmpty || _driverPhoneController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter driver name and phone number.')));
                        return;
                      }
                      setState(() => _saving = true);
                      final fareVal = int.tryParse(_fareController.text.trim());
                      final driverName = _driverNameController.text.trim();
                      final driverPhone = _driverPhoneController.text.trim();

                      await _rideService.assignDriverToIntercityBooking(
                        bookingId: widget.bookingId,
                        riderId: _selectedRiderUid ?? 'admin_assigned',
                        riderName: driverName,
                        riderPhone: driverPhone,
                        confirmedFare: fareVal,
                      );

                      final finalFare = fareVal ?? ((widget.booking['fare'] is num) ? (widget.booking['fare'] as num).toInt() : 6000);
                      final String routeFrom = widget.booking["fromCity"] ?? "City";
                      final String routeTo = widget.booking["toCity"] ?? "City";
                      final String dateStr = widget.booking["scheduledDate"] ?? widget.booking["departureDate"] ?? "";
                      final String timeStr = widget.booking["scheduledTime"] ?? widget.booking["departureTime"] ?? "";
                      final String? passengerUid = widget.booking["customerId"] ?? widget.booking["userId"];
                      final String? passengerName = widget.booking["customerName"];
                      final String? passengerPhone = widget.booking["customerPhone"];

                      // 1. Notify Driver (if registered app driver UID)
                      if (_selectedRiderUid != null && _selectedRiderUid!.isNotEmpty && _selectedRiderUid != 'admin_assigned') {
                        await NotificationService().notifyDriverTripAssigned(
                          driverUid: _selectedRiderUid!,
                          bookingId: widget.bookingId,
                          fromCity: routeFrom,
                          toCity: routeTo,
                          date: dateStr.isNotEmpty ? dateStr : 'Upcoming Date',
                          time: timeStr.isNotEmpty ? timeStr : 'Scheduled Time',
                          fare: finalFare,
                          commissionPercent: 15.0,
                          customerName: passengerName,
                          customerPhone: passengerPhone,
                        );
                      }

                      // 2. Notify Passenger
                      if (passengerUid != null && passengerUid.isNotEmpty) {
                        await NotificationService().notifyPassengerTripConfirmed(
                          passengerUid: passengerUid,
                          bookingId: widget.bookingId,
                          fromCity: routeFrom,
                          toCity: routeTo,
                          driverName: driverName,
                          driverPhone: driverPhone,
                          fare: finalFare,
                        );
                      }

                      widget.onAssigned();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Trip assigned to $driverName! Notifications sent.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF25D366),
                      side: const BorderSide(color: Color(0xFF25D366), width: 1.2),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('Send Trip Details on WhatsApp', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    onPressed: () {
                      if (_driverPhoneController.text.trim().isNotEmpty) {
                        _notifyDriverWhatsApp(_driverPhoneController.text.trim(), _driverNameController.text.trim());
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter driver phone number first.')));
                      }
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
