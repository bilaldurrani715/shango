/**
 * ShanGo Standalone Background Ride Request Dispatcher Daemon
 *
 * This daemon runs continuously on Node.js and listens to Firestore in real-time.
 * It provides instant dispatching for local testing, staging, and dedicated server setups (Railway, Render, VPS).
 *
 * Usage:
 *   1. Local: Place `serviceAccountKey.json` in the `functions/` folder.
 *   2. Railway/Render: Set the `FIREBASE_SERVICE_ACCOUNT` environment variable to the JSON content of your serviceAccountKey.
 *   3. Run: `node functions/standalone-dispatcher.js`
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');
const http = require('http');

// 1. Initialize Firebase Admin SDK
const defaultKeyPath = path.join(__dirname, 'serviceAccountKey.json');
const filesInDir = fs.readdirSync(__dirname);
const autoFoundKey = filesInDir.find(f => f.endsWith('.json') && (f.includes('adminsdk') || f.includes('serviceAccount')));
const resolvedKeyPath = fs.existsSync(defaultKeyPath) ? defaultKeyPath : (autoFoundKey ? path.join(__dirname, autoFoundKey) : null);

if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  try {
    let raw = process.env.FIREBASE_SERVICE_ACCOUNT.trim();
    if (!raw.startsWith('{')) {
      raw = Buffer.from(raw, 'base64').toString('utf8');
    }
    const serviceAccount = JSON.parse(raw);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || 'shango-46a70',
    });
    console.log('Initialized Firebase Admin via FIREBASE_SERVICE_ACCOUNT environment variable.');
  } catch (err) {
    console.error('Failed to parse FIREBASE_SERVICE_ACCOUNT environment variable:', err);
    process.exit(1);
  }
} else if (resolvedKeyPath && fs.existsSync(resolvedKeyPath)) {
  const serviceAccount = require(resolvedKeyPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id || 'shango-46a70',
  });
  console.log(`Initialized Firebase Admin with local key: ${path.basename(resolvedKeyPath)}`);
} else {
  console.error('\n❌ [ERROR] Missing Firebase Admin Credentials!');
  console.error('Firebase Admin requires a private service account key to read Firestore and dispatch notifications.\n');
  console.error('👉 Quick 1-minute fix:');
  console.error('1. Open: https://console.firebase.google.com/project/shango-46a70/settings/serviceaccounts/adminsdk');
  console.error('2. Click "Generate new private key" -> "Generate key"');
  console.error('3. Rename the downloaded file to: serviceAccountKey.json');
  console.error('4. Put it in this folder:');
  console.error('   ' + path.join(__dirname, 'serviceAccountKey.json'));
  console.error('5. Re-run: node standalone-dispatcher.js\n');
  process.exit(1);
}

const db = admin.firestore();
const MAX_RADIUS_KM = 7.0;
const RIDE_TTL_SECONDS = 90;

function calculateDistanceKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
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

const processedRides = new Set();

console.log('====================================================');
console.log('ShanGo Ride Request Background Dispatcher Started');
console.log('Listening for incoming rides & updates in Firestore...');
console.log('====================================================');

// Real-time listener on active requested rides
db.collection('rides')
  .where('status', '==', 'requested')
  .onSnapshot(async (snapshot) => {
    for (const change of snapshot.docChanges()) {
      if (change.type === 'added') {
        const rideId = change.doc.id;
        if (processedRides.has(rideId)) continue;
        processedRides.add(rideId);

        const rideData = change.doc.data();
        await dispatchRideRequest(rideId, rideData);
      }
    }
  }, (err) => {
    console.error('Firestore rides listener error:', err);
  });

// Real-time listener for ride cancellations and acceptance to dismiss notifications
db.collection('rides')
  .onSnapshot((snapshot) => {
    for (const change of snapshot.docChanges()) {
      if (change.type === 'modified') {
        const rideId = change.doc.id;
        const data = change.doc.data();
        if (data.status === 'accepted') {
          notifyRidersRideUnavailable(rideId, data.riderId, 'accepted_by_other');
        } else if (data.status === 'cancelled') {
          notifyRidersRideUnavailable(rideId, null, 'passenger_cancelled');
        }
      }
    }
  }, (err) => {
    console.error('Firestore status listener error:', err);
  });

async function dispatchRideRequest(rideId, rideData) {
  const pickupLat = parseFloat(rideData.pickupLat);
  const pickupLng = parseFloat(rideData.pickupLng);

  if (isNaN(pickupLat) || isNaN(pickupLng)) {
    console.warn(`Ride ${rideId} missing valid pickup coordinates.`);
    return;
  }

  console.log(`\n[NEW RIDE] Dispatching Ride ${rideId} at (${pickupLat}, ${pickupLng})`);

  try {
    const onlineSnap = await db.collection('online_riders')
      .where('isOnline', '==', true)
      .get();

    if (onlineSnap.empty) {
      console.log(`No online riders found for Ride ${rideId}.`);
      return;
    }

    const eligibleTokens = [];
    const eligibleRiderUids = [];
    const tokenToUidMap = {};

    for (const doc of onlineSnap.docs) {
      const data = doc.data();
      const uid = doc.id;

      if (data.isOnTrip === true) continue;

      const rLat = parseFloat(data.lat);
      const rLng = parseFloat(data.lng);
      if (isNaN(rLat) || isNaN(rLng)) continue;

      const dist = calculateDistanceKm(pickupLat, pickupLng, rLat, rLng);
      if (dist > MAX_RADIUS_KM) continue;

      const userDoc = await db.collection('users').doc(uid).get();
      if (!userDoc.exists) continue;
      const uData = userDoc.data();
      if (uData.isSuspended === true || uData.isApproved === false) continue;

      const token = data.fcmToken || uData.fcmToken;
      if (token && !eligibleTokens.includes(token)) {
        eligibleTokens.push(token);
        eligibleRiderUids.push(uid);
        tokenToUidMap[token] = uid;
      }
    }

    console.log(`Found ${eligibleTokens.length} eligible online riders for Ride ${rideId}.`);
    if (eligibleTokens.length === 0) return;

    const estimatedFare = String(Math.round(rideData.estimatedFare || 300));
    const pickupAddress = String(rideData.pickupAddress || 'Nearby Pickup');
    const dropAddress = String(rideData.dropAddress || 'Destination');

    const payloadData = {
      type: 'NEW_RIDE_REQUEST',
      ride_request_id: String(rideId),
      pickup_address: pickupAddress,
      drop_address: dropAddress,
      pickup_latitude: String(pickupLat),
      pickup_longitude: String(pickupLng),
      drop_latitude: String(rideData.dropLat || ''),
      drop_longitude: String(rideData.dropLng || ''),
      estimated_fare: estimatedFare,
      distance_km: String((rideData.distanceKm || 2.0).toFixed(1)),
      customer_name: String(rideData.customerName || 'Passenger'),
      customer_phone: String(rideData.customerPhone || ''),
      expires_at: String(Date.now() + (RIDE_TTL_SECONDS * 1000)),
    };

    const notificationPayload = {
      title: `NEW RIDE REQUEST! (PKR ${estimatedFare})`,
      body: `Pickup: ${pickupAddress} • PKR ${estimatedFare} (Cash) • Tap to accept`,
    };

    // Both notification + data payload:
    // When the app is closed/killed, Google Play Services system daemon ALWAYS displays the notification,
    // plays the custom sound 'ride_request', and vibrates on channel 'shango_ride_requests_v2'.
    // When the app is open, FirebaseMessaging.onMessage handles the custom UI and sound in foreground.
    const message = {
      tokens: eligibleTokens,
      notification: notificationPayload,
      android: {
        priority: 'high',
        ttl: RIDE_TTL_SECONDS * 1000,
        notification: {
          channelId: 'shango_ride_requests_v2',
          sound: 'ride_request',
          tag: `ride_${rideId}`,
          title: `NEW RIDE REQUEST! (PKR ${estimatedFare})`,
          body: `Pickup: ${pickupAddress} • PKR ${estimatedFare} (Cash) • Tap to accept`,
          icon: 'ic_launcher',
          color: '#F4C20D',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
        data: payloadData,
      },
      data: payloadData,
    };

    const resp = await admin.messaging().sendEachForMulticast(message);
    console.log(`Dispatched to ${resp.successCount} riders (${resp.failureCount} failed).`);

    // Clean up invalid tokens
    if (resp.failureCount > 0) {
      const batch = db.batch();
      let invalidCount = 0;
      resp.responses.forEach((r, idx) => {
        if (!r.success) {
          const errCode = r.error ? r.error.code : 'unknown';
          const badToken = eligibleTokens[idx];
          const uid = tokenToUidMap[badToken];
          if (
            errCode === 'messaging/invalid-registration-token' ||
            errCode === 'messaging/registration-token-not-registered'
          ) {
            if (uid) {
              batch.update(db.collection('users').doc(uid), { fcmToken: admin.firestore.FieldValue.delete() });
              batch.update(db.collection('online_riders').doc(uid), { fcmToken: admin.firestore.FieldValue.delete() });
              invalidCount++;
            }
          }
        }
      });
      if (invalidCount > 0) {
        await batch.commit();
        console.log(`Cleaned up ${invalidCount} invalid tokens.`);
      }
    }
  } catch (err) {
    console.error(`Dispatch error for Ride ${rideId}:`, err);
  }
}

async function notifyRidersRideUnavailable(rideId, acceptedRiderId, reason) {
  try {
    const onlineSnap = await db.collection('online_riders').where('isOnline', '==', true).get();
    const tokens = [];
    for (const doc of onlineSnap.docs) {
      if (acceptedRiderId && doc.id === acceptedRiderId) continue;
      const data = doc.data();
      if (data.fcmToken) tokens.push(data.fcmToken);
    }
    if (tokens.length === 0) return;

    const cancelMessage = {
      tokens: tokens,
      android: {
        priority: 'high',
        data: {
          type: 'RIDE_NO_LONGER_AVAILABLE',
          ride_request_id: rideId,
          reason: reason,
        },
      },
      data: {
        type: 'RIDE_NO_LONGER_AVAILABLE',
        ride_request_id: rideId,
        reason: reason,
      },
    };
    await admin.messaging().sendEachForMulticast(cancelMessage);
  } catch (e) {
    console.error('Error notifying ride unavailable:', e);
  }
}

// Minimal HTTP Health Check server for Railway/Render
const PORT = process.env.PORT || 8080;
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ status: 'ok', service: 'shango-dispatcher', timestamp: new Date().toISOString() }));
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.warn(`[Dispatcher] Port ${PORT} is already in use. HTTP health check server skipped, Firestore dispatcher continues running.`);
  } else {
    console.error('[Dispatcher] HTTP server error:', err);
  }
});

server.listen(PORT, () => {
  console.log(`Health check HTTP server listening on port ${PORT}`);
});
