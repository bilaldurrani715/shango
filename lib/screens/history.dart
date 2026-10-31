import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/account_switch_dialog.dart';
import 'auth.dart';
import 'shell.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride history')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.history_toggle_off, size: 70, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No Ride History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Please sign in to view your past and active rides.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              PrimaryButton('Login / Sign Up', onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              }),
            ],
          ),
        ),
      );
    }

    final rideService = RideService();

    return Scaffold(
      appBar: AppBar(title: const Text('Ride history')),
      body: StreamBuilder<List<RideModel>>(
        stream: rideService.streamUserRides(uid: user.uid, isRider: isRider.value),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: C.yellow));
          }

          final rides = snapshot.data ?? [];
          if (rides.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'No Rides Yet',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isRider.value
                          ? 'Your accepted and completed trips will appear here.'
                          : 'Your booked rides and trip receipts will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final r = rides[i];
              final isCompleted = r.status == 'completed';
              final isCancelled = r.status == 'cancelled';
              final statusColor = isCompleted
                  ? Colors.green.shade700
                  : isCancelled
                      ? Colors.red.shade700
                      : C.black;
              final statusBg = isCompleted
                  ? Colors.green.shade50
                  : isCancelled
                      ? Colors.red.shade50
                      : C.yellow;

              final dateStr =
                  '${r.createdAt.day}/${r.createdAt.month}/${r.createdAt.year}  ${r.createdAt.hour.toString().padLeft(2, '0')}:${r.createdAt.minute.toString().padLeft(2, '0')}';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: C.grey,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(dateStr, style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            r.status.toUpperCase(),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.circle, color: Colors.green, size: 10),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r.pickupAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.square, color: C.yellow, size: 10),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r.dropAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Distance: ${LocationService.formatDistance(r.distanceKm * 1000)}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          'PKR ${r.estimatedFare.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.black),
                        ),
                      ],
                    ),
                    if (r.rating != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              r.rating!.toStringAsFixed(1),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            if (r.reviewMessage != null && r.reviewMessage!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '"${r.reviewMessage}"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade800),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _vehicleModelController;
  late TextEditingController _plateController;
  String _vehicleType = 'Bike';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController = TextEditingController(text: user?.displayName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
    _vehicleModelController = TextEditingController(text: '');
    _plateController = TextEditingController(text: '');

    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          if (mounted) {
            setState(() {
              if (data['name'] != null && data['name'].toString().isNotEmpty) {
                _nameController.text = data['name'];
              }
              if (data['phone'] != null && data['phone'].toString().isNotEmpty) {
                _phoneController.text = data['phone'];
              }
              if (data['vehicleModel'] != null) {
                _vehicleModelController.text = data['vehicleModel'];
              }
              if (data['plateNumber'] != null) {
                _plateController.text = data['plateNumber'];
              }
              if (data['vehicleType'] != null) {
                _vehicleType = data['vehicleType'];
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading profile: $e');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _vehicleModelController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.yellow))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 46,
                        backgroundColor: user != null ? C.yellow : Colors.grey.shade300,
                        child: Icon(
                          user != null ? Icons.person : Icons.person_outline,
                          size: 52,
                          color: C.black,
                        ),
                      ),
                      if (user == null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                          child: const Text('Guest', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (user == null) ...[
                  const Center(
                    child: Text('Guest Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You are browsing as a guest. Sign in to request rides with live driver tracking, save addresses, and earn as a rider.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton('Login / Create Account', onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                  }),
                ] else ...[
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone)),
                  ),
                  const SizedBox(height: 20),

                  // Account Type & Role Switch Box
                  StreamBuilder<Map<String, dynamic>?>(
                    stream: _authService.streamUserProfile(user.uid),
                    builder: (context, snapshot) {
                      final data = snapshot.data ?? {};
                      final role = (data['role'] as String?) ?? 'customer';
                      final isRiderRole = role == 'rider';
                      final switchReq = data['switchRequest'] as Map<String, dynamic>?;
                      final isPending = switchReq != null && switchReq['status'] == 'pending';
                      final targetRole = switchReq?['requestedRole'] as String?;

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isRiderRole ? C.black : C.yellow,
                                  child: Icon(
                                    isRiderRole ? Icons.two_wheeler : Icons.person,
                                    size: 20,
                                    color: isRiderRole ? C.yellow : C.black,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Account Role: ${isRiderRole ? "Driver / Rider" : "Passenger"}',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                      ),
                                      const Text(
                                        'Single account type per Gmail address',
                                        style: TextStyle(fontSize: 11, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (isPending) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF9E6),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.amber.shade400),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.hourglass_top, color: Color(0xFFB78103), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Switch to ${targetRole == 'rider' ? 'Driver' : 'Passenger'} Pending Admin Approval',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF7A5500)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: C.black,
                                side: const BorderSide(color: C.black, width: 1.2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                minimumSize: const Size(double.infinity, 42),
                              ),
                              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                              label: Text(
                                isPending ? 'View / Manage Switch Request' : 'Switch Account Type (Admin Approval)',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                              onPressed: () => AccountSwitchDialog.show(context, uid: user.uid),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  if (isRider.value) ...[
                    const SizedBox(height: 24),
                    const Text('Vehicle info', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _vehicleType,
                      decoration: const InputDecoration(labelText: 'Vehicle type', prefixIcon: Icon(Icons.two_wheeler)),
                      items: const [
                        DropdownMenuItem(value: 'Bike', child: Text('Motorbike / Scooter')),
                        DropdownMenuItem(value: 'Auto', child: Text('Rickshaw / Auto')),
                        DropdownMenuItem(value: 'Car', child: Text('Car / Taxi')),
                      ],
                      onChanged: (v) => setState(() => _vehicleType = v ?? 'Bike'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _vehicleModelController,
                      decoration: const InputDecoration(labelText: 'Model', prefixIcon: Icon(Icons.electric_moped)),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _plateController,
                      decoration: const InputDecoration(labelText: 'Plate number', prefixIcon: Icon(Icons.badge)),
                    ),
                  ],
                  const SizedBox(height: 28),
                  PrimaryButton('Save Profile', onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                        'name': _nameController.text.trim(),
                        'phone': _phoneController.text.trim(),
                        if (isRider.value) ...{
                          'vehicleType': _vehicleType,
                          'vehicleModel': _vehicleModelController.text.trim(),
                          'plateNumber': _plateController.text.trim(),
                        },
                      }, SetOptions(merge: true));
                      if (mounted) {
                        messenger.showSnackBar(const SnackBar(content: Text('Profile saved successfully!')));
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red));
                      }
                    }
                  }),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    'Logout',
                    bg: C.black,
                    fg: C.white,
                    onTap: () async {
                      final nav = Navigator.of(context);
                      await _authService.signOut();
                      if (mounted) {
                        nav.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const HomeShell()),
                          (r) => false,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 20),
                    label: const Text(
                      'Delete Account & Data',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    onPressed: () => _showDeleteAccountDialog(context),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to permanently delete your ShanGo account?\n\n'
          'This action cannot be undone. All your profile information, ride records, and personal data will be completely deleted.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _executeAccountDeletion();
    }
  }

  Future<void> _executeAccountDeletion() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Show loading progress modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.red),
                SizedBox(width: 18),
                Text('Deleting account & data...', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _authService.deleteAccount();
      if (mounted) {
        nav.pop(); // Dismiss loading dialog
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Your account and all associated data have been permanently deleted.'),
            backgroundColor: Colors.black87,
          ),
        );
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeShell()),
          (r) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        nav.pop(); // Dismiss loading dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Account Deletion Notice', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    }
  }
}
