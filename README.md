# ShanGo – Real-Time Ride-Booking Application & Instant Background Dispatcher

ShanGo is a real-time on-demand ride-hailing and booking mobile platform built with **Flutter** (Android/iOS) and backed by **Firebase Firestore** and **Firebase Cloud Messaging (FCM)**.

This repository includes the complete Flutter client application and the production-ready Node.js real-time background dispatching service.

---

## Key Features & Upgrades

### 1. Reliable Real-Time Background Notification System
- **High-Priority FCM Payloads**: Data and notification messages with `priority: 'high'` ensure delivery even when the device is locked, the screen is turned off, or the app is killed in the background.
- **Dedicated Android Notification Channel**:
  - Channel ID: `shango_ride_requests`
  - Name: `ShanGo Ride Requests`
  - Importance: `Importance.max` / High priority heads-up banner
  - Custom audio sound: `android/app/src/main/res/raw/ride_request.wav`
  - Vibration pattern: `[0, 500, 200, 500, 200, 500]`
- **Lock-Screen & Wake-Up Handling**:
  - Configured with `WAKE_LOCK` and `USE_FULL_SCREEN_INTENT`.
  - Android activity configured with `android:showWhenLocked="true"` and `android:turnScreenOn="true"` to alert drivers immediately when a ride request comes in.

### 2. Dedicated Incoming Ride Screen (`IncomingRideScreen`)
- High-visibility incoming ride screen displaying:
  - Passenger name, rating, and phone number
  - Pickup and Drop-off locations with distance calculations
  - Guaranteed fare in PKR
  - 45-second animated countdown timer with progress bar
  - One-tap **Accept** and **Decline** actions
- **Real-time Cancellation Reactivity**:
  - Listens to the ride in Firestore; if the passenger cancels or another driver accepts first, the screen immediately dismisses the prompt and notifies the rider without false alerts.

### 3. Server-Authoritative Concurrency Control
- Atomic acceptance using Firestore transactions ensures only **one** driver can accept a ride, preventing race conditions.
- Once accepted, the ride updates to `status: 'accepted'`, assigning `riderId` and marking the rider's `isOnTrip: true`.

### 4. Zero-Cost Dispatch Engine (Firebase Spark Compatible)
- Operates on Firebase's free **Spark plan** without requiring the paid Blaze plan.
- The dispatch daemon runs continuously, monitoring Firestore for new ride requests and dispatching FCM notifications to nearby riders within a 5 km radius.
- Can be run locally or deployed 24/7 on **Railway.app** or **Render.com** free tier.

---

## Project Structure

```
shango/
├── android/                 # Android native project files
│   └── app/src/main/res/raw/ride_request.wav # Custom audio tone
├── assets/
│   ├── data/                # Bannu places and geographical dataset
│   ├── images/              # Logo and splash assets
│   └── sounds/              # Ride alert audio
├── functions/               # Backend dispatch & cloud logic
│   ├── standalone-dispatcher.js # 24/7 background ride dispatcher
│   ├── index.js             # Cloud Functions definitions
│   ├── package.json         # Dependencies & start script
│   ├── Procfile             # Railway / Render process definition
│   └── README.md            # Backend deployment guide
├── lib/
│   ├── main.dart            # Flutter entrypoint & navigation key
│   ├── screens/
│   │   ├── incoming_ride_screen.dart # High-priority incoming ride screen
│   │   ├── rider.dart       # Rider mode screen & active ride tracking
│   │   ├── customer.dart    # Passenger booking & search flow
│   │   ├── auth.dart        # Authentication & profile setup
│   │   └── ...
│   ├── services/
│   │   ├── notification_service.dart # FCM background handler & channels
│   │   ├── ride_service.dart # Atomic transactions & Firestore queries
│   │   ├── location_service.dart # GPS tracking & distance calculations
│   │   └── ...
│   └── theme.dart           # App styling and color palette
└── pubspec.yaml             # Flutter dependencies
```

---

## Getting Started

### Prerequisites
- **Flutter SDK**: `>=3.0.0`
- **Node.js**: `>=18.0.0`
- **Android Studio / VS Code**
- A **Firebase Project** with Firestore and Cloud Messaging enabled

### 1. Flutter Mobile App Setup

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Verify code health:
   ```bash
   flutter analyze
   ```

3. Run the app on an Android device or emulator:
   ```bash
   flutter run
   ```

*Note: For testing background notifications and lock-screen wake-ups, run on a physical Android device or an emulator with Google Play Services.*

---

### 2. Backend Dispatcher Setup

1. Navigate to the `functions/` directory:
   ```bash
   cd functions
   npm install
   ```

2. Place your Firebase service account private key in `functions/` as `serviceAccountKey.json`. (This file is ignored by git for security).

3. Start the dispatcher:
   ```bash
   npm start
   ```

You will see:
```text
Initialized Firebase Admin with local key: serviceAccountKey.json
====================================================
ShanGo Ride Request Background Dispatcher Started
Listening for incoming rides & updates in Firestore...
====================================================
```

---

### 3. Deploying the Dispatcher 24/7 to Railway

To keep the dispatcher running online 24/7 for free:

1. Create a project at [Railway.app](https://railway.app).
2. Connect your GitHub repository (`bilaldurrani715/shango`).
3. Set **Root Directory** to `functions`.
4. In Railway **Variables**, create `FIREBASE_SERVICE_ACCOUNT` and paste the raw JSON text of your service account key.
5. Railway will automatically build and start the dispatcher.

---

## Security Note

Sensitive credentials (such as `serviceAccountKey.json`, `upload-keystore.jks`, and `key.properties`) are strictly ignored via `.gitignore` to protect your Firebase and signing keys. Always use environment variables in cloud deployments.
