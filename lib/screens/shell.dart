import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/account_switch_dialog.dart';
import 'admin_fleet_map_screen.dart';
import 'auth.dart';
import 'customer.dart';
import 'history.dart';
import 'intercity_screen.dart';
import 'notifications_screen.dart';
import 'rider.dart';
import 'rider_dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<User?>? _authSub;
  StreamSubscription<Map<String, dynamic>?>? _userDocSub;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _setupUserListeners();
  }

  void _setupUserListeners() {
    // 1. Check existing logged-in user immediately on launch
    final initialUser = FirebaseAuth.instance.currentUser;
    if (initialUser != null) {
      final initialIsAdmin = initialUser.email == 'shango1132@gmail.com' || initialUser.email == 'shango@gmail.com';
      if (initialIsAdmin) {
        _isAdmin = true;
      }
      _notificationService.saveUserFcmToken(initialUser.uid);
      _notificationService.startLiveNotificationListener(initialUser.uid, isAdmin: initialIsAdmin);
      _authService.getUserData(initialUser.uid).then((data) {
        if (mounted && data != null) {
          final role = (data['role'] as String?) ?? 'customer';
          final bool isAdmin = role == 'admin' || data['isAdmin'] == true || initialUser.email == 'shango1132@gmail.com' || initialUser.email == 'shango@gmail.com';
          isRider.value = (role == 'rider');
          setState(() {
            _isAdmin = isAdmin;
          });
          _notificationService.startLiveNotificationListener(initialUser.uid, isAdmin: isAdmin);
        }
      });
    }

    // 2. Stream auth state changes
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _userDocSub?.cancel();
      if (user != null) {
        _notificationService.saveUserFcmToken(user.uid);
        _userDocSub = _authService.streamUserProfile(user.uid).listen((data) {
          if (mounted && data != null) {
            final role = (data['role'] as String?) ?? 'customer';
            final bool isAdmin = role == 'admin' || data['isAdmin'] == true || user.email == 'shango1132@gmail.com' || user.email == 'shango@gmail.com';
            isRider.value = (role == 'rider');
            setState(() {
              _isAdmin = isAdmin;
            });
            _notificationService.startLiveNotificationListener(user.uid, isAdmin: isAdmin);
          }
        });
      } else {
        _notificationService.stopLiveNotificationListener();
        if (mounted) {
          isRider.value = false;
          setState(() {
            _isAdmin = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userDocSub?.cancel();
    _notificationService.stopLiveNotificationListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return ValueListenableBuilder<bool>(
      valueListenable: isRider,
      builder: (context, rider, _) => Scaffold(
        appBar: AppBar(
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Logo(size: 28),
              if (rider) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: C.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'DRIVER',
                    style: TextStyle(
                      color: C.yellow,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          centerTitle: true,
          actions: [
            // 0. Admin Quick Action in AppBar
            if (_isAdmin)
              IconButton(
                icon: const Icon(Icons.radar_rounded, color: C.black, size: 24),
                tooltip: 'Fleet Radar Map',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminFleetMapScreen()),
                ),
              ),

            // 1. Notification Bell with Real-Time Badge
            if (user != null)
              StreamBuilder<int>(
                stream: _notificationService.streamUnreadCount(user.uid),
                builder: (context, notifSnap) {
                  final unread = notifSnap.data ?? 0;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined, color: C.black, size: 24),
                        tooltip: 'Notifications',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                        ),
                      ),
                      if (unread > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              unread > 9 ? '9+' : '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),

            // 2. Primary Navigation Button
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: rider
                  ? TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: C.black,
                        foregroundColor: C.yellow,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        if (user != null) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => RiderAssignedIntercityScreen(uid: user.uid)));
                        }
                      },
                      icon: const Icon(Icons.schedule_send, size: 16, color: C.yellow),
                      label: const Text(
                        'My Trips',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    )
                  : TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: C.black,
                        foregroundColor: C.yellow,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const IntercityBookingScreen()));
                      },
                      icon: const Icon(Icons.airport_shuttle, size: 16, color: C.yellow),
                      label: const Text(
                        'City-to-City',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              children: [
                // User Profile Header in Drawer
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: _isAdmin ? Colors.black87 : (rider ? C.black : C.yellow),
                        child: Icon(
                          _isAdmin ? Icons.admin_panel_settings : (rider ? Icons.two_wheeler : Icons.person),
                          color: _isAdmin ? C.yellow : (rider ? C.yellow : C.black),
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? (user != null ? 'ShanGo User' : 'Guest Account'),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.phoneNumber ?? user?.email ?? 'Tap profile to sign in',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _isAdmin ? C.black : (rider ? C.black : C.yellow.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _isAdmin ? 'Admin Mode' : (rider ? 'Driver Mode' : 'Customer Mode'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: _isAdmin ? C.yellow : (rider ? C.yellow : Colors.black87),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Dedicated Admin Console Tile
                if (_isAdmin) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: C.black, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.admin_panel_settings, color: C.yellow, size: 20),
                    ),
                    title: const Text('Admin Console', style: TextStyle(fontWeight: FontWeight.w900, color: C.black)),
                    subtitle: const Text('Manage rides, pricing, users & dispatch', style: TextStyle(fontSize: 11, color: Colors.black54)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(6)),
                      child: const Text('ADMIN', style: TextStyle(color: C.black, fontSize: 10, fontWeight: FontWeight.w900)),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminFleetMapScreen()));
                    },
                  ),
                  const Divider(height: 1),
                ],

                // Intercity Option: Passenger gets "City to City (Booking)", Driver gets "My Scheduled Trips"
                if (!rider)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.airport_shuttle, color: C.black, size: 20),
                    ),
                    title: const Text('City to City (On-Demand)', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Bannu ⇄ Peshawar ⇄ Islamabad', style: TextStyle(fontSize: 11, color: Colors.black54)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(6)),
                      child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const IntercityBookingScreen()));
                    },
                  )
                else ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: C.black, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.dashboard_rounded, color: C.yellow, size: 20),
                    ),
                    title: const Text('Driver Dashboard & Earnings', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Total earnings, ShanGo commission & rides', style: TextStyle(fontSize: 11, color: Colors.black54)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                    onTap: () {
                      Navigator.pop(context);
                      if (user != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => RiderDashboardScreen(riderId: user.uid)));
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: C.black, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.schedule_send, color: C.yellow, size: 20),
                    ),
                    title: const Text('My Scheduled Trips', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('View assigned intercity rides & passenger contacts', style: TextStyle(fontSize: 11, color: Colors.black54)),
                    onTap: () {
                      Navigator.pop(context);
                      if (user != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => RiderAssignedIntercityScreen(uid: user.uid)));
                      }
                    },
                  ),
                ],

                const Divider(height: 1),

                // Navigation Items
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Ride history', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
                  },
                ),
                ListTile(
                  leading: Stack(
                    children: [
                      const Icon(Icons.notifications_outlined),
                      if (user != null)
                        StreamBuilder<int>(
                          stream: _notificationService.streamUnreadCount(user.uid),
                          builder: (context, snap) {
                            final count = snap.data ?? 0;
                            if (count == 0) return const SizedBox.shrink();
                            return Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Profile & Settings', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Data, GPS tracking & safety terms', style: TextStyle(fontSize: 11, color: Colors.black54)),
                  onTap: () {
                    Navigator.pop(context);
                    _showPrivacyPolicyModal(context);
                  },
                ),

                const Divider(height: 1),

                // Role Switcher Tile (Requires Admin Approval)
                if (user != null)
                  StreamBuilder<Map<String, dynamic>?>(
                    stream: _authService.streamUserProfile(user.uid),
                    builder: (context, snapshot) {
                      final data = snapshot.data ?? {};
                      final switchReq = data['switchRequest'] as Map<String, dynamic>?;
                      final isPending = switchReq != null && switchReq['status'] == 'pending';
                      final requestedRole = switchReq?['requestedRole'] as String?;

                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isPending ? Colors.amber.shade100 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            rider ? Icons.person : Icons.two_wheeler,
                            color: isPending ? Colors.amber.shade900 : C.black,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          rider ? 'Switch to Passenger Mode' : 'Switch to Driver Mode',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          isPending
                              ? '⏳ Switch to ${requestedRole == 'rider' ? 'Driver' : 'Passenger'} Pending Admin Approval'
                              : 'Requires ShanGo Admin verification',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isPending ? Colors.amber.shade900 : Colors.grey.shade600,
                            fontWeight: isPending ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: isPending
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Pending', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                              )
                            : const Icon(Icons.swap_horiz_rounded, color: C.black),
                        onTap: () {
                          Navigator.pop(context);
                          AccountSwitchDialog.show(context, uid: user.uid);
                        },
                      );
                    },
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.swap_horiz, color: C.black),
                    title: const Text('Switch Account Type', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Sign in to manage Driver or Passenger mode', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                    },
                  ),

                const Spacer(),

                // Sign In / Logout Button at bottom of drawer
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: user == null
                      ? PrimaryButton(
                          'Login / Sign Up',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                          },
                        )
                      : ListTile(
                          leading: const Icon(Icons.logout, color: Colors.red),
                          title: const Text('Log out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          onTap: () async {
                            Navigator.pop(context);
                            await _authService.signOut();
                            isRider.value = false;
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        body: IndexedStack(
          index: rider ? 1 : 0,
          children: const [
            CustomerHome(),
            RiderHome(),
          ],
        ),
      ),
    );
  }



  void _showPrivacyPolicyModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
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
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.privacy_tip, color: C.black),
                      SizedBox(width: 8),
                      Text(
                        'Privacy Policy',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Text(
                'ShanGo (by Jabiru Labs) • Last Updated: October 2026',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const Divider(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    const _PolicySection(
                      title: '1. Introduction',
                      body:
                          'Welcome to ShanGo. We value your privacy and are committed to protecting your personal information. This Privacy Policy explains how our app collects, uses, shares, and protects your information when you use our on-demand ride booking, driver partner, and intercity transport services.',
                    ),
                    _PolicySection(
                      title: '2. Information We Collect',
                      body:
                          '• Account & Profile Information: When registering or completing your profile, we collect your name, email address, contact phone number, and selected role (Passenger or Driver).\n• Driver & Vehicle Information: For riders, we collect vehicle type, vehicle model, and vehicle registration plate number.\n• Location Data (GPS): We collect real-time precise location data to enable pickup matching, calculate trip distance and fares, and allow live tracking on the map during active trips.',
                    ),
                    _PolicySection(
                      title: '3. How We Use Your Location Data',
                      body:
                          '• Passengers: Your GPS coordinates are used to set pickup locations and route destinations.\n• Drivers: When online or on an active trip, your location is broadcast to nearby passengers and displayed on the interactive map for trip safety and estimated arrival times.\n• Background Tracking: Location is only accessed while the driver is active/online in Driver Mode.',
                    ),
                    _PolicySection(
                      title: '4. Driver-Passenger Communication',
                      body:
                          'To ensure smooth trip coordination, phone numbers are shared between the matched passenger and driver once a ride is accepted. You can make direct calls via your device\'s standard phone dialer.',
                    ),
                    _PolicySection(
                      title: '5. Rating & Reviews',
                      body:
                          'Passengers can submit star ratings and feedback reviews for drivers upon ride completion. Reviews are displayed to future passengers to ensure high service quality and community trust.',
                    ),
                    _PolicySection(
                      title: '6. Account Security & Verification',
                      body:
                          'All driver registrations are subject to verification and approval by ShanGo administrators. Admin reserves the right to suspend or block accounts that violate community safety standards or Terms of Service.',
                    ),
                    _PolicySection(
                      title: '7. Data Protection & Security',
                      body:
                          'Your data is securely stored in Google Firebase Firestore with industry-standard encryption protocols. We do not sell your personal information to third parties.',
                    ),
                    StreamBuilder<Map<String, dynamic>>(
                      stream: RideService().streamAdminContactInfo(),
                      builder: (context, snap) {
                        final contact = snap.data ?? RideService.defaultAdminContact;
                        final email = contact['adminEmail'] ?? 'info@jabirulabs.com';
                        final helpline = contact['adminPhone'] ?? '+92 345 1234567';
                        final address = contact['supportAddress'] ?? 'Bannu / Peshawar, Khyber Pakhtunkhwa, Pakistan';
                        return _PolicySection(
                          title: '8. Contact Us & Helpline',
                          body:
                              'If you have any questions or requests regarding your data, rides, or account, please contact us at:\n• Email: $email\n• Helpline: $helpline\n• Address: $address',
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              PrimaryButton('I Understand & Accept', onTap: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;

  const _PolicySection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: C.black)),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.45)),
        ],
      ),
    );
  }
}
