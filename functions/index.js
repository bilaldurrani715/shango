const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// Maximum dispatch radius in kilometers (7 km)
const MAX_RADIUS_KM = 7.0;
// Maximum request validity in seconds (90s matching passenger searching screen)
const RIDE_TTL_SECONDS = 90;

/**
 * Calculates Haversine distance between two GPS coordinates in kilometers
 */
function calculateDistanceKm(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth radius in km
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * 1. TRIGGER: On New Ride Request Created in Firestore (`rides/{rideId}`)
 * Identifies eligible online nearby riders and sends high-priority FCM notifications.
 */
exports.onRideCreated = functions.firestore
  .document('rides/{rideId}')
  .onCreate(async (snap, context) => {
    const rideId = context.params.rideId;
    const rideData = snap.data();

    // Verify ride is in requested state
    if (!rideData || rideData.status !== 'requested') {
      console.log(`[onRideCreated] Ride ${rideId} is not in requested status. Skipping dispatch.`);
      return null;
    }

    const pickupLat = parseFloat(rideData.pickupLat);
    const pickupLng = parseFloat(rideData.pickupLng);

    if (isNaN(pickupLat) || isNaN(pickupLng)) {
      console.error(`[onRideCreated] Ride ${rideId} has invalid pickup coordinates (${rideData.pickupLat}, ${rideData.pickupLng}).`);
      return null;
    }

    console.log(`[onRideCreated] Processing dispatch for Ride ${rideId} at pickup (${pickupLat}, ${pickupLng})`);

    try {
      // 1. Fetch all online riders from online_riders collection
      const onlineSnap = await db.collection('online_riders')
        .where('isOnline', '==', true)
        .get();

      if (onlineSnap.empty) {
        console.log(`[onRideCreated] No online riders found in system for Ride ${rideId}.`);
        return null;
      }

      const eligibleTokens = [];
      const eligibleRiderUids = [];
      const tokenToUidMap = {};

      const now = Date.now();
      const MAX_PING_AGE_MS = 45 * 60 * 1000; // 45 minutes freshness tolerance

      for (const doc of onlineSnap.docs) {
        const data = doc.data();
        const uid = doc.id;

        // Check if rider is currently on an active trip
        if (data.isOnTrip === true) {
          console.log(`[onRideCreated] Rider ${uid} is currently on an active trip. Skipping.`);
          continue;
        }

        // Check last ping freshness
        if (data.updatedAt) {
          const lastPing = data.updatedAt.toDate ? data.updatedAt.toDate().getTime() : 0;
          if (now - lastPing > MAX_PING_AGE_MS) {
            console.log(`[onRideCreated] Rider ${uid} ping is stale (> 45m). Skipping.`);
            continue;
          }
        }

        const riderLat = parseFloat(data.lat);
        const riderLng = parseFloat(data.lng);

        if (isNaN(riderLat) || isNaN(riderLng)) {
          continue;
        }

        // Calculate distance to pickup
        const distKm = calculateDistanceKm(pickupLat, pickupLng, riderLat, riderLng);
        if (distKm > MAX_RADIUS_KM) {
          console.log(`[onRideCreated] Rider ${uid} is ${distKm.toFixed(2)} km away (> ${MAX_RADIUS_KM} km limit). Skipping.`);
          continue;
        }

        // 2. Verify rider account status in users collection
        const userDoc = await db.collection('users').doc(uid).get();
        if (!userDoc.exists) continue;

        const userData = userDoc.data();
        if (userData.isSuspended === true) {
          console.log(`[onRideCreated] Rider ${uid} is suspended. Skipping.`);
          continue;
        }
        if (userData.isApproved === false) {
          console.log(`[onRideCreated] Rider ${uid} is not approved. Skipping.`);
          continue;
        }

        // Collect FCM Token
        const token = data.fcmToken || userData.fcmToken;
        if (token && typeof token === 'string' && token.length > 20) {
          if (!eligibleTokens.includes(token)) {
            eligibleTokens.push(token);
            eligibleRiderUids.push(uid);
            tokenToUidMap[token] = uid;
          }
        }
      }

      console.log(`[onRideCreated] Found ${eligibleTokens.length} eligible online riders for Ride ${rideId}.`);

      if (eligibleTokens.length === 0) {
        return null;
      }

      const estimatedFare = String(Math.round(rideData.estimatedFare || 300));
      const pickupAddress = String(rideData.pickupAddress || 'Nearby Pickup');
      const dropAddress = String(rideData.dropAddress || 'Destination');
      const distanceKm = String((rideData.distanceKm || 2.0).toFixed(1));
      const customerName = String(rideData.customerName || 'Passenger');
      const expiresAt = String(Date.now() + (RIDE_TTL_SECONDS * 1000));

      // 3. Construct high-priority FCM Multicast message
      const message = {
        tokens: eligibleTokens,
        android: {
          priority: 'high',
          ttl: RIDE_TTL_SECONDS * 1000,
          notification: {
            channelId: 'shango_ride_requests',
            sound: 'ride_request',
            tag: `ride_${rideId}`,
            title: `NEW RIDE REQUEST! (PKR ${estimatedFare})`,
            body: `A passenger nearby is requesting a ride. Tap to view and accept.`,
            icon: 'ic_launcher',
            color: '#F4C20D',
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          },
          data: {
            type: 'NEW_RIDE_REQUEST',
            ride_request_id: rideId,
            pickup_address: pickupAddress,
            drop_address: dropAddress,
            pickup_latitude: String(pickupLat),
            pickup_longitude: String(pickupLng),
            drop_latitude: String(rideData.dropLat || ''),
            drop_longitude: String(rideData.dropLng || ''),
            estimated_fare: estimatedFare,
            distance_km: distanceKm,
            customer_name: customerName,
            customer_phone: String(rideData.customerPhone || ''),
            expires_at: expiresAt,
          },
        },
        data: {
          type: 'NEW_RIDE_REQUEST',
          ride_request_id: rideId,
          pickup_address: pickupAddress,
          drop_address: dropAddress,
          pickup_latitude: String(pickupLat),
          pickup_longitude: String(pickupLng),
          drop_latitude: String(rideData.dropLat || ''),
          drop_longitude: String(rideData.dropLng || ''),
          estimated_fare: estimatedFare,
          distance_km: distanceKm,
          customer_name: customerName,
          customer_phone: String(rideData.customerPhone || ''),
          expires_at: expiresAt,
        },
      };

      // 4. Send Multicast via Firebase Admin SDK
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(`[onRideCreated] FCM Multicast for Ride ${rideId}: ${response.successCount} succeeded, ${response.failureCount} failed.`);

      // 5. Handle invalid or expired FCM tokens (cleanup from Firestore)
      if (response.failureCount > 0) {
        const batch = db.batch();
        let invalidCount = 0;

        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const errCode = resp.error ? resp.error.code : 'unknown';
            const badToken = eligibleTokens[idx];
            const uid = tokenToUidMap[badToken];

            console.warn(`[onRideCreated] FCM failure for rider ${uid} (token: ${badToken.slice(0, 10)}...): ${errCode}`);

            if (
              errCode === 'messaging/invalid-registration-token' ||
              errCode === 'messaging/registration-token-not-registered'
            ) {
              if (uid) {
                batch.update(db.collection('users').doc(uid), {
                  fcmToken: admin.firestore.FieldValue.delete(),
                });
                batch.update(db.collection('online_riders').doc(uid), {
                  fcmToken: admin.firestore.FieldValue.delete(),
                });
                invalidCount++;
              }
            }
          }
        });

        if (invalidCount > 0) {
          await batch.commit();
          console.log(`[onRideCreated] Cleaned up ${invalidCount} invalid FCM tokens from Firestore.`);
        }
      }

      // Record dispatched riders in ride document
      await snap.ref.update({
        dispatchedRidersCount: response.successCount,
        dispatchedAt: admin.firestore.FieldValue.serverTimestamp(),
        dispatchedRiderUids: eligibleRiderUids,
      });

      return null;
    } catch (err) {
      console.error(`[onRideCreated] Error dispatching ride request ${rideId}:`, err);
      return null;
    }
  });

/**
 * 2. TRIGGER: On Ride Document Updated (`rides/{rideId}`)
 * When a ride is accepted by one driver or cancelled, notify all other drivers to cancel/dismiss their alerts.
 */
exports.onRideUpdated = functions.firestore
  .document('rides/{rideId}')
  .onUpdate(async (change, context) => {
    const rideId = context.params.rideId;
    const beforeData = change.before.data();
    const afterData = change.after.data();

    // Check if status transitioned from 'requested' to 'accepted'
    if (beforeData.status === 'requested' && afterData.status === 'accepted') {
      const acceptedRiderId = afterData.riderId;
      console.log(`[onRideUpdated] Ride ${rideId} was ACCEPTED by rider ${acceptedRiderId}. Notifying other riders to dismiss alerts.`);

      try {
        // Query other online riders who might have received the notification
        const onlineSnap = await db.collection('online_riders')
          .where('isOnline', '==', true)
          .get();

        const tokensToNotify = [];
        for (const doc of onlineSnap.docs) {
          if (doc.id === acceptedRiderId) continue; // Skip the driver who accepted
          const data = doc.data();
          if (data.fcmToken) {
            tokensToNotify.push(data.fcmToken);
          }
        }

        if (tokensToNotify.length > 0) {
          const cancelMessage = {
            tokens: tokensToNotify,
            android: {
              priority: 'high',
              data: {
                type: 'RIDE_NO_LONGER_AVAILABLE',
                ride_request_id: rideId,
                reason: 'accepted_by_other',
                accepted_by: acceptedRiderId || '',
              },
            },
            data: {
              type: 'RIDE_NO_LONGER_AVAILABLE',
              ride_request_id: rideId,
              reason: 'accepted_by_other',
              accepted_by: acceptedRiderId || '',
            },
          };

          const cancelResp = await admin.messaging().sendEachForMulticast(cancelMessage);
          console.log(`[onRideUpdated] Sent RIDE_NO_LONGER_AVAILABLE to ${cancelResp.successCount} other riders.`);
        }
      } catch (err) {
        console.error(`[onRideUpdated] Error sending ride accepted cancellation:`, err);
      }
    }

    // Check if status transitioned to 'cancelled'
    if (beforeData.status === 'requested' && afterData.status === 'cancelled') {
      console.log(`[onRideUpdated] Ride ${rideId} was CANCELLED by passenger. Notifying riders to dismiss alerts.`);

      try {
        const onlineSnap = await db.collection('online_riders')
          .where('isOnline', '==', true)
          .get();

        const tokensToNotify = [];
        for (const doc of onlineSnap.docs) {
          const data = doc.data();
          if (data.fcmToken) tokensToNotify.push(data.fcmToken);
        }

        if (tokensToNotify.length > 0) {
          const cancelMessage = {
            tokens: tokensToNotify,
            android: {
              priority: 'high',
              data: {
                type: 'RIDE_CANCELLED',
                ride_request_id: rideId,
                reason: 'passenger_cancelled',
              },
            },
            data: {
              type: 'RIDE_CANCELLED',
              ride_request_id: rideId,
              reason: 'passenger_cancelled',
            },
          };
          await admin.messaging().sendEachForMulticast(cancelMessage);
        }
      } catch (err) {
        console.error(`[onRideUpdated] Error sending ride cancelled notification:`, err);
      }
    }

    return null;
  });

/**
 * 3. HTTPS CALLABLE: Server-Authoritative Atomic Ride Acceptance
 * Guaranteed concurrency safety: Only ONE rider can accept a particular ride.
 */
exports.acceptRide = functions.https.onCall(async (data, context) => {
  // 1. Verify caller authentication
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'You must be logged in as an authorized driver to accept rides.'
    );
  }

  const riderUid = context.auth.uid;
  const rideId = data.rideId;
  const riderLocation = data.riderLocation || {};

  if (!rideId) {
    throw new functions.https.HttpsError('invalid-argument', 'rideId parameter is required.');
  }

  // 2. Fetch driver profile from Firestore
  const userDoc = await db.collection('users').doc(riderUid).get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Driver account not found.');
  }
  const userData = userDoc.data();
  if (userData.isSuspended === true) {
    throw new functions.https.HttpsError('permission-denied', 'Your driver account has been suspended.');
  }
  if (userData.isApproved === false) {
    throw new functions.https.HttpsError('permission-denied', 'Your driver account is pending approval.');
  }

  const riderName = userData.name || userData.displayName || 'Driver';
  const riderPhone = userData.phone || userData.phoneNumber || '';
  const vehicleType = userData.vehicleType || 'Bike';
  const vehicleModel = userData.vehicleModel || 'Motorbike';
  const plateNumber = userData.plateNumber || '';

  const rideRef = db.collection('rides').doc(rideId);

  try {
    // 3. Atomic Database Transaction
    const result = await db.runTransaction(async (transaction) => {
      const rideSnap = await transaction.get(rideRef);

      if (!rideSnap.exists) {
        return { success: false, code: 'RIDE_NOT_FOUND', message: 'Ride request does not exist.' };
      }

      const rideCurrent = rideSnap.data();

      // STRICT CONCURRENCY CHECK
      if (rideCurrent.status !== 'requested') {
        return {
          success: false,
          code: 'RIDE_ALREADY_ACCEPTED',
          message: 'This ride has already been accepted by another driver or cancelled.',
          currentStatus: rideCurrent.status,
        };
      }

      // Assign ride to this driver
      transaction.update(rideRef, {
        riderId: riderUid,
        riderName: riderName,
        riderPhone: riderPhone,
        vehicleType: vehicleType,
        vehicleModel: vehicleModel,
        plateNumber: plateNumber,
        riderLat: riderLocation.latitude || null,
        riderLng: riderLocation.longitude || null,
        status: 'accepted',
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update rider's active trip state
      const onlineRef = db.collection('online_riders').doc(riderUid);
      transaction.set(
        onlineRef,
        {
          isOnTrip: true,
          currentRideId: rideId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return {
        success: true,
        code: 'ACCEPTED',
        message: 'Ride successfully accepted!',
        rideId: rideId,
      };
    });

    return result;
  } catch (err) {
    console.error(`[acceptRide] Transaction failure for rider ${riderUid} on ride ${rideId}:`, err);
    throw new functions.https.HttpsError('internal', 'Internal error processing ride acceptance.');
  }
});

/**
 * 4. SCHEDULED CLEANUP: Expire Stale Ride Requests (> 120 seconds old)
 * Runs periodically to ensure pending requests never get stuck in requested status.
 */
exports.cleanupExpiredRides = functions.pubsub
  .schedule('every 2 minutes')
  .onRun(async (context) => {
    const now = Date.now();
    const cutoffTime = new Date(now - (120 * 1000)); // 120 seconds ago

    try {
      const staleSnap = await db.collection('rides')
        .where('status', '==', 'requested')
        .where('createdAt', '<', cutoffTime)
        .limit(50)
        .get();

      if (staleSnap.empty) {
        return null;
      }

      console.log(`[cleanupExpiredRides] Found ${staleSnap.docs.length} stale ride requests to auto-expire.`);
      const batch = db.batch();

      staleSnap.docs.forEach((doc) => {
        batch.update(doc.ref, {
          status: 'expired',
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      await batch.commit();
      console.log(`[cleanupExpiredRides] Successfully auto-expired ${staleSnap.docs.length} rides.`);
      return null;
    } catch (err) {
      console.error('[cleanupExpiredRides] Error during cleanup:', err);
      return null;
    }
  });
