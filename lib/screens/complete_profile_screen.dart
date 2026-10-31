import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell.dart';

class CompleteProfileScreen extends StatefulWidget {
  final String uid;
  final String? initialName;
  final String? initialEmail;
  final String? initialPhone;
  final bool asModal;

  const CompleteProfileScreen({
    super.key,
    required this.uid,
    this.initialName,
    this.initialEmail,
    this.initialPhone,
    this.asModal = false,
  });

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  final TextEditingController _vehicleModelController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();

  bool _isRider = false;
  bool _hasExistingRole = false;
  String _vehicleType = 'Bike';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    final data = await _authService.getUserData(widget.uid);
    if (data != null && mounted) {
      setState(() {
        if (_nameController.text.isEmpty && data['name'] != null) {
          _nameController.text = data['name'];
        }
        if (_phoneController.text.isEmpty && data['phone'] != null) {
          _phoneController.text = data['phone'];
        }
        if (data['role'] != null && (data['role'] as String).isNotEmpty) {
          _hasExistingRole = true;
          _isRider = (data['role'] == 'rider');
        }
        if (data['vehicleType'] != null) {
          _vehicleType = data['vehicleType'];
        }
        if (data['vehicleModel'] != null) {
          _vehicleModelController.text = data['vehicleModel'];
        }
        if (data['plateNumber'] != null) {
          _plateController.text = data['plateNumber'];
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehicleModelController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final role = _isRider ? 'rider' : 'customer';
      await _authService.updateUserProfile(
        uid: widget.uid,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: role,
        vehicleType: _isRider ? _vehicleType : null,
        vehicleModel: _isRider ? _vehicleModelController.text.trim() : null,
        plateNumber: _isRider ? _plateController.text.trim() : null,
      );

      // Update Firebase Auth Display Name if empty
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && (user.displayName == null || user.displayName!.isEmpty)) {
        await user.updateDisplayName(_nameController.text.trim());
      }

      if (_isRider) {
        await NotificationService().notifyAdminNewDriverRegistered(
          uid: widget.uid,
          driverName: _nameController.text.trim(),
          driverPhone: _phoneController.text.trim(),
          vehicleModel: _vehicleModelController.text.trim().isNotEmpty ? _vehicleModelController.text.trim() : _vehicleType,
        );
      }

      if (mounted) {
        isRider.value = _isRider;
        if (widget.asModal) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeShell()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Complete Profile', style: TextStyle(fontWeight: FontWeight.w800)),
        automaticallyImplyLeading: widget.asModal,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: C.yellow,
                        child: Icon(
                          _isRider ? Icons.two_wheeler : Icons.person,
                          size: 38,
                          color: C.black,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'One Last Step!',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.black),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Please choose your account type and add your phone number.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Account Type Selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Account Type',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.black),
                    ),
                    if (_hasExistingRole)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                        child: const Row(
                          children: [
                            Icon(Icons.lock, size: 12, color: Colors.black54),
                            SizedBox(width: 4),
                            Text('Registered Role', style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_hasExistingRole)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: _isRider ? C.black : C.yellow,
                          child: Icon(_isRider ? Icons.two_wheeler : Icons.person, size: 18, color: _isRider ? C.yellow : C.black),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isRider ? 'Driver / Rider Account' : 'Passenger Account',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              Text(
                                'Role is bound to this Gmail. Role changes require Admin approval in Settings.',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    height: 50,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFEFEF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isRider = false),
                            child: Container(
                              decoration: BoxDecoration(
                                color: !_isRider ? C.yellow : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person, size: 18, color: !_isRider ? C.black : Colors.black54),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Passenger',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: !_isRider ? C.black : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isRider = true),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _isRider ? C.yellow : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.two_wheeler, size: 18, color: _isRider ? C.black : Colors.black54),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Driver / Rider',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: _isRider ? C.black : Colors.black54,
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
                const SizedBox(height: 20),

                // Full Name
                TextFormField(
                  controller: _nameController,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'e.g. Bilal Durrani',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),

                // Phone Number
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    final clean = (v ?? '').trim();
                    if (clean.isEmpty) return 'Phone number is required';
                    if (clean.length < 10) return 'Enter a valid phone number (03XXXXXXXXX)';
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '03XXXXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),

                // If Rider, require vehicle details
                if (_isRider) ...[
                  const SizedBox(height: 22),
                  const Text(
                    'Vehicle Details',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: C.black),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _vehicleType,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle Type',
                      prefixIcon: Icon(Icons.two_wheeler),
                    ),
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
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter vehicle model (e.g. Honda CD70)' : null,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle Model',
                      hintText: 'e.g. Honda CD70 / Toyota Corolla',
                      prefixIcon: Icon(Icons.electric_moped_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _plateController,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter number plate (e.g. BNU-1234)' : null,
                    decoration: const InputDecoration(
                      labelText: 'Number Plate',
                      hintText: 'e.g. BNU-1234',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),

                  // Transparent Commission Card
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF166534),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.monetization_on, color: C.yellow, size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'ShanGo Earnings & Commission Policy',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Color(0xFF166534),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFDCFCE7)),
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Your Payout', style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                                    SizedBox(height: 2),
                                    Text('85% Fare', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF15803D))),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFDCFCE7)),
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('ShanGo Platform Fee', style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                                    SizedBox(height: 2),
                                    Text('15% Commission', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFFB45309))),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '• Example: On a PKR 1,000 trip, you keep PKR 850 net earnings.\n• Transparent pricing with zero hidden deduction fees.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF14532D), height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                PrimaryButton(
                  'Save & Continue',
                  isLoading: _isLoading,
                  onTap: _isLoading ? null : _saveProfile,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
