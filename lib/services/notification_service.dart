import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/incoming_ride_screen.dart';

/// Top-level background message handler for FCM (invoked by OS in background and terminated states)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM Background message received: ${message.messageId}, data: ${message.data}');

  final type = message.data['type'];
  final rideId = message.data['ride_request_id'] ?? message.data['rideId'];

  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
  await localNotifications.initialize(initSettings);

  final androidPlugin = localNotifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin != null) {
    await androidPlugin.createNotificationChannel(NotificationService.rideRequestChannel);
  }

  if (type == 'NEW_RIDE_REQUEST' && rideId != null) {
    final fare = message.data['estimated_fare'] ?? '300';
    final pickup = message.data['pickup_address'] ?? 'Nearby Pickup';
    final drop = message.data['drop_address'] ?? 'Destination';
    final distKm = message.data['distance_km'] ?? '2.0';
    final notifId = (rideId.hashCode.abs()) % 1000000;

    final androidDetails = AndroidNotificationDetails(
      NotificationService.rideRequestChannel.id,
      NotificationService.rideRequestChannel.name,
      channelDescription: NotificationService.rideRequestChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('ride_request'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1500]),
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFF4C20D),
      styleInformation: BigTextStyleInformation(
        'Pickup: $pickup\nDestination: $drop\nFare: PKR $fare (Cash) • $distKm km\nTap to view and accept.',
      ),
    );

    await localNotifications.show(
      notifId,
      'NEW RIDE REQUEST! (PKR $fare)',
      'A passenger nearby is requesting a ride. Tap to view and accept.',
      NotificationDetails(android: androidDetails),
      payload: rideId,
    );
  } else if ((type == 'RIDE_CANCELLED' || type == 'RIDE_NO_LONGER_AVAILABLE') && rideId != null) {
    final notifId = (rideId.hashCode.abs()) % 1000000;
    await localNotifications.cancel(notifId);
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  /// Global navigator key for notification click routing from any app state
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Stream for foreground incoming ride alerts
  static final StreamController<Map<String, dynamic>> incomingRideStream =
      StreamController<Map<String, dynamic>>.broadcast();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// Standard app alert channel
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'shango_high_importance_channel',
    'ShanGo Ride & Trip Alerts',
    description: 'High priority push alerts for bookings, assignments, and account status.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Dedicated high-priority ride requests notification channel with custom sound & strong vibration
  static final AndroidNotificationChannel rideRequestChannel = AndroidNotificationChannel(
    'shango_ride_requests',
    'Shango Ride Requests',
    description: 'Urgent incoming passenger ride requests with high priority alert sound and vibration.',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('ride_request'),
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1500]),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  );

  bool _isInitialized = false;
  StreamSubscription? _liveNotifSub;
  final Set<String> _shownNotificationIds = {};

  /// Route user directly to IncomingRideRequestScreen when notification is clicked
  static void navigateToIncomingRide(String rideId) {
    if (rideId.isEmpty) return;
    final nav = navigatorKey?.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => IncomingRideRequestScreen(rideId: rideId),
        ),
      );
    }
  }

  /// Initialize Push Notifications (FCM + Flutter Local Notifications)
  Future<void> initialize({GlobalKey<NavigatorState>? navKey}) async {
    if (navKey != null) {
      navigatorKey = navKey;
    }
    if (_isInitialized) return;

    try {
      // 1. Request Push Notification permissions (Android 13+ & iOS)
      final settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );
      debugPrint('FCM Notification permission status: ${settings.authorizationStatus}');

      // 2. Setup Android & iOS local notification settings
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notification clicked with payload: ${response.payload}');
          if (response.payload != null && response.payload!.isNotEmpty) {
            navigateToIncomingRide(response.payload!);
          }
        },
      );

      // 3. Create high importance Android notification channels and request permission
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(_channel);
        await androidPlugin.createNotificationChannel(rideRequestChannel);
        await androidPlugin.requestNotificationsPermission();
        await androidPlugin.requestFullScreenIntentPermission();
      }

      // 4. Foreground FCM message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final type = message.data['type'];
        final rideId = message.data['ride_request_id'] ?? message.data['rideId'];

        if (type == 'NEW_RIDE_REQUEST' && rideId != null) {
          // Broadcast to active UI
          incomingRideStream.add(message.data);

          // Show heads-up notification with custom sound
          showRideRequestNotification(
            rideId: rideId,
            fare: message.data['estimated_fare'] ?? '300',
            pickup: message.data['pickup_address'] ?? 'Nearby Pickup',
            drop: message.data['drop_address'] ?? 'Destination',
            distanceKm: message.data['distance_km'] ?? '2.0',
          );
        } else if ((type == 'RIDE_CANCELLED' || type == 'RIDE_NO_LONGER_AVAILABLE') && rideId != null) {
          cancelRideNotification(rideId);
          incomingRideStream.add({'type': type, 'rideId': rideId});
        } else {
          final notification = message.notification;
          if (notification != null) {
            showLocalNotification(
              title: notification.title ?? 'ShanGo Alert',
              body: notification.body ?? '',
              payload: message.data['referenceId'] ?? message.data['ride_request_id'],
            );
          }
        }
      });

      // 5. Setup top-level background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 6. Monitor Token refresh
      _fcm.onTokenRefresh.listen((newToken) {
        final curUid = FirebaseAuth.instance.currentUser?.uid;
        if (curUid != null) {
          saveUserFcmToken(curUid, customToken: newToken);
        }
      });

      // 7. Handle notification tap when app was opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final rideId = message.data['ride_request_id'] ?? message.data['rideId'] ?? message.data['referenceId'];
        if (rideId != null) {
          navigateToIncomingRide(rideId);
        }
      });

      // 8. Handle notification tap when app was launched from terminated state via FCM
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        final rideId = initialMessage.data['ride_request_id'] ?? initialMessage.data['rideId'] ?? initialMessage.data['referenceId'];
        if (rideId != null) {
          Future.delayed(const Duration(milliseconds: 700), () => navigateToIncomingRide(rideId));
        }
      }

      // 9. Handle notification tap when app was launched from terminated state via local notification
      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final payload = launchDetails.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 700), () => navigateToIncomingRide(payload));
        }
      }

      _isInitialized = true;
      debugPrint('NotificationService initialized successfully with Push Channels & Ride Alert Audio!');
    } catch (e) {
      debugPrint('NotificationService initialization error: $e');
    }
  }

  /// Show dedicated high-priority incoming ride alert notification with custom sound
  Future<void> showRideRequestNotification({
    required String rideId,
    required String fare,
    required String pickup,
    required String drop,
    required String distanceKm,
  }) async {
    try {
      final notifId = (rideId.hashCode.abs()) % 1000000;
      final androidDetails = AndroidNotificationDetails(
        rideRequestChannel.id,
        rideRequestChannel.name,
        channelDescription: rideRequestChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('ride_request'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1500]),
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFFF4C20D),
        styleInformation: BigTextStyleInformation(
          'Pickup: $pickup\nDestination: $drop\nFare: PKR $fare (Cash) • $distanceKm km\nTap to view and accept.',
        ),
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
          sound: 'ride_request.wav',
        ),
      );

      await _localNotifications.show(
        notifId,
        'NEW RIDE REQUEST! (PKR $fare)',
        'A passenger nearby is requesting a ride. Tap to view and accept.',
        details,
        payload: rideId,
      );
    } catch (e) {
      debugPrint('Error displaying incoming ride notification: $e');
    }
  }

  /// Cancel active notification for a specific ride
  Future<void> cancelRideNotification(String rideId) async {
    try {
      final notifId = (rideId.hashCode.abs()) % 1000000;
      await _localNotifications.cancel(notifId);
    } catch (e) {
      debugPrint('Error cancelling ride notification: $e');
    }
  }

  /// Save FCM Device Token to Firestore users and online_riders collections
  Future<void> saveUserFcmToken(String uid, {String? customToken}) async {
    try {
      final token = customToken ?? await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        final batch = _firestore.batch();
        batch.set(
          _firestore.collection('users').doc(uid),
          {
            'fcmToken': token,
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        batch.set(
          _firestore.collection('online_riders').doc(uid),
          {
            'fcmToken': token,
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        await batch.commit();
        debugPrint('Saved FCM Token for user & online rider $uid: $token');
      }
    } catch (e) {
      debugPrint('Error saving FCM Token: $e');
    }
  }

  /// Show instant native status bar notification banner on device
  Future<void> showLocalNotification({
    int? id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final notifId = id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000);
      final androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(body),
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _localNotifications.show(
        notifId,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error displaying local status bar notification: $e');
    }
  }

  /// Start live listener for instant status bar popups when new notifications are written to Firestore
  void startLiveNotificationListener(String uid, {bool isAdmin = false}) {
    _liveNotifSub?.cancel();
    final stream = isAdmin ? streamAdminNotifications() : streamUserNotifications(uid);
    final initTime = DateTime.now().subtract(const Duration(seconds: 10));

    _liveNotifSub = stream.listen((notifs) {
      for (final n in notifs) {
        final id = n['id'] as String?;
        final isRead = n['isRead'] == true;
        final createdAt = (n['createdAt'] as Timestamp?)?.toDate();

        if (id != null && !isRead && !_shownNotificationIds.contains(id)) {
          _shownNotificationIds.add(id);
          // Only pop up status bar if notification is newly created
          if (createdAt == null || createdAt.isAfter(initTime)) {
            showLocalNotification(
              title: n['title'] ?? 'ShanGo Alert',
              body: n['body'] ?? '',
              payload: n['referenceId'],
            );
          }
        }
      }
    });
  }

  /// Stop live notification listener
  void stopLiveNotificationListener() {
    _liveNotifSub?.cancel();
    _liveNotifSub = null;
  }

  // =========================================================================
  // FIRESTORE STREAMS & DATA METHODS
  // =========================================================================

  /// 1. Stream all notifications for a specific user sorted newest first
  Stream<List<Map<String, dynamic>>> streamUserNotifications(String uid) {
    return _firestore
        .collection('notifications')
        .where('recipientUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      list.sort((a, b) {
        final tA = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2020);
        final tB = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2020);
        return tB.compareTo(tA);
      });
      return list;
    });
  }

  /// 2. Stream unread count for badge indicators
  Stream<int> streamUnreadCount(String uid) {
    return _firestore
        .collection('notifications')
        .where('recipientUid', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// 2b. Stream admin unread count
  Stream<int> streamAdminUnreadCount() {
    return _firestore
        .collection('notifications')
        .where('recipientRole', isEqualTo: 'admin')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// 3. Stream admin notifications
  Stream<List<Map<String, dynamic>>> streamAdminNotifications() {
    return _firestore
        .collection('notifications')
        .where('recipientRole', isEqualTo: 'admin')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      list.sort((a, b) {
        final tA = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2020);
        final tB = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2020);
        return tB.compareTo(tA);
      });
      return list;
    });
  }

  /// 4. Core send notification method
  Future<void> sendNotification({
    required String recipientUid,
    required String recipientRole, // 'rider', 'customer', 'admin'
    required String title,
    required String body,
    required String type, // 'trip_assigned', 'trip_confirmed', 'price_offer', 'role_switch', 'account_approved', 'general'
    String? referenceId,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'recipientUid': recipientUid,
        'recipientRole': recipientRole,
        'title': title,
        'body': body,
        'type': type,
        'referenceId': referenceId,
        'extraData': extraData ?? {},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }

  /// 5. Mark single notification as read
  Future<void> markAsRead(String notifId) async {
    try {
      await _firestore.collection('notifications').doc(notifId).update({'isRead': true});
    } catch (e) {
      debugPrint('Error marking notification read: $e');
    }
  }

  /// 6. Mark all notifications as read for a user or admin
  Future<void> markAllAsRead(String uid, {bool isAdmin = false}) async {
    try {
      final query = isAdmin
          ? await _firestore
              .collection('notifications')
              .where('recipientRole', isEqualTo: 'admin')
              .where('isRead', isEqualTo: false)
              .get()
          : await _firestore
              .collection('notifications')
              .where('recipientUid', isEqualTo: uid)
              .where('isRead', isEqualTo: false)
              .get();

      final batch = _firestore.batch();
      for (final doc in query.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error marking all notifications read: $e');
    }
  }

  // =========================================================================
  // HELPER TRIGGER METHODS FOR DRIVERS, PASSENGERS & ADMIN
  // =========================================================================

  /// Notify Driver: Scheduled Trip Assigned with Route, Fare, Commission & Net Payout
  Future<void> notifyDriverTripAssigned({
    required String driverUid,
    required String fromCity,
    required String toCity,
    required String date,
    required String time,
    required int fare,
    required double commissionPercent,
    required String bookingId,
    String? customerName,
    String? customerPhone,
  }) async {
    final double commAmount = fare * (commissionPercent / 100);
    final double netPayout = fare - commAmount;

    final title = '📅 New Scheduled Trip: $fromCity ➔ $toCity';
    final body = 'Departure: $date at $time\n'
        '• Total Fare: PKR $fare\n'
        '${commissionPercent <= 0 ? "• ShanGo Fee: PKR 0 (0% Promo - Zero Commission)" : "• ShanGo Fee (${commissionPercent.toInt()}%): PKR ${commAmount.toStringAsFixed(0)}"}\n'
        '• Your Net Earnings: PKR ${netPayout.toStringAsFixed(0)}\n'
        '${customerName != null ? "• Passenger: $customerName ($customerPhone)" : ""}';

    await sendNotification(
      recipientUid: driverUid,
      recipientRole: 'rider',
      title: title,
      body: body,
      type: 'trip_assigned',
      referenceId: bookingId,
      extraData: {
        'fromCity': fromCity,
        'toCity': toCity,
        'fare': fare,
        'commissionPercent': commissionPercent,
        'netPayout': netPayout,
        'bookingId': bookingId,
      },
    );
  }

  /// Notify Passenger: Driver Assigned & Trip Confirmed
  Future<void> notifyPassengerTripConfirmed({
    required String passengerUid,
    required String driverName,
    required String driverPhone,
    required String fromCity,
    required String toCity,
    required int fare,
    required String bookingId,
  }) async {
    final title = '🚖 Trip Confirmed: $fromCity ➔ $toCity';
    final body = 'Driver $driverName ($driverPhone) has been assigned for your journey.\nConfirmed Fare: PKR $fare.';

    await sendNotification(
      recipientUid: passengerUid,
      recipientRole: 'customer',
      title: title,
      body: body,
      type: 'trip_confirmed',
      referenceId: bookingId,
      extraData: {
        'fromCity': fromCity,
        'toCity': toCity,
        'fare': fare,
        'driverName': driverName,
        'driverPhone': driverPhone,
      },
    );
  }

  /// Notify Passenger: Admin Countered Price Offer
  Future<void> notifyPassengerCounterOffer({
    required String passengerUid,
    required int counterFare,
    required String fromCity,
    required String toCity,
    required String bookingId,
    String? adminMessage,
  }) async {
    final title = '🏷️ Price Offer: PKR $counterFare for $fromCity ➔ $toCity';
    final body = 'Admin proposed PKR $counterFare for your route.${adminMessage != null && adminMessage.isNotEmpty ? "\nNote: \"$adminMessage\"" : "\nOpen City to City to accept or decline."}';

    await sendNotification(
      recipientUid: passengerUid,
      recipientRole: 'customer',
      title: title,
      body: body,
      type: 'price_offer',
      referenceId: bookingId,
      extraData: {
        'counterFare': counterFare,
        'fromCity': fromCity,
        'toCity': toCity,
      },
    );
  }

  /// Notify Driver: Account Approved
  Future<void> notifyDriverAccountApproved({
    required String driverUid,
    required String driverName,
  }) async {
    final title = '🎉 Driver Account Approved!';
    final body = 'Hello $driverName, your ShanGo Driver Partner account is now verified. You can go online to receive rides and scheduled intercity trips.';

    await sendNotification(
      recipientUid: driverUid,
      recipientRole: 'rider',
      title: title,
      body: body,
      type: 'account_approved',
    );
  }

  /// Notify User: Role Switch Approved
  Future<void> notifyUserSwitchApproved({
    required String uid,
    required String newRole,
  }) async {
    final roleName = newRole == 'rider' ? 'Driver Partner' : 'Passenger';
    final title = '🔄 Account Switch Approved!';
    final body = 'Your request to switch to $roleName account has been approved by ShanGo Admin.';

    await sendNotification(
      recipientUid: uid,
      recipientRole: newRole,
      title: title,
      body: body,
      type: 'role_switch',
    );
  }

  /// Notify Admin: New Driver Registration Pending Verification
  Future<void> notifyAdminNewDriverRegistered({
    required String driverName,
    required String vehicleModel,
    required String driverPhone,
    required String uid,
  }) async {
    final title = '📝 New Driver Registration: $driverName';
    final body = 'Driver $driverName ($driverPhone) registered with $vehicleModel. Verification required in Admin Panel.';

    await sendNotification(
      recipientUid: 'admin',
      recipientRole: 'admin',
      title: title,
      body: body,
      type: 'driver_registered',
      referenceId: uid,
    );
  }

  /// Notify Admin: Role Switch Request Submitted
  Future<void> notifyAdminRoleSwitchRequest({
    required String userName,
    required String requestedRole,
    required String uid,
  }) async {
    final targetName = requestedRole == 'rider' ? 'Driver' : 'Passenger';
    final title = '🔄 Switch Request: $userName ➔ $targetName';
    final body = '$userName has applied to switch their account to $targetName mode. Review in Admin Console.';

    await sendNotification(
      recipientUid: 'admin',
      recipientRole: 'admin',
      title: title,
      body: body,
      type: 'role_switch_request',
      referenceId: uid,
    );
  }

  /// Notify Admin: New Intercity Booking Request Submitted
  Future<void> notifyAdminNewIntercityBooking({
    required String passengerName,
    required String fromCity,
    required String toCity,
    required int fare,
    required String bookingId,
  }) async {
    final title = '🛣️ New Booking: $fromCity ➔ $toCity';
    final body = '$passengerName requested an on-demand ride ($fromCity ➔ $toCity) for PKR $fare. Driver assignment needed.';

    await sendNotification(
      recipientUid: 'admin',
      recipientRole: 'admin',
      title: title,
      body: body,
      type: 'intercity_booking',
      referenceId: bookingId,
    );
  }

  /// D3: Notify User (Driver or Passenger): Promoted to Admin or Admin Revoked
  Future<void> notifyUserAdminStatusChanged({
    required String uid,
    required bool isAdmin,
    String? role,
  }) async {
    final title = isAdmin ? '👑 Promoted to Admin!' : '🛡️ Admin Access Updated';
    final body = isAdmin
        ? 'You have been granted Admin privileges by ShanGo Management. You can now access the Admin Console and manage rides.'
        : 'Your Admin privileges have been revoked by ShanGo Management.';

    await sendNotification(
      recipientUid: uid,
      recipientRole: role ?? 'customer',
      title: title,
      body: body,
      type: 'admin_status',
    );
  }

  /// D4: Notify User: Account Suspended or Reactivated
  Future<void> notifyUserAccountSuspension({
    required String uid,
    required bool isSuspended,
    String? reason,
    String? role,
  }) async {
    final title = isSuspended ? '🚫 Account Suspended' : '✅ Account Reactivated';
    final body = isSuspended
        ? 'Your ShanGo account has been suspended by Admin.${reason != null && reason.isNotEmpty ? " Reason: $reason" : " Contact support for details."}'
        : 'Your ShanGo account has been reactivated! You can now use all services normally.';

    await sendNotification(
      recipientUid: uid,
      recipientRole: role ?? 'customer',
      title: title,
      body: body,
      type: 'account_suspension',
    );
  }

  /// P3: Notify Passenger: Price Offer Accepted by Admin
  Future<void> notifyPassengerPriceAccepted({
    required String passengerUid,
    required String fromCity,
    required String toCity,
    required int acceptedFare,
    required String bookingId,
  }) async {
    final title = '✅ Price Offer Accepted: PKR $acceptedFare!';
    final body = 'Admin has accepted your offered fare of PKR $acceptedFare for $fromCity ➔ $toCity. Driver is being assigned now.';

    await sendNotification(
      recipientUid: passengerUid,
      recipientRole: 'customer',
      title: title,
      body: body,
      type: 'price_accepted',
      referenceId: bookingId,
      extraData: {
        'fromCity': fromCity,
        'toCity': toCity,
        'fare': acceptedFare,
      },
    );
  }

  /// A5: Notify Parties & Admin: Trip Cancelled
  Future<void> notifyTripCancelled({
    required String fromCity,
    required String toCity,
    required String cancelledBy,
    String? passengerUid,
    String? driverUid,
    String? bookingId,
    String? reason,
  }) async {
    final title = '⚠️ Trip Cancelled: $fromCity ➔ $toCity';
    final body = 'Trip ($fromCity ➔ $toCity) was cancelled by $cancelledBy.${reason != null && reason.isNotEmpty ? " Reason: $reason" : ""}';

    // 1. Notify Admin
    await sendNotification(
      recipientUid: 'admin',
      recipientRole: 'admin',
      title: title,
      body: body,
      type: 'trip_cancelled',
      referenceId: bookingId,
    );

    // 2. Notify Passenger if driver cancelled
    if (passengerUid != null && passengerUid.isNotEmpty && cancelledBy != 'Passenger') {
      await sendNotification(
        recipientUid: passengerUid,
        recipientRole: 'customer',
        title: title,
        body: 'Your scheduled trip from $fromCity to $toCity was cancelled. We are arranging another driver for you.',
        type: 'trip_cancelled',
        referenceId: bookingId,
      );
    }

    // 3. Notify Driver if passenger cancelled
    if (driverUid != null && driverUid.isNotEmpty && cancelledBy != 'Driver') {
      await sendNotification(
        recipientUid: driverUid,
        recipientRole: 'rider',
        title: title,
        body: 'Scheduled trip ($fromCity ➔ $toCity) was cancelled by the passenger. You are now free for other trips.',
        type: 'trip_cancelled',
        referenceId: bookingId,
      );
    }
  }
}
