import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

class RideModel {
  final String id;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String? riderId;
  final String? riderName;
  final String? riderPhone;
  final String? vehicleType;
  final String? vehicleModel;
  final String? plateNumber;
  final String pickupAddress;
  final String dropAddress;
  final LatLng pickupLocation;
  final LatLng dropLocation;
  final LatLng? riderLocation;
  final double estimatedFare;
  final double distanceKm;
  final String status; // 'requested', 'accepted', 'in_progress', 'completed', 'cancelled'
  final double? rating;
  final String? reviewMessage;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  RideModel({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.riderId,
    this.riderName,
    this.riderPhone,
    this.vehicleType,
    this.vehicleModel,
    this.plateNumber,
    required this.pickupAddress,
    required this.dropAddress,
    required this.pickupLocation,
    required this.dropLocation,
    this.riderLocation,
    required this.estimatedFare,
    required this.distanceKm,
    required this.status,
    this.rating,
    this.reviewMessage,
    this.reviewedAt,
    required this.createdAt,
  });

  factory RideModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return RideModel(
      id: doc.id,
      customerId: data['customerId'] ?? '',
      customerName: data['customerName'] ?? 'Customer',
      customerPhone: data['customerPhone'] ?? '',
      riderId: data['riderId'],
      riderName: data['riderName'],
      riderPhone: data['riderPhone'],
      vehicleType: data['vehicleType'],
      vehicleModel: data['vehicleModel'],
      plateNumber: data['plateNumber'],
      pickupAddress: data['pickupAddress'] ?? '',
      dropAddress: data['dropAddress'] ?? '',
      pickupLocation: LatLng(
        (data['pickupLat'] as num?)?.toDouble() ?? 32.9861,
        (data['pickupLng'] as num?)?.toDouble() ?? 70.6042,
      ),
      dropLocation: LatLng(
        (data['dropLat'] as num?)?.toDouble() ?? 32.9900,
        (data['dropLng'] as num?)?.toDouble() ?? 70.6100,
      ),
      riderLocation: (data['riderLat'] != null && data['riderLng'] != null)
          ? LatLng((data['riderLat'] as num).toDouble(), (data['riderLng'] as num).toDouble())
          : null,
      estimatedFare: (data['estimatedFare'] as num?)?.toDouble() ?? 300.0,
      distanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 2.0,
      status: data['status'] ?? 'requested',
      rating: (data['rating'] as num?)?.toDouble(),
      reviewMessage: data['reviewMessage'],
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'riderId': riderId,
      'riderName': riderName,
      'riderPhone': riderPhone,
      'vehicleType': vehicleType,
      'vehicleModel': vehicleModel,
      'plateNumber': plateNumber,
      'pickupAddress': pickupAddress,
      'dropAddress': dropAddress,
      'pickupLat': pickupLocation.latitude,
      'pickupLng': pickupLocation.longitude,
      'dropLat': dropLocation.latitude,
      'dropLng': dropLocation.longitude,
      'riderLat': riderLocation?.latitude,
      'riderLng': riderLocation?.longitude,
      'estimatedFare': estimatedFare,
      'distanceKm': distanceKm,
      'status': status,
      'rating': rating,
      'reviewMessage': reviewMessage,
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class OnlineRiderInfo {
  final String uid;
  final LatLng location;
  final String vehicleType;
  final String vehicleModel;

  const OnlineRiderInfo({
    required this.uid,
    required this.location,
    this.vehicleType = 'Bike',
    this.vehicleModel = 'Motorbike',
  });
}

class RideService {
  final CollectionReference _ridesRef = FirebaseFirestore.instance.collection('rides');

  /// 1. Create a new ride request
  Future<String> requestRide({
    required String customerId,
    required String customerName,
    required String customerPhone,
    required String pickupAddress,
    required String dropAddress,
    required LatLng pickupLocation,
    required LatLng dropLocation,
    required double estimatedFare,
    required double distanceKm,
  }) async {
    final docRef = await _ridesRef.add({
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'pickupAddress': pickupAddress,
      'dropAddress': dropAddress,
      'pickupLat': pickupLocation.latitude,
      'pickupLng': pickupLocation.longitude,
      'dropLat': dropLocation.latitude,
      'dropLng': dropLocation.longitude,
      'riderLat': null,
      'riderLng': null,
      'estimatedFare': estimatedFare,
      'distanceKm': distanceKm,
      'status': 'requested',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// 2. Stream a specific ride for real-time customer and rider tracking
  Stream<RideModel?> streamRide(String rideId) {
    return _ridesRef.doc(rideId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return RideModel.fromFirestore(snapshot);
    });
  }

  /// Maximum valid age in seconds for a pending ride request to be broadcast to drivers (2 minutes)
  static const int maxRideRequestAgeSeconds = 120;

  /// 3. Stream all pending active ride requests for riders (filtered for freshness)
  Stream<List<RideModel>> streamAvailableRides() {
    return _ridesRef
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final validRides = <RideModel>[];
          for (final doc in snapshot.docs) {
            final ride = RideModel.fromFirestore(doc);
            final ageSeconds = now.difference(ride.createdAt).inSeconds;
            // A request is valid if created within the last 120 seconds (clock skew is tolerated)
            if (ageSeconds <= maxRideRequestAgeSeconds) {
              validRides.add(ride);
            } else {
              // Asynchronously auto-expire stale/dummy test requests in Firestore
              _ridesRef.doc(ride.id).update({
                'status': 'expired',
                'expiredAt': FieldValue.serverTimestamp(),
              }).catchError((e) {
                debugPrint('Auto-expire stale ride error: $e');
              });
            }
          }
          return validRides;
        });
  }

  /// Explicitly clean up all old/dummy requested rides left in Firestore
  Future<void> purgeStaleRequestedRides() async {
    try {
      final snapshot = await _ridesRef.where('status', isEqualTo: 'requested').get();
      final now = DateTime.now();
      final batch = FirebaseFirestore.instance.batch();
      int count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final createdAt = (data?['createdAt'] as Timestamp?)?.toDate();
        if (createdAt == null || now.difference(createdAt).inSeconds > maxRideRequestAgeSeconds) {
          batch.update(doc.reference, {
            'status': 'expired',
            'expiredAt': FieldValue.serverTimestamp(),
          });
          count++;
        }
      }
      if (count > 0) {
        await batch.commit();
        debugPrint('Successfully purged $count stale/dummy ride requests from Firestore.');
      }
    } catch (e) {
      debugPrint('Error purging stale rides: $e');
    }
  }

  /// 4. Rider accepts a ride request (uses a Firestore transaction to prevent race conditions when multiple riders accept)
  Future<bool> acceptRide({
    required String rideId,
    required String riderId,
    required String riderName,
    required String riderPhone,
    String? vehicleType,
    String? vehicleModel,
    String? plateNumber,
    required LatLng riderLocation,
  }) async {
    try {
      final docRef = _ridesRef.doc(rideId);
      final success = await FirebaseFirestore.instance.runTransaction<bool>((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          return false;
        }
        final data = snapshot.data() as Map<String, dynamic>?;
        final currentStatus = data?['status'] as String?;
        if (currentStatus != 'requested') {
          // Ride was already accepted by another rider or cancelled
          return false;
        }

        transaction.update(docRef, {
          'riderId': riderId,
          'riderName': riderName,
          'riderPhone': riderPhone,
          'vehicleType': vehicleType,
          'vehicleModel': vehicleModel,
          'plateNumber': plateNumber,
          'riderLat': riderLocation.latitude,
          'riderLng': riderLocation.longitude,
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });

      if (success) {
        _onlineRidersRef.doc(riderId).set({
          'isOnTrip': true,
          'currentRideId': rideId,
        }, SetOptions(merge: true)).catchError((_) {});
      }
      return success;
    } catch (e) {
      debugPrint('Error in acceptRide transaction: $e');
      return false;
    }
  }

  /// 4.1 Start Trip / Passenger Onboard
  Future<void> startTrip(String rideId) async {
    await _ridesRef.doc(rideId).update({
      'status': 'in_progress',
      'startedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 5. Update rider's live coordinates in real-time
  Future<void> updateRiderLocation(String rideId, LatLng riderLocation) async {
    await _ridesRef.doc(rideId).update({
      'riderLat': riderLocation.latitude,
      'riderLng': riderLocation.longitude,
    });
  }

  /// 6. Complete a ride
  Future<void> completeRide(String rideId) async {
    final doc = await _ridesRef.doc(rideId).get();
    final data = doc.data() as Map<String, dynamic>?;
    final riderId = data?['riderId'] as String?;

    await _ridesRef.doc(rideId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });

    if (riderId != null) {
      _onlineRidersRef.doc(riderId).set({
        'isOnTrip': false,
        'currentRideId': null,
      }, SetOptions(merge: true)).catchError((_) {});
    }
  }

  /// 7. Cancel a ride
  Future<void> cancelRide(String rideId) async {
    final doc = await _ridesRef.doc(rideId).get();
    final data = doc.data() as Map<String, dynamic>?;
    final riderId = data?['riderId'] as String?;

    await _ridesRef.doc(rideId).update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    });

    if (riderId != null) {
      _onlineRidersRef.doc(riderId).set({
        'isOnTrip': false,
        'currentRideId': null,
      }, SetOptions(merge: true)).catchError((_) {});
    }
  }

  /// 8. Stream real ride history for a customer or rider from Firestore
  Stream<List<RideModel>> streamUserRides({required String uid, required bool isRider}) {
    final queryField = isRider ? 'riderId' : 'customerId';
    return _ridesRef
        .where(queryField, isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final rides = snapshot.docs.map((d) => RideModel.fromFirestore(d)).toList();
          rides.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return rides;
        });
  }

  /// 9. Stream today's real completed rides and earnings for a rider
  Stream<Map<String, num>> streamRiderTodayStats(String riderId) {
    return _ridesRef
        .where('riderId', isEqualTo: riderId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final startOfDay = DateTime(now.year, now.month, now.day);

          int count = 0;
          double earnings = 0.0;

          for (final doc in snapshot.docs) {
            final ride = RideModel.fromFirestore(doc);
            if (ride.createdAt.isAfter(startOfDay)) {
              count++;
              earnings += ride.estimatedFare;
            }
          }
          return {
            'rides': count,
            'earnings': earnings,
          };
        });
  }

  final CollectionReference _onlineRidersRef = FirebaseFirestore.instance.collection('online_riders');

  /// 10. Update rider online status in Firestore
  Future<void> setRiderOnlineStatus({
    required String uid,
    required bool isOnline,
    LatLng? location,
    String? vehicleType,
    String? vehicleModel,
  }) async {
    if (isOnline && location != null) {
      String? token;
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}

      final onlineData = <String, dynamic>{
        'uid': uid,
        'isOnline': true,
        'lat': location.latitude,
        'lng': location.longitude,
        'vehicleType': vehicleType ?? 'Bike',
        'vehicleModel': vehicleModel ?? 'Motorbike',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (token != null && token.isNotEmpty) {
        onlineData['fcmToken'] = token;
        onlineData['fcmTokenUpdatedAt'] = FieldValue.serverTimestamp();
      }

      await _onlineRidersRef.doc(uid).set(onlineData, SetOptions(merge: true));
    } else {
      try {
        await _onlineRidersRef.doc(uid).delete();
      } catch (e) {
        debugPrint('Delete online rider error: $e');
      }
    }
  }

  /// 11. Update live GPS coordinates of online rider
  Future<void> updateOnlineRiderPosition({
    required String uid,
    required LatLng location,
  }) async {
    await _onlineRidersRef.doc(uid).set({
      'isOnline': true,
      'lat': location.latitude,
      'lng': location.longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 12. Stream all genuinely active online rider locations for passenger / guest map view
  Stream<List<LatLng>> streamOnlineRiders() {
    return _onlineRidersRef
        .snapshots()
        .map((snapshot) {
          final riders = <LatLng>[];
          final now = DateTime.now();
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null && (data['isOnline'] == true)) {
              // Resilient stale check: Only filter out if no ping for > 45 minutes.
              // Note: clock skew between device and server is tolerated to avoid dropping active drivers.
              final updatedAt = data['updatedAt'];
              if (updatedAt is Timestamp) {
                final lastPing = updatedAt.toDate();
                final diffMinutes = now.difference(lastPing).inMinutes;
                if (diffMinutes >= 45) {
                  continue; // Rider app has been dormant for over 45 minutes
                }
              }
              final lat = (data['lat'] as num?)?.toDouble();
              final lng = (data['lng'] as num?)?.toDouble();
              if (lat != null && lng != null && (lat != 0.0 || lng != 0.0)) {
                riders.add(LatLng(lat, lng));
              }
            }
          }
          return riders;
        });
  }

  /// Stream full details of active online riders
  Stream<List<OnlineRiderInfo>> streamOnlineRiderDetails() {
    return _onlineRidersRef
        .snapshots()
        .map((snapshot) {
          final riders = <OnlineRiderInfo>[];
          final now = DateTime.now();
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null && (data['isOnline'] == true)) {
              final updatedAt = data['updatedAt'];
              if (updatedAt is Timestamp) {
                final lastPing = updatedAt.toDate();
                final diffMinutes = now.difference(lastPing).inMinutes;
                if (diffMinutes >= 45) {
                  continue;
                }
              }
              final lat = (data['lat'] as num?)?.toDouble();
              final lng = (data['lng'] as num?)?.toDouble();
              if (lat != null && lng != null && (lat != 0.0 || lng != 0.0)) {
                riders.add(
                  OnlineRiderInfo(
                    uid: doc.id,
                    location: LatLng(lat, lng),
                    vehicleType: (data['vehicleType'] as String?) ?? 'Bike',
                    vehicleModel: (data['vehicleModel'] as String?) ?? 'Motorbike',
                  ),
                );
              }
            }
          }
          return riders;
        });
  }

  /// 13. Submit a review from the passenger for the rider
  Future<void> submitRideReview({
    required String rideId,
    required String riderId,
    required String customerId,
    required String customerName,
    required double rating,
    required String message,
  }) async {
    // 1. Update the ride record
    await _ridesRef.doc(rideId).update({
      'rating': rating,
      'reviewMessage': message,
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    // 2. Add to rider's reviews subcollection
    final riderReviewsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(riderId)
        .collection('reviews');

    await riderReviewsRef.doc(rideId).set({
      'rideId': rideId,
      'customerId': customerId,
      'customerName': customerName,
      'rating': rating,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 3. Update rider's overall rating stats in users collection
    final userRef = FirebaseFirestore.instance.collection('users').doc(riderId);
    final userDoc = await userRef.get();
    final data = userDoc.data() ?? {};

    final currentTotalRatings = (data['totalRatings'] as num?)?.toInt() ?? 0;
    final currentRatingSum = (data['ratingSum'] as num?)?.toDouble() ?? 0.0;

    final newTotalRatings = currentTotalRatings + 1;
    final newRatingSum = currentRatingSum + rating;
    final newAverageRating = newRatingSum / newTotalRatings;

    await userRef.set({
      'rating': double.parse(newAverageRating.toStringAsFixed(1)),
      'totalRatings': newTotalRatings,
      'ratingSum': newRatingSum,
      'latestReview': {
        'customerName': customerName,
        'rating': rating,
        'message': message,
        'createdAt': DateTime.now().toIso8601String(),
      },
    }, SetOptions(merge: true));
  }

  /// 14. Stream all past reviews for a rider
  Stream<List<Map<String, dynamic>>> streamRiderReviews(String riderId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(riderId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => d.data()).toList());
  }

  /// 15. Stream rider public profile summary (rating, total ratings, latest review)
  Stream<Map<String, dynamic>?> streamRiderProfile(String riderId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(riderId)
        .snapshots()
        .map((doc) => doc.data());
  }

  /// 16. Stream all registered users by role (admin)
  Stream<List<Map<String, dynamic>>> streamUsers({String? role}) {
    Query query = FirebaseFirestore.instance.collection('users');
    if (role != null) {
      query = query.where('role', isEqualTo: role);
    }
    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['uid'] = doc.id;
        return data;
      }).toList();
    });
  }

  /// 17. Stream all rides for overall admin analytics
  Stream<List<RideModel>> streamAllRides() {
    return _ridesRef.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) => RideModel.fromFirestore(doc)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// 18. Stream all intercity bookings (admin)
  Stream<List<Map<String, dynamic>>> streamAllIntercityBookings() {
    return FirebaseFirestore.instance
        .collection('intercity_bookings')
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
          return list;
        });
  }

  /// 19. Admin assign driver & confirm intercity booking
  Future<void> assignDriverToIntercityBooking({
    required String bookingId,
    required String riderId,
    required String riderName,
    required String riderPhone,
    String? vehicleModel,
    String? plateNumber,
    int? confirmedFare,
  }) async {
    final Map<String, dynamic> updateData = {
      'riderId': riderId,
      'riderName': riderName,
      'riderPhone': riderPhone,
      'status': 'confirmed',
      'assignedAt': FieldValue.serverTimestamp(),
    };
    if (vehicleModel != null) updateData['vehicleModel'] = vehicleModel;
    if (plateNumber != null) updateData['plateNumber'] = plateNumber;
    if (confirmedFare != null) updateData['fare'] = confirmedFare;

    await FirebaseFirestore.instance
        .collection('intercity_bookings')
        .doc(bookingId)
        .update(updateData);
  }

  /// 20. Update intercity booking status
  Future<void> updateIntercityBookingStatus(String bookingId, String status) async {
    await FirebaseFirestore.instance
        .collection('intercity_bookings')
        .doc(bookingId)
        .update({'status': status});
  }

  /// 21. Admin approve passenger's offered negotiated price
  Future<void> adminApproveNegotiatedPrice(String bookingId, int approvedPrice) async {
    await FirebaseFirestore.instance
        .collection('intercity_bookings')
        .doc(bookingId)
        .update({
          'fare': approvedPrice,
          'negotiationStatus': 'price_approved',
          'status': 'scheduled',
          'adminPriceResponse': 'Price accepted by Admin. Ready for driver assignment.',
          'priceApprovedAt': FieldValue.serverTimestamp(),
        });
  }

  /// 22. Admin send counter-offer price to passenger
  Future<void> adminCounterNegotiatedPrice(String bookingId, int counterPrice, {String? adminMessage}) async {
    await FirebaseFirestore.instance
        .collection('intercity_bookings')
        .doc(bookingId)
        .update({
          'counterPrice': counterPrice,
          'negotiationStatus': 'admin_countered',
          'adminPriceResponse': adminMessage ?? 'Admin proposed PKR $counterPrice for this ride.',
          'counteredAt': FieldValue.serverTimestamp(),
        });
  }

  /// 23. Admin reject passenger's offered price
  Future<void> adminRejectNegotiatedPrice(String bookingId, {String? adminMessage}) async {
    await FirebaseFirestore.instance
        .collection('intercity_bookings')
        .doc(bookingId)
        .update({
          'negotiationStatus': 'price_rejected',
          'adminPriceResponse': adminMessage ?? 'Offered price is too low for this route and vehicle. Please re-offer or accept standard fare.',
          'rejectedAt': FieldValue.serverTimestamp(),
        });
  }

  /// 24. Passenger accept admin's counter price
  Future<void> passengerAcceptCounterPrice(String bookingId, int acceptedPrice) async {
    await FirebaseFirestore.instance
        .collection('intercity_bookings')
        .doc(bookingId)
        .update({
          'fare': acceptedPrice,
          'negotiationStatus': 'price_approved',
          'status': 'scheduled',
          'adminPriceResponse': 'Passenger agreed to PKR $acceptedPrice. Awaiting driver assignment.',
        });
  }

  /// 25. Passenger re-submit a new price offer
  Future<void> passengerReofferPrice(String bookingId, int newOfferedPrice) async {
    await FirebaseFirestore.instance
        .collection('intercity_bookings')
        .doc(bookingId)
        .update({
          'offeredFare': newOfferedPrice,
          'fare': newOfferedPrice,
          'negotiationStatus': 'under_review',
          'status': 'under_negotiation',
          'adminPriceResponse': 'Passenger revised offer to PKR $newOfferedPrice.',
          'reofferedAt': FieldValue.serverTimestamp(),
        });
  }

  // ==========================================
  // INTERCITY ROUTES & VEHICLE TYPES CONFIG
  // ==========================================

  /// Stream dynamic local ride pricing settings configured by Admin
  Stream<Map<String, dynamic>> streamLocalPricing() {
    return FirebaseFirestore.instance
        .collection('app_settings')
        .doc('local_pricing')
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists || snapshot.data() == null) {
            return {
              'baseFare': 150.0,
              'perKmRate': 40.0,
              'commissionPercent': 15.0,
            };
          }
          final data = snapshot.data()!;
          return {
            'baseFare': (data['baseFare'] as num?)?.toDouble() ?? 150.0,
            'perKmRate': (data['perKmRate'] as num?)?.toDouble() ?? 40.0,
            'commissionPercent': (data['commissionPercent'] as num?)?.toDouble() ?? 15.0,
          };
        });
  }

  /// Update local ride pricing settings
  Future<void> updateLocalPricing({
    required double baseFare,
    required double perKmRate,
    required double commissionPercent,
  }) async {
    await FirebaseFirestore.instance.collection('app_settings').doc('local_pricing').set({
      'baseFare': baseFare,
      'perKmRate': perKmRate,
      'commissionPercent': commissionPercent,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Default fallback admin contact info
  static const Map<String, dynamic> defaultAdminContact = {
    'adminPhone': '+923451234567',
    'adminWhatsApp': '+923451234567',
    'adminEmail': 'info@jabirulabs.com',
    'supportAddress': 'Bannu / Peshawar, Khyber Pakhtunkhwa, Pakistan',
  };

  /// Stream dynamic admin contact info configured from Admin Panel
  Stream<Map<String, dynamic>> streamAdminContactInfo() {
    return FirebaseFirestore.instance
        .collection('app_settings')
        .doc('admin_contact')
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists || snapshot.data() == null) {
            return Map<String, dynamic>.from(defaultAdminContact);
          }
          final data = snapshot.data()!;
          return {
            'adminPhone': (data['adminPhone'] as String?)?.trim().isNotEmpty == true
                ? (data['adminPhone'] as String).trim()
                : defaultAdminContact['adminPhone'],
            'adminWhatsApp': (data['adminWhatsApp'] as String?)?.trim().isNotEmpty == true
                ? (data['adminWhatsApp'] as String).trim()
                : defaultAdminContact['adminWhatsApp'],
            'adminEmail': (data['adminEmail'] as String?)?.trim().isNotEmpty == true
                ? (data['adminEmail'] as String).trim()
                : defaultAdminContact['adminEmail'],
            'supportAddress': (data['supportAddress'] as String?)?.trim().isNotEmpty == true
                ? (data['supportAddress'] as String).trim()
                : defaultAdminContact['supportAddress'],
          };
        });
  }

  /// Get current admin contact info once
  Future<Map<String, dynamic>> getAdminContactInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('admin_contact')
          .get();
      if (!doc.exists || doc.data() == null) {
        return Map<String, dynamic>.from(defaultAdminContact);
      }
      final data = doc.data()!;
      return {
        'adminPhone': (data['adminPhone'] as String?)?.trim().isNotEmpty == true
            ? (data['adminPhone'] as String).trim()
            : defaultAdminContact['adminPhone'],
        'adminWhatsApp': (data['adminWhatsApp'] as String?)?.trim().isNotEmpty == true
            ? (data['adminWhatsApp'] as String).trim()
            : defaultAdminContact['adminWhatsApp'],
        'adminEmail': (data['adminEmail'] as String?)?.trim().isNotEmpty == true
            ? (data['adminEmail'] as String).trim()
            : defaultAdminContact['adminEmail'],
        'supportAddress': (data['supportAddress'] as String?)?.trim().isNotEmpty == true
            ? (data['supportAddress'] as String).trim()
            : defaultAdminContact['supportAddress'],
      };
    } catch (_) {
      return Map<String, dynamic>.from(defaultAdminContact);
    }
  }

  /// Update admin contact info from Admin Panel
  Future<void> updateAdminContactInfo({
    required String adminPhone,
    required String adminWhatsApp,
    String? adminEmail,
    String? supportAddress,
  }) async {
    await FirebaseFirestore.instance.collection('app_settings').doc('admin_contact').set({
      'adminPhone': adminPhone.trim(),
      'adminWhatsApp': adminWhatsApp.trim(),
      'adminEmail': (adminEmail ?? defaultAdminContact['adminEmail']).trim(),
      'supportAddress': (supportAddress ?? defaultAdminContact['supportAddress']).trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream dynamic intercity routes configured by Admin
  Stream<List<Map<String, dynamic>>> streamIntercityRoutes() {
    return FirebaseFirestore.instance
        .collection('intercity_routes')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
        });
  }

  /// Add new intercity route
  Future<String> addIntercityRoute(Map<String, dynamic> routeData) async {
    final docRef = await FirebaseFirestore.instance.collection('intercity_routes').add({
      ...routeData,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Update existing intercity route & pricing
  Future<void> updateIntercityRoute(String routeId, Map<String, dynamic> routeData) async {
    await FirebaseFirestore.instance.collection('intercity_routes').doc(routeId).update({
      ...routeData,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete intercity route
  Future<void> deleteIntercityRoute(String routeId) async {
    await FirebaseFirestore.instance.collection('intercity_routes').doc(routeId).delete();
  }

  /// Stream dynamic intercity vehicles configured by Admin
  Stream<List<Map<String, dynamic>>> streamIntercityVehicles() {
    return FirebaseFirestore.instance
        .collection('intercity_vehicles')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
        });
  }

  /// Add new intercity vehicle type
  Future<String> addIntercityVehicle(Map<String, dynamic> vehicleData) async {
    final docRef = await FirebaseFirestore.instance.collection('intercity_vehicles').add({
      ...vehicleData,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Update existing vehicle type
  Future<void> updateIntercityVehicle(String vehicleId, Map<String, dynamic> vehicleData) async {
    await FirebaseFirestore.instance.collection('intercity_vehicles').doc(vehicleId).update({
      ...vehicleData,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete vehicle type
  Future<void> deleteIntercityVehicle(String vehicleId) async {
    await FirebaseFirestore.instance.collection('intercity_vehicles').doc(vehicleId).delete();
  }

  /// Seed initial default routes and vehicle types into Firestore if empty
  Future<void> seedDefaultIntercityRoutesAndVehicles() async {
    final routesColl = FirebaseFirestore.instance.collection('intercity_routes');
    final vehiclesColl = FirebaseFirestore.instance.collection('intercity_vehicles');

    final existingVehicles = await vehiclesColl.limit(1).get();
    if (existingVehicles.docs.isEmpty) {
      final defaultVehicles = [
        {
          'key': 'AC Sedan Car',
          'title': 'AC Sedan (Corolla / Yaris / City)',
          'subtitle': 'Air Conditioned, Trunk for Luggage, Up to 4 Pax',
          'capacity': 4,
        },
        {
          'key': 'Economy Car',
          'title': 'Economy Car (Alto / Cultus / WagonR)',
          'subtitle': 'Budget Intercity Travel, Up to 3-4 Pax',
          'capacity': 4,
        },
        {
          'key': 'Bike / Express',
          'title': 'Motorbike / Express Courier',
          'subtitle': 'Fast Solo Passenger or Urgent Parcels',
          'capacity': 1,
        },
        {
          'key': 'HiAce / 7-Seater',
          'title': 'HiAce / APV / Grand Cabin',
          'subtitle': 'Group & Family Travel, Heavy Luggage, 7-12 Pax',
          'capacity': 8,
        },
      ];
      for (final v in defaultVehicles) {
        await vehiclesColl.add({...v, 'createdAt': FieldValue.serverTimestamp()});
      }
    }

    final existingRoutes = await routesColl.limit(1).get();
    if (existingRoutes.docs.isEmpty) {
      final defaultRoutes = [
        {
          'from': 'Bannu',
          'to': 'Peshawar',
          'distanceKm': 180,
          'durationText': '3.5 Hours',
          'baseFares': {
            'AC Sedan Car': 6500,
            'Economy Car': 5000,
            'Bike / Express': 2800,
            'HiAce / 7-Seater': 9500,
          },
        },
        {
          'from': 'Bannu',
          'to': 'Islamabad / Rawalpindi',
          'distanceKm': 350,
          'durationText': '5.5 Hours (Motorway/CPEC)',
          'baseFares': {
            'AC Sedan Car': 12000,
            'Economy Car': 9500,
            'Bike / Express': 5500,
            'HiAce / 7-Seater': 16500,
          },
        },
        {
          'from': 'Islamabad / Rawalpindi',
          'to': 'Bannu',
          'distanceKm': 350,
          'durationText': '5.5 Hours (Motorway/CPEC)',
          'baseFares': {
            'AC Sedan Car': 12000,
            'Economy Car': 9500,
            'Bike / Express': 5500,
            'HiAce / 7-Seater': 16500,
          },
        },
        {
          'from': 'Peshawar',
          'to': 'Bannu',
          'distanceKm': 180,
          'durationText': '3.5 Hours',
          'baseFares': {
            'AC Sedan Car': 6500,
            'Economy Car': 5000,
            'Bike / Express': 2800,
            'HiAce / 7-Seater': 9500,
          },
        },
        {
          'from': 'Bannu',
          'to': 'Dera Ismail Khan',
          'distanceKm': 140,
          'durationText': '2.5 Hours',
          'baseFares': {
            'AC Sedan Car': 5000,
            'Economy Car': 4000,
            'Bike / Express': 2200,
            'HiAce / 7-Seater': 7500,
          },
        },
        {
          'from': 'Dera Ismail Khan',
          'to': 'Bannu',
          'distanceKm': 140,
          'durationText': '2.5 Hours',
          'baseFares': {
            'AC Sedan Car': 5000,
            'Economy Car': 4000,
            'Bike / Express': 2200,
            'HiAce / 7-Seater': 7500,
          },
        },
        {
          'from': 'Bannu',
          'to': 'Kohat',
          'distanceKm': 115,
          'durationText': '2.0 Hours',
          'baseFares': {
            'AC Sedan Car': 4200,
            'Economy Car': 3400,
            'Bike / Express': 1800,
            'HiAce / 7-Seater': 6200,
          },
        },
      ];
      for (final r in defaultRoutes) {
        await routesColl.add({...r, 'createdAt': FieldValue.serverTimestamp()});
      }
    }
  }

  /// 28. Stream assigned intercity bookings for a specific rider
  Stream<List<Map<String, dynamic>>> streamRiderIntercityBookings(String riderId) {
    return FirebaseFirestore.instance
        .collection('intercity_bookings')
        .where('riderId', isEqualTo: riderId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
          list.sort((a, b) {
            final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });
          return list;
        });
  }
}
