import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import 'admin_panel.dart';
import 'intercity_screen.dart';
import 'rider.dart';

class NotificationsScreen extends StatefulWidget {
  final bool isAdminView;
  const NotificationsScreen({super.key, this.isAdminView = false});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notifService = NotificationService();
  final AuthService _authService = AuthService();
  String _activeFilter = 'all'; // 'all', 'unread', 'trips', 'account'

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
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final curUser = FirebaseAuth.instance.currentUser;
    final uid = widget.isAdminView ? 'admin' : curUser?.uid;

    if (uid == null && !widget.isAdminView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const Center(child: Text('Please log in to view notifications.')),
      );
    }

    final stream = widget.isAdminView
        ? _notifService.streamAdminNotifications()
        : _notifService.streamUserNotifications(uid!);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(
          widget.isAdminView ? 'Admin Notifications' : 'Notifications',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded, size: 22),
            tooltip: 'Mark all as read',
            onPressed: () async {
              if (uid != null) {
                await _notifService.markAllAsRead(uid, isAdmin: widget.isAdminView);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All notifications marked as read.')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: C.yellow));
          }

          final allNotifs = snapshot.data ?? [];
          final unreadCount = allNotifs.where((n) => n['isRead'] == false).length;

          final filteredNotifs = allNotifs.where((n) {
            final isRead = n['isRead'] == true;
            final type = (n['type'] as String?) ?? '';

            if (_activeFilter == 'unread') return !isRead;
            if (_activeFilter == 'trips') {
              return type.contains('trip') ||
                  type.contains('price') ||
                  type.contains('intercity');
            }
            if (_activeFilter == 'account') {
              return type.contains('role') ||
                  type.contains('driver') ||
                  type.contains('account');
            }
            return true;
          }).toList();

          return Column(
            children: [
              // Filter Chips Row
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChip('All (${allNotifs.length})', 'all'),
                      const SizedBox(width: 8),
                      _buildChip('Unread ($unreadCount)', 'unread'),
                      const SizedBox(width: 8),
                      _buildChip('Trips & Payouts', 'trips'),
                      const SizedBox(width: 8),
                      _buildChip('Account & Role', 'account'),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),

              // Notification Cards List
              Expanded(
                child: filteredNotifs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.notifications_off_outlined,
                                    size: 48, color: Colors.grey.shade400),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'No Notifications Yet',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Trip assignments, price updates, commission payouts, and account approvals will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredNotifs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return _buildNotificationCard(filteredNotifs[index]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChip(String label, String key) {
    final isSelected = _activeFilter == key;
    return ChoiceChip(
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
      backgroundColor: const Color(0xFFF3F4F6),
      onSelected: (_) => setState(() => _activeFilter = key),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notif) {
    final title = notif['title'] ?? 'Notification';
    final body = notif['body'] ?? '';
    final type = notif['type'] ?? 'general';
    final isRead = notif['isRead'] == true;
    final timestamp = notif['createdAt'] as Timestamp?;
    final timeStr = _formatTimestamp(timestamp);
    final referenceId = notif['referenceId'] as String?;

    IconData iconData = Icons.notifications;
    Color iconColor = C.black;
    Color iconBg = const Color(0xFFF3F4F6);

    if (type == 'trip_assigned') {
      iconData = Icons.calendar_month;
      iconColor = const Color(0xFF166534);
      iconBg = const Color(0xFFDCFCE7);
    } else if (type == 'trip_confirmed') {
      iconData = Icons.check_circle;
      iconColor = const Color(0xFF166534);
      iconBg = const Color(0xFFDCFCE7);
    } else if (type == 'price_offer') {
      iconData = Icons.local_offer;
      iconColor = const Color(0xFFB45309);
      iconBg = const Color(0xFFFEF3C7);
    } else if (type == 'account_approved' || type == 'role_switch') {
      iconData = Icons.verified_user;
      iconColor = const Color(0xFF1E40AF);
      iconBg = const Color(0xFFDBEAFE);
    } else if (type == 'driver_registered' || type == 'role_switch_request') {
      iconData = Icons.badge;
      iconColor = const Color(0xFF6B21A8);
      iconBg = const Color(0xFFF3E8FF);
    } else if (type == 'intercity_booking') {
      iconData = Icons.alt_route;
      iconColor = const Color(0xFF0369A1);
      iconBg = const Color(0xFFE0F2FE);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _handleNotificationTap(notif),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : const Color(0xFFFFFDF5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead ? const Color(0xFFE5E7EB) : C.yellow.withValues(alpha: 0.7),
              width: isRead ? 1 : 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isRead ? 0.02 : 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notification Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(iconData, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.w700 : FontWeight.w900,
                              fontSize: 13.5,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: const BoxDecoration(
                                color: C.yellow, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.grey.shade500),
                        ),
                        if (referenceId != null && referenceId.isNotEmpty)
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _handleNotificationTap(notif),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Tap to view ➔',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                ],
                              ),
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
      ),
    );
  }

  // ==========================================
  // ACTION HANDLER FOR TAPPING NOTIFICATION
  // ==========================================
  Future<void> _handleNotificationTap(Map<String, dynamic> notif) async {
    final id = notif['id'] ?? '';
    final type = notif['type'] ?? '';
    final referenceId = (notif['referenceId'] as String?)?.trim() ?? '';
    final isRead = notif['isRead'] == true;

    if (!isRead && id.isNotEmpty) {
      await _notifService.markAsRead(id);
    }

    if (!mounted) return;

    // 1. Intercity Booking (New booking notification for Admin)
    if (type == 'intercity_booking') {
      if (widget.isAdminView) {
        if (referenceId.isNotEmpty) {
          _showIntercityBookingDetailsModal(referenceId);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminPanelScreen(initialTabIndex: 4),
            ),
          );
        }
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IntercityBookingScreen()),
        );
      }
      return;
    }

    // 2. Role Switch Request (Passenger requesting to be Driver)
    if (type == 'role_switch_request') {
      if (widget.isAdminView) {
        if (referenceId.isNotEmpty) {
          _showRoleSwitchDetailsModal(referenceId);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminPanelScreen(initialTabIndex: 3),
            ),
          );
        }
      }
      return;
    }

    // 3. Driver Registered (New driver pending verification)
    if (type == 'driver_registered') {
      if (widget.isAdminView) {
        if (referenceId.isNotEmpty) {
          _showDriverDetailsModal(referenceId);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminPanelScreen(initialTabIndex: 1),
            ),
          );
        }
      }
      return;
    }

    // 4. Trip Assigned (For Driver)
    if (type == 'trip_assigned') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RiderAssignedIntercityScreen()),
      );
      return;
    }

    // 5. Price Offer or Trip Confirmed (For Passenger)
    if (type == 'price_offer' || type == 'trip_confirmed') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IntercityBookingScreen()),
      );
      return;
    }

    // 6. Fallback based on referenceId if available
    if (referenceId.isNotEmpty && widget.isAdminView) {
      // Check if it's an intercity booking
      final bookingDoc = await FirebaseFirestore.instance
          .collection('intercity_bookings')
          .doc(referenceId)
          .get();
      if (bookingDoc.exists && mounted) {
        _showIntercityBookingDetailsModal(referenceId);
        return;
      }

      // Check if it's a user
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(referenceId)
          .get();
      if (userDoc.exists && mounted) {
        final userData = userDoc.data() ?? {};
        if (userData['switchRequest'] != null) {
          _showRoleSwitchDetailsModal(referenceId);
          return;
        } else {
          _showDriverDetailsModal(referenceId);
          return;
        }
      }
    }

    // 7. General fallback dialog
    _showSimpleNotificationDialog(notif);
  }

  // ==========================================
  // MODAL 1: INTERCITY BOOKING DETAILS & DISPATCH
  // ==========================================
  void _showIntercityBookingDetailsModal(String bookingId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('intercity_bookings')
              .doc(bookingId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: C.yellow));
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text('Trip Request Not Found',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    const Text(
                        'This booking may have been cancelled or completed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: C.black, foregroundColor: C.yellow),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const AdminPanelScreen(initialTabIndex: 4),
                          ),
                        );
                      },
                      child: const Text('Open Intercity Dispatch Tab'),
                    ),
                  ],
                ),
              );
            }

            final data = snapshot.data!.data()!;
            final fromCity = data['fromCity'] ?? 'City';
            final toCity = data['toCity'] ?? 'City';
            final fare = data['fare'] ?? 0;
            final customerName = data['customerName'] ?? 'Passenger';
            final customerPhone = data['customerPhone'] ?? '';
            final pickupAddress = data['pickupAddress'] ?? 'Not specified';
            final dropAddress = data['dropAddress'] ?? 'Not specified';
            final pickupCoords = data['pickupCoordinates'] as Map<String, dynamic>?;
            final dropCoords = data['dropCoordinates'] as Map<String, dynamic>?;
            final departureDate = data['departureDate'] ?? 'On-Demand';
            final departureTime = data['departureTime'] ?? '';
            final vehicleType = data['vehicleType'] ?? 'Standard Car';
            final status = (data['status'] as String?) ?? 'pending';

            final riderName = data['riderName'] as String?;
            final riderPhone = data['riderPhone'] as String?;
            final isDriverAssigned = riderName != null && riderName.isNotEmpty;

            return Column(
              children: [
                // Top Handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                // Modal Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$fromCity ➔ $toCity',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 18),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Date: $departureDate $departureTime • Vehicle: $vehicleType',
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: C.yellow.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: C.yellow),
                        ),
                        child: Text(
                          'PKR $fare',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),

                // Content List
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // Status Banner
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDriverAssigned
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDriverAssigned
                                ? const Color(0xFFBBF7D0)
                                : const Color(0xFFFDE68A),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isDriverAssigned
                                  ? Icons.check_circle_rounded
                                  : Icons.pending_actions_rounded,
                              size: 18,
                              color: isDriverAssigned
                                  ? Colors.green.shade700
                                  : Colors.amber.shade900,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isDriverAssigned
                                    ? 'Driver Assigned: $riderName'
                                    : 'Driver Required • Trip status: $status',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  color: isDriverAssigned
                                      ? Colors.green.shade800
                                      : Colors.amber.shade900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Passenger Info Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 18,
                              child: Icon(Icons.person, color: C.black),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(customerName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5)),
                                  Text(customerPhone,
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.call,
                                  color: Colors.black87, size: 20),
                              tooltip: 'Call Passenger',
                              onPressed: () => _makeCall(customerPhone),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chat,
                                  color: Color(0xFF25D366), size: 20),
                              tooltip: 'WhatsApp Passenger',
                              onPressed: () => _openWhatsApp(
                                customerPhone,
                                'Hello $customerName, ShanGo Admin regarding your trip request from $fromCity to $toCity.',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Route Addresses
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.my_location,
                                    size: 16, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Pickup Location:',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: Colors.grey)),
                                      Text(pickupAddress,
                                          style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                if (pickupCoords != null)
                                  InkWell(
                                    onTap: () => _openMaps(
                                        pickupCoords['latitude'],
                                        pickupCoords['longitude']),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Map 🗺️',
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue)),
                                    ),
                                  ),
                              ],
                            ),
                            const Divider(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on,
                                    size: 16, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Drop-off Location:',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: Colors.grey)),
                                      Text(dropAddress,
                                          style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                if (dropCoords != null)
                                  InkWell(
                                    onTap: () => _openMaps(
                                        dropCoords['latitude'],
                                        dropCoords['longitude']),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Map 🗺️',
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue)),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Driver Assignment Card
                      if (isDriverAssigned) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.two_wheeler,
                                      size: 18, color: Color(0xFF166534)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Assigned Driver: $riderName',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: Color(0xFF166534)),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.call,
                                        size: 18, color: Colors.black87),
                                    onPressed: () => _makeCall(riderPhone),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chat,
                                        size: 18, color: Color(0xFF25D366)),
                                    onPressed: () => _openWhatsApp(
                                      riderPhone,
                                      'Hello $riderName, ShanGo Admin regarding trip $fromCity ➔ $toCity for $customerName.',
                                    ),
                                  ),
                                ],
                              ),
                              if (riderPhone != null && riderPhone.isNotEmpty)
                                Text('Phone: $riderPhone',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF15803D))),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Bottom Primary Buttons
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: C.black,
                            foregroundColor: C.yellow,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(isDriverAssigned
                              ? Icons.swap_horiz
                              : Icons.person_add_alt_1),
                          label: Text(
                            isDriverAssigned
                                ? 'Re-assign Driver'
                                : 'Assign Approved Driver Now',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(24))),
                              builder: (_) => AssignDriverModal(
                                bookingId: bookingId,
                                booking: data,
                                onAssigned: () {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Driver assigned and linked!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const AdminPanelScreen(initialTabIndex: 4),
                              ),
                            );
                          },
                          child: const Text('Open in Intercity Dispatch Console'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ==========================================
  // MODAL 2: ROLE SWITCH REQUEST DETAILS & APPROVAL
  // ==========================================
  void _showRoleSwitchDetailsModal(String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: C.yellow));
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text('User Account Not Found',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: C.black, foregroundColor: C.yellow),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const AdminPanelScreen(initialTabIndex: 3),
                          ),
                        );
                      },
                      child: const Text('Open Account Switches Tab'),
                    ),
                  ],
                ),
              );
            }

            final user = snapshot.data!.data()!;
            final name = user['name'] ?? 'User';
            final phone = user['phone'] ?? '';
            final email = user['email'] ?? '';
            final currentRole = user['role'] ?? 'customer';
            final req = user['switchRequest'] as Map<String, dynamic>?;

            final requestedRole = req?['requestedRole'] ?? 'rider';
            final switchStatus = req?['status'] ?? 'pending';
            final vehicleType = req?['vehicleType'] ?? user['vehicleType'] ?? 'Bike';
            final vehicleModel = req?['vehicleModel'] ?? user['vehicleModel'] ?? '';
            final plateNumber = req?['plateNumber'] ?? user['plateNumber'] ?? '';
            final reason = req?['reason'] ?? '';

            final isPending = switchStatus == 'pending';

            return Column(
              children: [
                // Top Handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                // Modal Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Account Switch Application',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 17),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Applicant: $name',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPending
                              ? Colors.amber.shade100
                              : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          switchStatus.toString().toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: isPending
                                ? Colors.amber.shade900
                                : Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),

                // Content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // User Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 18,
                              child: Icon(Icons.person, color: C.black),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5)),
                                  Text(phone.isNotEmpty ? phone : email,
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.call,
                                  color: Colors.black87, size: 20),
                              tooltip: 'Call Applicant',
                              onPressed: () => _makeCall(phone),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chat,
                                  color: Color(0xFF25D366), size: 20),
                              tooltip: 'WhatsApp Applicant',
                              onPressed: () => _openWhatsApp(
                                phone,
                                'Hello $name, ShanGo Admin reviewing your request to switch to $requestedRole mode.',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Transition Visual Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text('Current Role',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  currentRole == 'rider'
                                      ? 'Driver'
                                      : 'Passenger',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800, fontSize: 14),
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_forward_rounded,
                                color: C.yellow, size: 24),
                            Column(
                              children: [
                                const Text('Requested Role',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  requestedRole == 'rider'
                                      ? 'Driver / Rider'
                                      : 'Passenger',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: Colors.blue.shade800),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Vehicle info if applying to Driver
                      if (requestedRole == 'rider') ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Vehicle Application Information:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800, fontSize: 12.5)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.electric_moped_outlined,
                                      size: 16, color: Colors.black54),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Type: $vehicleType ${vehicleModel.isNotEmpty ? "($vehicleModel)" : ""}',
                                      style: const TextStyle(
                                          fontSize: 12.5, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.badge_outlined,
                                      size: 16, color: Colors.black54),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Number Plate: ${plateNumber.isNotEmpty ? plateNumber : "Pending"}',
                                      style: const TextStyle(
                                          fontSize: 12.5, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      if (reason.isNotEmpty) ...[
                        Text(
                          'Note from User: "$reason"',
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                              color: Colors.grey.shade700),
                        ),
                      ],
                    ],
                  ),
                ),

                // Approval / Reject Buttons
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      if (isPending) ...[
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Approve Switch',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    Navigator.pop(ctx);
                                    await _authService.approveAccountSwitchRequest(uid);
                                    await NotificationService()
                                        .notifyUserSwitchApproved(
                                      uid: uid,
                                      newRole: requestedRole,
                                    );
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '✅ Approved switch for $name to ${requestedRole == "rider" ? "Driver" : "Passenger"}!'),
                                        backgroundColor: Colors.green.shade800,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    side: BorderSide(color: Colors.red.shade300),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.cancel_outlined),
                                  label: const Text('Decline'),
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    final reasonCtrl = TextEditingController();
                                    final shouldReject = await showDialog<bool>(
                                      context: context,
                                      builder: (dCtx) => AlertDialog(
                                        title: Text('Decline Switch for $name'),
                                        content: TextField(
                                          controller: reasonCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Reason (Optional)',
                                            hintText: 'e.g. Invalid vehicle plate or documents',
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dCtx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white),
                                            onPressed: () => Navigator.pop(dCtx, true),
                                            child: const Text('Decline'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (shouldReject == true) {
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }
                                      await _authService.rejectAccountSwitchRequest(
                                        uid,
                                        reason: reasonCtrl.text.trim(),
                                      );
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'Account switch declined for $name.'),
                                          backgroundColor: Colors.red.shade800,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const AdminPanelScreen(initialTabIndex: 3),
                              ),
                            );
                          },
                          child: const Text('Open in Account Switches Console'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ==========================================
  // MODAL 3: DRIVER REGISTRATION & APPROVAL
  // ==========================================
  void _showDriverDetailsModal(String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: C.yellow));
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text('Driver Not Found',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: C.black, foregroundColor: C.yellow),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const AdminPanelScreen(initialTabIndex: 1),
                          ),
                        );
                      },
                      child: const Text('Open Riders Tab'),
                    ),
                  ],
                ),
              );
            }

            final user = snapshot.data!.data()!;
            final name = user['name'] ?? 'Driver';
            final phone = user['phone'] ?? '';
            final email = user['email'] ?? '';
            final isApproved = user['isApproved'] == true;
            final isSuspended = user['isSuspended'] == true;
            final vehicleType = user['vehicleType'] ?? 'Bike';
            final vehicleModel = user['vehicleModel'] ?? '';
            final plateNumber = user['plateNumber'] ?? '';

            return Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Driver Profile & Approval',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 17),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text('Driver: $name',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSuspended
                              ? Colors.red.shade100
                              : (isApproved
                                  ? Colors.green.shade100
                                  : Colors.amber.shade100),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isSuspended
                              ? 'SUSPENDED'
                              : (isApproved ? 'APPROVED' : 'PENDING APPROVAL'),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: isSuspended
                                ? Colors.red.shade900
                                : (isApproved
                                    ? Colors.green.shade900
                                    : Colors.amber.shade900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 18,
                              child: Icon(Icons.two_wheeler, color: C.black),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5)),
                                  Text(phone.isNotEmpty ? phone : email,
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.call,
                                  color: Colors.black87, size: 20),
                              onPressed: () => _makeCall(phone),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chat,
                                  color: Color(0xFF25D366), size: 20),
                              onPressed: () => _openWhatsApp(
                                phone,
                                'Hello $name, ShanGo Admin regarding your Driver account registration.',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Vehicle Information:',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 12.5)),
                            const SizedBox(height: 6),
                            Text('Category: $vehicleType',
                                style: const TextStyle(fontSize: 12)),
                            if (vehicleModel.isNotEmpty)
                              Text('Model: $vehicleModel',
                                  style: const TextStyle(fontSize: 12)),
                            if (plateNumber.isNotEmpty)
                              Text('Plate: $plateNumber',
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      if (!isApproved) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Approve Driver Now',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(ctx);
                              await _authService.setRiderApprovalStatus(uid,
                                  isApproved: true);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('✅ Driver $name approved!'),
                                  backgroundColor: Colors.green.shade800,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const AdminPanelScreen(initialTabIndex: 1),
                              ),
                            );
                          },
                          child: const Text('Open in Riders & Approval Console'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ==========================================
  // MODAL 4: GENERIC SIMPLE NOTIFICATION DIALOG
  // ==========================================
  void _showSimpleNotificationDialog(Map<String, dynamic> notif) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.notifications_active, color: C.yellow),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notif['title'] ?? 'Notification',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          notif['body'] ?? '',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'Just now';
    final date = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
