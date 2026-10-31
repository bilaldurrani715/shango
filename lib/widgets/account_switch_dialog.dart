import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets.dart';

class AccountSwitchDialog extends StatefulWidget {
  final String uid;

  const AccountSwitchDialog({super.key, required this.uid});

  static Future<void> show(BuildContext context, {required String uid}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AccountSwitchDialog(uid: uid),
    );
  }

  @override
  State<AccountSwitchDialog> createState() => _AccountSwitchDialogState();
}

class _AccountSwitchDialogState extends State<AccountSwitchDialog> {
  final AuthService _authService = AuthService();
  final RideService _rideService = RideService();
  final _formKey = GlobalKey<FormState>();

  String _vehicleType = 'Bike';
  String? _userName;
  final _modelController = TextEditingController();
  final _plateController = TextEditingController();
  final _phoneController = TextEditingController();
  final _reasonController = TextEditingController();

  bool _isSubmitting = false;
  bool _initialized = false;

  @override
  void dispose() {
    _modelController.dispose();
    _plateController.dispose();
    _phoneController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _initFields(Map<String, dynamic> data) {
    if (_initialized) return;
    _initialized = true;

    if (data['name'] != null) {
      _userName = data['name'];
    }
    if (data['phone'] != null) {
      _phoneController.text = data['phone'];
    }
    if (data['vehicleType'] != null) {
      _vehicleType = data['vehicleType'];
    }
    if (data['vehicleModel'] != null) {
      _modelController.text = data['vehicleModel'];
    }
    if (data['plateNumber'] != null) {
      _plateController.text = data['plateNumber'];
    }
  }

  Future<void> _submitRequest(String targetRole) async {
    if (targetRole == 'rider') {
      if (!_formKey.currentState!.validate()) return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _authService.submitAccountSwitchRequest(
        uid: widget.uid,
        requestedRole: targetRole,
        vehicleType: targetRole == 'rider' ? _vehicleType : null,
        vehicleModel: targetRole == 'rider' ? _modelController.text.trim() : null,
        plateNumber: targetRole == 'rider' ? _plateController.text.trim() : null,
        phone: _phoneController.text.trim(),
        reason: _reasonController.text.trim().isNotEmpty ? _reasonController.text.trim() : null,
      );

      await NotificationService().notifyAdminRoleSwitchRequest(
        userName: _userName ?? (_phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : 'User'),
        requestedRole: targetRole,
        uid: widget.uid,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account switch request submitted! Waiting for Admin approval.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit request: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _cancelRequest() async {
    setState(() => _isSubmitting = true);
    try {
      await _authService.cancelAccountSwitchRequest(widget.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Switch request cancelled.'),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _contactAdminWhatsApp() async {
    final contact = await _rideService.getAdminContactInfo();
    final adminWhatsApp = (contact['adminWhatsApp'] as String?)?.isNotEmpty == true
        ? contact['adminWhatsApp'] as String
        : (contact['adminPhone'] as String? ?? '+923451234567');
    final clean = adminWhatsApp.replaceAll(RegExp(r'[^\d]'), '');
    final msg = Uri.encodeComponent('Hello ShanGo Admin, I have submitted an account switch request for approval.');
    final uri = Uri.parse('https://wa.me/$clean?text=$msg');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _callAdmin() async {
    final contact = await _rideService.getAdminContactInfo();
    final adminPhone = (contact['adminPhone'] as String?)?.isNotEmpty == true
        ? contact['adminPhone'] as String
        : '+923451234567';
    final clean = adminPhone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
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
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _authService.streamUserProfile(widget.uid),
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
        final currentRole = (data['role'] as String?) ?? 'customer';
        final switchRequest = data['switchRequest'] as Map<String, dynamic>?;
        final isPending = switchRequest != null && switchRequest['status'] == 'pending';
        final isRejected = switchRequest != null && switchRequest['status'] == 'rejected';
        final targetRole = currentRole == 'rider' ? 'customer' : 'rider';

        _initFields(data);

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: C.yellow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.swap_horiz_rounded, color: C.black, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Switch Account Type',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.black),
                            ),
                            Text(
                              'Requires ShanGo Admin Approval',
                              style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Current Account Role Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F6F6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: currentRole == 'rider' ? C.black : C.yellow,
                        child: Icon(
                          currentRole == 'rider' ? Icons.two_wheeler : Icons.person,
                          color: currentRole == 'rider' ? C.yellow : C.black,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Account: ${currentRole == 'rider' ? 'Driver / Rider' : 'Passenger'}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            Text(
                              'Single account type per Gmail address',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: currentRole == 'rider' ? Colors.black87 : Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          currentRole == 'rider' ? 'ACTIVE DRIVER' : 'ACTIVE PASSENGER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: currentRole == 'rider' ? C.yellow : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Pending Status Box
                if (isPending) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9E6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.shade400, width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.pending_actions_rounded, color: Color(0xFFB78103), size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Switch to ${switchRequest['requestedRole'] == 'rider' ? 'Driver / Rider' : 'Passenger'} Pending',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF7A5500)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your request to switch account type has been submitted to the Admin Console. Once approved, your account will instantly switch across all your logged-in devices.',
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800, height: 1.4),
                        ),
                        if (switchRequest['requestedRole'] == 'rider') ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '• Vehicle: ${switchRequest['vehicleType'] ?? 'Bike'} - ${switchRequest['vehicleModel'] ?? 'N/A'}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '• Plate Number: ${switchRequest['plateNumber'] ?? 'N/A'}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  side: BorderSide(color: Colors.red.shade300),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text('Cancel Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: _isSubmitting ? null : _cancelRequest,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.all(10),
                              ),
                              icon: const Icon(Icons.call, size: 18),
                              tooltip: 'Call Admin Helpline',
                              onPressed: _callAdmin,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                icon: const Icon(Icons.chat, size: 16),
                                label: const Text('WhatsApp Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: _contactAdminWhatsApp,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Rejected notice if previously declined
                  if (isRejected) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Previous Request Declined',
                                  style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red, fontSize: 13),
                                ),
                                Text(
                                  switchRequest['rejectionReason'] ?? 'Details did not meet verification criteria. You can submit updated details below.',
                                  style: TextStyle(fontSize: 11.5, color: Colors.red.shade900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Form to request switch
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          targetRole == 'rider'
                              ? 'Request to become a Driver / Rider'
                              : 'Request to switch to Passenger Account',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.black),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          targetRole == 'rider'
                              ? 'Submit your vehicle & contact information for admin review.'
                              : 'Switch from driver back to standard customer mode.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                        const SizedBox(height: 16),

                        if (targetRole == 'rider') ...[
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
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _modelController,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter vehicle model (e.g. Honda CD70)' : null,
                            decoration: const InputDecoration(
                              labelText: 'Vehicle Model',
                              hintText: 'e.g. Honda CD70 / Suzuki Alto',
                              prefixIcon: Icon(Icons.electric_moped_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _plateController,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter registration plate number' : null,
                            decoration: const InputDecoration(
                              labelText: 'Plate Number',
                              hintText: 'e.g. BNU-1234',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          validator: (v) => (v == null || v.trim().length < 10) ? 'Enter valid contact phone number' : null,
                          decoration: const InputDecoration(
                            labelText: 'Contact Phone',
                            hintText: '03XXXXXXXXX',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _reasonController,
                          decoration: const InputDecoration(
                            labelText: 'Message for Admin (Optional)',
                            hintText: 'e.g. Available for full-time driving in Bannu',
                            prefixIcon: Icon(Icons.note_alt_outlined),
                          ),
                        ),

                        if (targetRole == 'rider')
                          Container(
                            margin: const EdgeInsets.only(top: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF86EFAC)),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.monetization_on, color: Color(0xFF166534), size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'ShanGo Driver Commission: 15%',
                                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFF166534)),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '• You retain 85% of all trip fares.\n• Transparent pricing with no hidden daily deductions.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF14532D), height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),

                        PrimaryButton(
                          targetRole == 'rider' ? 'Submit Driver Application' : 'Request Passenger Switch',
                          isLoading: _isSubmitting,
                          onTap: _isSubmitting ? null : () => _submitRequest(targetRole),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
