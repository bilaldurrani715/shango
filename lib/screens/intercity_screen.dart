import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth.dart';

class CityRoute {
  final String? id;
  final String from;
  final String to;
  final double distanceKm;
  final String durationText;
  final Map<String, int> baseFares;

  const CityRoute({
    this.id,
    required this.from,
    required this.to,
    required this.distanceKm,
    required this.durationText,
    required this.baseFares,
  });
}

const List<CityRoute> availableRoutes = [
  CityRoute(
    from: 'Bannu',
    to: 'Peshawar',
    distanceKm: 180,
    durationText: '3.5 Hours',
    baseFares: {
      'AC Sedan Car': 6500,
      'Economy Car': 5000,
      'Bike / Express': 2800,
      'HiAce / 7-Seater': 9500,
    },
  ),
  CityRoute(
    from: 'Bannu',
    to: 'Islamabad / Rawalpindi',
    distanceKm: 350,
    durationText: '5.5 Hours (Motorway/CPEC)',
    baseFares: {
      'AC Sedan Car': 12000,
      'Economy Car': 9500,
      'Bike / Express': 5500,
      'HiAce / 7-Seater': 16500,
    },
  ),
  CityRoute(
    from: 'Islamabad / Rawalpindi',
    to: 'Bannu',
    distanceKm: 350,
    durationText: '5.5 Hours (Motorway/CPEC)',
    baseFares: {
      'AC Sedan Car': 12000,
      'Economy Car': 9500,
      'Bike / Express': 5500,
      'HiAce / 7-Seater': 16500,
    },
  ),
  CityRoute(
    from: 'Peshawar',
    to: 'Bannu',
    distanceKm: 180,
    durationText: '3.5 Hours',
    baseFares: {
      'AC Sedan Car': 6500,
      'Economy Car': 5000,
      'Bike / Express': 2800,
      'HiAce / 7-Seater': 9500,
    },
  ),
  CityRoute(
    from: 'Bannu',
    to: 'Dera Ismail Khan',
    distanceKm: 140,
    durationText: '2.5 Hours',
    baseFares: {
      'AC Sedan Car': 5000,
      'Economy Car': 4000,
      'Bike / Express': 2200,
      'HiAce / 7-Seater': 7500,
    },
  ),
  CityRoute(
    from: 'Dera Ismail Khan',
    to: 'Bannu',
    distanceKm: 140,
    durationText: '2.5 Hours',
    baseFares: {
      'AC Sedan Car': 5000,
      'Economy Car': 4000,
      'Bike / Express': 2200,
      'HiAce / 7-Seater': 7500,
    },
  ),
  CityRoute(
    from: 'Bannu',
    to: 'Kohat',
    distanceKm: 115,
    durationText: '2.0 Hours',
    baseFares: {
      'AC Sedan Car': 4200,
      'Economy Car': 3400,
      'Bike / Express': 1800,
      'HiAce / 7-Seater': 6200,
    },
  ),
];

class VehicleOption {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final int capacity;

  const VehicleOption({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.capacity,
  });
}

const List<VehicleOption> vehicleTypes = [
  VehicleOption(
    key: 'AC Sedan Car',
    title: 'AC Sedan (Corolla / Yaris / City)',
    subtitle: 'Air Conditioned, Trunk for Luggage, Up to 4 Pax',
    icon: Icons.directions_car_filled,
    capacity: 4,
  ),
  VehicleOption(
    key: 'Economy Car',
    title: 'Economy Car (Alto / Cultus / WagonR)',
    subtitle: 'Budget Intercity Travel, Up to 3-4 Pax',
    icon: Icons.directions_car_outlined,
    capacity: 4,
  ),
  VehicleOption(
    key: 'Bike / Express',
    title: 'Motorbike / Express Courier',
    subtitle: 'Fast Solo Passenger or Urgent Parcels',
    icon: Icons.two_wheeler,
    capacity: 1,
  ),
  VehicleOption(
    key: 'HiAce / 7-Seater',
    title: 'HiAce / APV / Grand Cabin',
    subtitle: 'Group & Family Travel, Heavy Luggage, 7-12 Pax',
    icon: Icons.airport_shuttle,
    capacity: 8,
  ),
];

class IntercityBookingScreen extends StatefulWidget {
  const IntercityBookingScreen({super.key});

  @override
  State<IntercityBookingScreen> createState() => _IntercityBookingScreenState();
}

class _IntercityBookingScreenState extends State<IntercityBookingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AuthService _authService = AuthService();
  final RideService _rideService = RideService();

  // Admin Helpline Details (Dynamic from Admin Panel)
  String adminPhone = '+923451234567';
  String adminWhatsApp = '+923451234567';
  StreamSubscription? _contactSub;

  // Form State
  bool _isRoundTrip = false; // false = One Way, true = Two Way (Round Trip)
  CityRoute _selectedRoute = availableRoutes[0];
  int _selectedRouteIndex = 0;
  String _selectedVehicleKey = 'AC Sedan Car';
  DateTime _selectedDate = DateTime.now().add(const Duration(hours: 3));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 30);
  
  // Return schedule if Two-Way
  DateTime _returnDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _returnTime = const TimeOfDay(hour: 17, minute: 0);

  // Price Negotiation
  final TextEditingController _offeredPriceController = TextEditingController();
  bool _userHasCustomPrice = false;

  final TextEditingController _pickupAddressController = TextEditingController();
  final TextEditingController _dropAddressController = TextEditingController();
  LatLng? _pickupCoordinates;
  LatLng? _dropCoordinates;

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isCustomRoute = false;
  final TextEditingController _customFromController = TextEditingController(text: 'Bannu');
  final TextEditingController _customToController = TextEditingController(text: 'Peshawar');

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserInitialData();
    _syncDefaultOfferedPrice();
    _contactSub = _rideService.streamAdminContactInfo().listen((info) {
      if (mounted) {
        setState(() {
          adminPhone = (info['adminPhone'] as String?)?.isNotEmpty == true
              ? info['adminPhone'] as String
              : adminPhone;
          adminWhatsApp = (info['adminWhatsApp'] as String?)?.isNotEmpty == true
              ? info['adminWhatsApp'] as String
              : adminWhatsApp;
        });
      }
    });
  }

  void _syncDefaultOfferedPrice() {
    if (!_userHasCustomPrice) {
      final std = _calculateStandardFare();
      _offeredPriceController.text = '$std';
    }
  }

  Future<void> _loadUserInitialData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _phoneController.text = user.phoneNumber ?? '';
      final data = await _authService.getUserData(user.uid);
      if (data != null && mounted) {
        if (data['name'] != null && data['name'].toString().isNotEmpty) {
          _nameController.text = data['name'];
        }
        if (data['phone'] != null && data['phone'].toString().isNotEmpty) {
          _phoneController.text = data['phone'];
        }
      }
    }
  }

  @override
  void dispose() {
    _contactSub?.cancel();
    _tabController.dispose();
    _offeredPriceController.dispose();
    _pickupAddressController.dispose();
    _dropAddressController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _notesController.dispose();
    _customFromController.dispose();
    _customToController.dispose();
    super.dispose();
  }

  int _calculateStandardFare({String? vehicleKey}) {
    final key = vehicleKey ?? _selectedVehicleKey;
    int oneWay;
    if (_isCustomRoute) {
      if (key == 'AC Sedan Car') {
        oneWay = 7000;
      } else if (key == 'Economy Car') {
        oneWay = 5500;
      } else if (key == 'Bike / Express') {
        oneWay = 3000;
      } else {
        oneWay = 10000;
      }
    } else {
      oneWay = _selectedRoute.baseFares[key] ?? 6000;
    }

    if (_isRoundTrip) {
      // 15% discount on round-trip booking
      return (oneWay * 1.85).round();
    }
    return oneWay;
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

  void _showWhatsAppLocationExtractorDialog({required bool isDropLocation}) {
    final urlController = TextEditingController();
    bool extracting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
                child: const Icon(Icons.share_location, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isDropLocation ? 'Import Destination Location' : 'Import Pickup Location',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDropLocation
                      ? 'Paste the Google Maps link received on WhatsApp for the Destination:'
                      : 'Paste the Google Maps link received on WhatsApp for the Pickup location:',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'e.g. https://maps.app.goo.gl/xxxx or 32.986, 70.604',
                    filled: true,
                    fillColor: C.grey,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: 'Paste from clipboard',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          setModalState(() {
                            urlController.text = data!.text!;
                          });
                        }
                      },
                    ),
                  ),
                ),
                if (extracting) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator(color: C.yellow)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow),
              icon: const Icon(Icons.pin_drop, size: 18),
              label: const Text('Extract & Set Location'),
              onPressed: extracting
                  ? null
                  : () async {
                      final text = urlController.text.trim();
                      if (text.isEmpty) return;

                      final nav = Navigator.of(ctx);
                      final messenger = ScaffoldMessenger.of(context);

                      setModalState(() => extracting = true);
                      final result = await LocationService.parseLocationFromMapsLink(text);
                      setModalState(() => extracting = false);

                      if (result != null) {
                        nav.pop();
                        setState(() {
                          if (isDropLocation) {
                            _dropAddressController.text = result.name;
                            _dropCoordinates = result.location;
                          } else {
                            _pickupAddressController.text = result.name;
                            _pickupCoordinates = result.location;
                          }
                        });
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Location resolved: ${result.name}'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Could not extract coordinates from link. Please verify and try again.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDepartureDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: C.yellow,
              onPrimary: C.black,
              onSurface: C.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        if (_returnDate.isBefore(_selectedDate)) {
          _returnDate = _selectedDate;
        }
      });
    }
  }

  Future<void> _selectDepartureTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: C.yellow,
              onPrimary: C.black,
              onSurface: C.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _selectReturnDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnDate.isBefore(_selectedDate) ? _selectedDate : _returnDate,
      firstDate: _selectedDate,
      lastDate: _selectedDate.add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: C.yellow,
              onPrimary: C.black,
              onSurface: C.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _returnDate = picked);
    }
  }

  Future<void> _selectReturnTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _returnTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: C.yellow,
              onPrimary: C.black,
              onSurface: C.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _returnTime = picked);
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    final min = tod.minute.toString().padLeft(2, '0');
    return '$hour:$min $period';
  }

  Future<void> _submitBooking() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final didLogin = await nav.push<bool>(
        MaterialPageRoute(builder: (_) => const LoginScreen(asModal: true)),
      );
      if (didLogin != true) return;
      user = FirebaseAuth.instance.currentUser;
    }

    // Ensure phone number
    if (_phoneController.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please enter your contact phone number.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final fromCity = _isCustomRoute ? _customFromController.text.trim() : _selectedRoute.from;
    final toCity = _isCustomRoute ? _customToController.text.trim() : _selectedRoute.to;
    final pickup = _pickupAddressController.text.trim().isEmpty
        ? '$fromCity City / Cantt Area'
        : _pickupAddressController.text.trim();
    final drop = _dropAddressController.text.trim().isEmpty
        ? '$toCity Main City / Terminal'
        : _dropAddressController.text.trim();
    
    final standardFare = _calculateStandardFare();
    final parsedOffered = int.tryParse(_offeredPriceController.text.trim());
    final finalFare = (parsedOffered != null && parsedOffered > 0) ? parsedOffered : standardFare;
    final isNegotiated = (finalFare != standardFare);

    final timeStr = _formatTimeOfDay(_selectedTime);
    final dateStr = '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';
    final returnDateStr = '${_returnDate.day}/${_returnDate.month}/${_returnDate.year}';
    final returnTimeStr = _formatTimeOfDay(_returnTime);

    setState(() => _submitting = true);

    try {
      final docRef = await FirebaseFirestore.instance.collection('intercity_bookings').add({
        'customerId': user?.uid ?? 'guest',
        'customerName': _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Passenger',
        'customerPhone': _phoneController.text.trim(),
        'isRoundTrip': _isRoundTrip,
        'tripType': _isRoundTrip ? 'two_way' : 'one_way',
        'fromCity': fromCity,
        'toCity': toCity,
        'pickupAddress': pickup,
        'dropAddress': drop,
        'pickupCoordinates': _pickupCoordinates != null ? {'latitude': _pickupCoordinates!.latitude, 'longitude': _pickupCoordinates!.longitude} : null,
        'dropCoordinates': _dropCoordinates != null ? {'latitude': _dropCoordinates!.latitude, 'longitude': _dropCoordinates!.longitude} : null,
        'vehicleType': _selectedVehicleKey,
        'standardFare': standardFare,
        'offeredFare': finalFare,
        'fare': finalFare,
        'isNegotiated': isNegotiated,
        'scheduledDate': dateStr,
        'scheduledTime': timeStr,
        'returnDate': _isRoundTrip ? returnDateStr : null,
        'returnTime': _isRoundTrip ? returnTimeStr : null,
        'notes': _notesController.text.trim(),
        'adminPhone': adminPhone,
        'adminWhatsApp': adminWhatsApp,
        'status': isNegotiated ? 'under_negotiation' : 'scheduled', // 'under_negotiation', 'scheduled', 'confirmed', 'completed', 'cancelled'
        'negotiationStatus': isNegotiated ? 'under_review' : 'standard', // 'under_review', 'admin_countered', 'price_approved', 'price_rejected'
        'adminPriceResponse': isNegotiated ? 'Passenger proposed PKR $finalFare (Standard: PKR $standardFare). Awaiting Admin approval.' : null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await NotificationService().notifyAdminNewIntercityBooking(
        passengerName: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Passenger',
        fromCity: fromCity,
        toCity: toCity,
        fare: finalFare,
        bookingId: docRef.id,
      );

      if (mounted) {
        setState(() => _submitting = false);
        _showConfirmationDialog(
          bookingId: docRef.id,
          isRoundTrip: _isRoundTrip,
          isNegotiated: isNegotiated,
          fromCity: fromCity,
          toCity: toCity,
          pickup: pickup,
          drop: drop,
          vehicle: _selectedVehicleKey,
          fare: finalFare,
          standardFare: standardFare,
          dateStr: dateStr,
          timeStr: timeStr,
          returnDateStr: returnDateStr,
          returnTimeStr: returnTimeStr,
          passengerPhone: _phoneController.text.trim(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Error booking ride: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showConfirmationDialog({
    required String bookingId,
    required bool isRoundTrip,
    required bool isNegotiated,
    required String fromCity,
    required String toCity,
    required String pickup,
    required String drop,
    required String vehicle,
    required int fare,
    required int standardFare,
    required String dateStr,
    required String timeStr,
    required String returnDateStr,
    required String returnTimeStr,
    required String passengerPhone,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: isNegotiated ? Colors.amber.shade200 : C.yellow,
              radius: 20,
              child: Icon(isNegotiated ? Icons.handshake : Icons.check, color: C.black, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isNegotiated ? 'Price Offer Submitted!' : 'Ride Booked & Scheduled!',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isNegotiated ? Colors.amber.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isNegotiated ? Colors.amber.shade300 : Colors.green.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRoundTrip ? '$fromCity ⇄ $toCity (Round Trip)' : '$fromCity ➔ $toCity (One Way)',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isNegotiated ? Colors.amber.shade900 : Colors.green.shade900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isNegotiated
                          ? 'Your Offered Price: PKR $fare (Std: PKR $standardFare)'
                          : 'Fixed Fare: PKR $fare • $vehicle',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isNegotiated ? Colors.black87 : Colors.green.shade900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Departure: $dateStr at $timeStr',
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (isRoundTrip) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Return: $returnDateStr at $returnTimeStr',
                        style: TextStyle(color: Colors.green.shade800, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (isNegotiated)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade800, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Your proposed price is sent to the Admin. Once approved, the admin will assign a driver and link you directly.',
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Direct Contact & Helpline:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                '• Passenger Phone: $passengerPhone\n• Admin Helpline: $adminPhone\n• You can check status in "My Bookings" tab anytime.',
                style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: C.black,
                        foregroundColor: C.yellow,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _makeCall(adminPhone),
                      icon: const Icon(Icons.call, size: 18),
                      label: const Text('Call Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _openWhatsApp(
                        adminWhatsApp,
                        'Hello ShanGo Admin, I submitted an Intercity Ride request from $fromCity to $toCity on $dateStr at $timeStr. Offered Price: PKR $fare. Ref: ${bookingId.substring(0, 6)}.',
                      ),
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _tabController.animateTo(1);
            },
            child: const Text('View My Bookings', style: TextStyle(fontWeight: FontWeight.bold, color: C.black)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: C.yellow,
              foregroundColor: C.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('City to City / Intercity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: C.black,
          indicatorColor: C.yellow,
          indicatorWeight: 4,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.alt_route), text: 'Book On-Demand'),
            Tab(icon: Icon(Icons.history_edu), text: 'My Bookings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBookingFormTab(),
          _buildMyBookingsTab(),
        ],
      ),
    );
  }

  Widget _buildBookingFormTab() {
    final standardFare = _calculateStandardFare();
    final timeStr = _formatTimeOfDay(_selectedTime);
    final dateStr = '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';
    final returnDateStr = '${_returnDate.day}/${_returnDate.month}/${_returnDate.year}';
    final returnTimeStr = _formatTimeOfDay(_returnTime);

    final enteredPrice = int.tryParse(_offeredPriceController.text.trim()) ?? standardFare;
    final isDiscountPropose = enteredPrice < standardFare;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.black,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: C.yellow,
                  radius: 24,
                  child: Icon(Icons.airport_shuttle, color: C.black, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'On-Demand Intercity Rides',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Doorstep Pickup • Negotiable Fares • Admin Approved Drivers',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Trip Type Selector (One Way vs Two Way)
          const Text('Select Trip Type', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isRoundTrip = false;
                      _syncDefaultOfferedPrice();
                    });
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: !_isRoundTrip ? C.yellow : C.grey,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: !_isRoundTrip ? C.black : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_forward, color: C.black, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'One Way',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: C.black),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isRoundTrip = true;
                      _syncDefaultOfferedPrice();
                    });
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: _isRoundTrip ? C.yellow : C.grey,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isRoundTrip ? C.black : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.swap_horiz, color: C.black, size: 20),
                            const SizedBox(width: 6),
                            const Text(
                              'Two Way',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: C.black),
                            ),
                          ],
                        ),
                        Positioned(
                          top: -24,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'SAVE 15%',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 1. Select Available Route
          const Text('1. Select Route / Cities', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _rideService.streamIntercityRoutes(),
            builder: (context, snapshot) {
              List<CityRoute> routes = availableRoutes;
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                routes = snapshot.data!.map((d) {
                  final Map<String, dynamic> rawFares = (d['baseFares'] as Map<String, dynamic>?) ?? {};
                  final Map<String, int> fares = {};
                  rawFares.forEach((k, v) {
                    if (v is num) fares[k] = v.toInt();
                  });
                  return CityRoute(
                    id: d['id'],
                    from: d['from'] ?? 'Bannu',
                    to: d['to'] ?? 'Peshawar',
                    distanceKm: ((d['distanceKm'] as num?)?.toDouble()) ?? 100.0,
                    durationText: d['durationText'] ?? '3 Hours',
                    baseFares: fares.isNotEmpty ? fares : {
                      'AC Sedan Car': 6500,
                      'Economy Car': 5000,
                      'Bike / Express': 2800,
                      'HiAce / 7-Seater': 9500,
                    },
                  );
                }).toList();
              }

              final selectedIndex = _isCustomRoute
                  ? -1
                  : (_selectedRouteIndex < routes.length ? _selectedRouteIndex : 0);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: C.grey,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: selectedIndex,
                    items: [
                      ...routes.asMap().entries.map(
                            (e) => DropdownMenuItem<int>(
                              value: e.key,
                              child: Text(
                                _isRoundTrip
                                    ? '${e.value.from} ⇄ ${e.value.to} (${(e.value.distanceKm * 2).round()} km Round Trip)'
                                    : '${e.value.from} ➔ ${e.value.to} (${e.value.distanceKm.round()} km • ${e.value.durationText})',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ),
                          ),
                      const DropdownMenuItem<int>(
                        value: -1,
                        child: Text(
                          '➕ Custom City Route (Specify cities)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.blueAccent),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val == -1) {
                        setState(() {
                          _isCustomRoute = true;
                          _syncDefaultOfferedPrice();
                        });
                      } else if (val != null) {
                        setState(() {
                          _isCustomRoute = false;
                          _selectedRouteIndex = val;
                          _selectedRoute = routes[val];
                          _syncDefaultOfferedPrice();
                        });
                      }
                    },
                  ),
                ),
              );
            },
          ),

          if (_isCustomRoute) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customFromController,
                    decoration: InputDecoration(
                      labelText: 'From City',
                      filled: true,
                      fillColor: C.grey,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _customToController,
                    decoration: InputDecoration(
                      labelText: 'To City',
                      filled: true,
                      fillColor: C.grey,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // 2. Select Vehicle Type
          const Text('2. Select Available Vehicle', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _rideService.streamIntercityVehicles(),
            builder: (context, snapshot) {
              List<VehicleOption> vehicles = vehicleTypes;
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                vehicles = snapshot.data!.map((v) {
                  final key = v['key'] ?? 'AC Sedan Car';
                  IconData icon = Icons.directions_car_filled;
                  if (key.toLowerCase().contains('bike')) {
                    icon = Icons.two_wheeler;
                  } else if (key.toLowerCase().contains('hiace') || key.toLowerCase().contains('van')) {
                    icon = Icons.airport_shuttle;
                  } else if (key.toLowerCase().contains('economy')) {
                    icon = Icons.directions_car_outlined;
                  }
                  return VehicleOption(
                    key: key,
                    title: v['title'] ?? key,
                    subtitle: v['subtitle'] ?? 'Intercity Vehicle',
                    icon: icon,
                    capacity: (v['capacity'] as num?)?.toInt() ?? 4,
                  );
                }).toList();
              }

              return Column(
                children: vehicles.map((v) {
                  final isSelected = _selectedVehicleKey == v.key;
                  final price = _calculateStandardFare(vehicleKey: v.key);
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedVehicleKey = v.key;
                        _syncDefaultOfferedPrice();
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected ? C.yellow.withValues(alpha: 0.15) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? C.yellow : Colors.grey.shade300,
                          width: isSelected ? 2.2 : 1,
                        ),
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(color: C.yellow.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isSelected ? C.black : C.grey,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(v.icon, color: isSelected ? C.yellow : C.black, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(v.subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'PKR $price',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: C.black),
                              ),
                              Text(
                                _isRoundTrip ? 'Standard Fare' : 'Standard Fare',
                                style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 16),

          // 3. Select Travel Date & Fix Departure Time
          const Text('3. Departure Date & Time', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _selectDepartureDate,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: C.grey, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month, color: C.black, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Departure Date', style: TextStyle(fontSize: 11, color: Colors.black54)),
                              Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _selectDepartureTime,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: C.grey, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_filled, color: C.black, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Departure Time', style: TextStyle(fontSize: 11, color: Colors.black54)),
                              Text(timeStr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // If Two-Way: Return Schedule Row
          if (_isRoundTrip) ...[
            const SizedBox(height: 14),
            const Text('Return Schedule (Two Way)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _selectReturnDate,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_repeat, color: Colors.green.shade800, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Return Date', style: TextStyle(fontSize: 11, color: Colors.black54)),
                                Text(returnDateStr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _selectReturnTime,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.green.shade800, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Return Time', style: TextStyle(fontSize: 11, color: Colors.black54)),
                                Text(returnTimeStr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // 4. Passenger & Location Details
          const Text('4. Passenger & Address Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),

          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Passenger Name',
              prefixIcon: const Icon(Icons.person),
              filled: true,
              fillColor: C.grey,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Contact Phone Number (For Driver & Admin Call)',
              prefixIcon: const Icon(Icons.phone),
              filled: true,
              fillColor: C.grey,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          // Pickup Address & WhatsApp Import
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Pickup Address in ${_isCustomRoute ? _customFromController.text : _selectedRoute.from}:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              TextButton.icon(
                icon: const Icon(Icons.share_location, color: Color(0xFF25D366), size: 16),
                label: const Text('WhatsApp Map Link', style: TextStyle(color: Color(0xFF25D366), fontSize: 11, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                onPressed: () => _showWhatsAppLocationExtractorDialog(isDropLocation: false),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _pickupAddressController,
            decoration: InputDecoration(
              labelText: 'Exact Pickup Address',
              hintText: 'e.g. Bannu Cantt / City Bazaar / Near USTB',
              prefixIcon: const Icon(Icons.location_on, color: Colors.green),
              suffixIcon: IconButton(
                icon: const Icon(Icons.share_location, color: Color(0xFF25D366)),
                tooltip: 'Import from WhatsApp Google Maps Link',
                onPressed: () => _showWhatsAppLocationExtractorDialog(isDropLocation: false),
              ),
              filled: true,
              fillColor: C.grey,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          if (_pickupCoordinates != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 14),
                const SizedBox(width: 4),
                Text(
                  'GPS Coordinates: ${_pickupCoordinates!.latitude.toStringAsFixed(5)}, ${_pickupCoordinates!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          // Destination / Drop Address & WhatsApp Import
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Destination / Drop in ${_isCustomRoute ? _customToController.text : _selectedRoute.to}:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              TextButton.icon(
                icon: const Icon(Icons.share_location, color: Color(0xFF25D366), size: 16),
                label: const Text('WhatsApp Map Link', style: TextStyle(color: Color(0xFF25D366), fontSize: 11, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                onPressed: () => _showWhatsAppLocationExtractorDialog(isDropLocation: true),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _dropAddressController,
            decoration: InputDecoration(
              labelText: 'Exact Destination Address',
              hintText: 'e.g. Peshawar Saddar / Hayatabad Phase 3 / Islamabad I-8',
              prefixIcon: const Icon(Icons.location_city, color: C.yellow),
              suffixIcon: IconButton(
                icon: const Icon(Icons.share_location, color: Color(0xFF25D366)),
                tooltip: 'Import from WhatsApp Google Maps Link',
                onPressed: () => _showWhatsAppLocationExtractorDialog(isDropLocation: true),
              ),
              filled: true,
              fillColor: C.grey,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          if (_dropCoordinates != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Destination GPS Coordinates: ${_dropCoordinates!.latitude.toStringAsFixed(5)}, ${_dropCoordinates!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            decoration: InputDecoration(
              labelText: 'Special Instructions / Waiting notes (Optional)',
              prefixIcon: const Icon(Icons.edit_note),
              filled: true,
              fillColor: C.grey,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),

          const SizedBox(height: 24),

          // 5. PRICE NEGOTIATION & OFFER BOX
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.shade300, width: 1.8),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
                      child: const Icon(Icons.handshake, color: Colors.black87, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Price Negotiation & Offer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text('Propose your fair fare to Admin', style: TextStyle(fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Standard Estimated Fare:', style: TextStyle(color: Colors.black54, fontSize: 13)),
                    Text('PKR $standardFare', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),

                const Text('Your Offered Price (PKR):', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 6),

                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: C.black, size: 30),
                      onPressed: () {
                        final cur = int.tryParse(_offeredPriceController.text.trim()) ?? standardFare;
                        if (cur > 1000) {
                          setState(() {
                            _userHasCustomPrice = true;
                            _offeredPriceController.text = '${cur - 500}';
                          });
                        }
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _offeredPriceController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: C.black),
                        onChanged: (val) {
                          setState(() => _userHasCustomPrice = true);
                        },
                        decoration: InputDecoration(
                          hintText: '$standardFare',
                          filled: true,
                          fillColor: C.grey,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: C.black, size: 30),
                      onPressed: () {
                        final cur = int.tryParse(_offeredPriceController.text.trim()) ?? standardFare;
                        setState(() {
                          _userHasCustomPrice = true;
                          _offeredPriceController.text = '${cur + 500}';
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_userHasCustomPrice && isDiscountPropose)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Offering PKR ${standardFare - enteredPrice} lower than standard price',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                        ),
                      ],
                    ),
                  ),
                if (_userHasCustomPrice)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _userHasCustomPrice = false;
                          _offeredPriceController.text = '$standardFare';
                        });
                      },
                      child: const Text('Reset to Standard Fare', style: TextStyle(fontSize: 12, color: Colors.blueAccent)),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_submitting)
            const Center(child: CircularProgressIndicator(color: C.yellow))
          else
            PrimaryButton(
              enteredPrice != standardFare
                  ? 'Submit Ride Offer (PKR $enteredPrice)'
                  : 'Confirm & Book Intercity Ride (PKR $standardFare)',
              onTap: _submitBooking,
            ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildMyBookingsTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history_edu, size: 64, color: Colors.grey),
              const SizedBox(height: 14),
              const Text('Please sign in to view your intercity bookings', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              PrimaryButton('Login', onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(asModal: true)));
              }),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('intercity_bookings')
          .where('customerId', isEqualTo: user.uid)
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
                  Icon(Icons.commute_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 14),
                  const Text('No Intercity Bookings Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    'Your on-demand intercity bookings and price negotiations will appear here.',
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
            final standardFare = data['standardFare'] ?? fare;
            final vehicle = data['vehicleType'] ?? 'Car';
            final isRoundTrip = data['isRoundTrip'] == true || data['tripType'] == 'two_way';
            final dateStr = data['scheduledDate'] ?? '';
            final timeStr = data['scheduledTime'] ?? '';
            final returnDate = data['returnDate'];
            final returnTime = data['returnTime'];
            final status = data['status'] ?? 'scheduled';
            final negStatus = data['negotiationStatus'] ?? 'standard';
            final adminResponse = data['adminPriceResponse'] as String?;
            final counterPrice = (data['counterPrice'] as num?)?.toInt();
            final adminNum = data['adminPhone'] ?? adminPhone;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: negStatus == 'admin_countered'
                      ? Colors.blue.shade300
                      : (negStatus == 'under_review' ? Colors.amber.shade300 : Colors.grey.shade200),
                  width: negStatus == 'admin_countered' ? 2 : 1,
                ),
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
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: isRoundTrip ? Colors.blue.shade100 : C.yellow.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isRoundTrip ? 'TWO WAY' : 'ONE WAY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: isRoundTrip ? Colors.blue.shade900 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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

                  // Fare & Negotiation Status Banner
                  if (negStatus == 'under_review') ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade200)),
                      child: Row(
                        children: [
                          const Icon(Icons.hourglass_top, color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Price Offer Under Review: You offered PKR $fare (Standard: PKR $standardFare). Admin is reviewing your proposal.',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (negStatus == 'admin_countered' && counterPrice != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade300)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.campaign, color: Colors.blue.shade800, size: 20),
                              const SizedBox(width: 8),
                              Text('Admin Counter Offer: PKR $counterPrice', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.blue.shade900)),
                            ],
                          ),
                          if (adminResponse != null) ...[
                            const SizedBox(height: 4),
                            Text('"$adminResponse"', style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontStyle: FontStyle.italic)),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    await _rideService.passengerAcceptCounterPrice(bookingId, counterPrice);
                                    messenger.showSnackBar(SnackBar(content: Text('Agreed on PKR $counterPrice! Driver will be assigned.')));
                                  },
                                  child: Text('Accept PKR $counterPrice', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                onPressed: () => _showReofferDialog(context, bookingId, counterPrice),
                                child: const Text('Re-offer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else if (negStatus == 'price_rejected') ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('❌ Price Offer Declined: ${adminResponse ?? "Price too low"}', style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: C.black, foregroundColor: C.yellow, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: () => _showReofferDialog(context, bookingId, standardFare),
                            child: const Text('Re-Submit New Offer / Standard Price', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Text('Confirmed Fare: PKR $fare', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ],

                  // Driver Details Card when driver is assigned
                  if (data['riderName'] != null || data['riderPhone'] != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade300, width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF25D366),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.two_wheeler, color: Colors.white, size: 16),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Assigned Driver & Vehicle Details',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1E7E34)),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(6)),
                                child: const Text('LINKED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Driver: ${data['riderName'] ?? "Assigned Driver"}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: C.black),
                          ),
                          if (data['riderPhone'] != null)
                            Text(
                              'Phone: ${data['riderPhone']}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
                            ),
                          if (data['vehicleModel'] != null || data['plateNumber'] != null)
                            Text(
                              'Vehicle: ${data['vehicleModel'] ?? vehicle} ${data['plateNumber'] != null ? "(${data['plateNumber']})" : ""}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          const Divider(height: 16),
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
                                  label: const Text('Call Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: () => _makeCall(data['riderPhone'] ?? ''),
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
                                  label: const Text('WhatsApp Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: () => _openWhatsApp(
                                    data['riderPhone'] ?? '',
                                    'Hello ${data['riderName'] ?? "Driver"}, I am your passenger for the ShanGo intercity ride from $from to $to scheduled on $dateStr at $timeStr. Pickup: ${data['pickupAddress'] ?? ""}.',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.amber, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Driver Status: Admin will assign your dedicated driver before departure.',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Status: ${status.toUpperCase()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.call, color: Colors.black),
                            tooltip: 'Call Helpline',
                            onPressed: () => _makeCall(adminNum),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                            tooltip: 'WhatsApp Admin',
                            onPressed: () => _openWhatsApp(
                              adminWhatsApp,
                              'Inquiry about intercity ride $from to $to on $dateStr (ID: ${bookingId.substring(0, 6)})',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showReofferDialog(BuildContext context, String bookingId, int currentPrice) {
    final reofferController = TextEditingController(text: '$currentPrice');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Re-Offer Price', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter your revised fare offer in PKR:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: reofferController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Revised Price (PKR)',
                filled: true,
                fillColor: C.grey,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.yellow, foregroundColor: C.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              final newPrice = int.tryParse(reofferController.text.trim());
              if (newPrice != null && newPrice > 0) {
                Navigator.pop(ctx);
                await _rideService.passengerReofferPrice(bookingId, newPrice);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Revised offer of PKR $newPrice submitted!')));
                }
              }
            },
            child: const Text('Submit Offer', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
