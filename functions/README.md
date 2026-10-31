# ShanGo Background Ride Request Dispatcher

The **ShanGo Background Ride Request Dispatcher** is a resilient Node.js service that listens to Firestore in real-time, calculates ride distances using the Haversine formula, dispatches high-priority Firebase Cloud Messaging (FCM) notifications to nearby available riders, and handles ride cancellation/expiry cleanly.

It works with **Firebase Spark (Free Tier)** without requiring the paid Blaze plan.

---

## Features

1. **Real-time Firestore Listener**: Automatically detects newly requested rides (`status: 'requested'`).
2. **Geo-proximity Matching**: Uses the Haversine formula to find online riders within a configured radius (default 5.0 km).
3. **High-Priority FCM Data Messages**:
   - `priority: 'high'`
   - Android notification channel `shango_ride_requests`
   - Custom audio sound (`ride_request.wav`)
   - Vibration pattern `[0, 500, 200, 500, 200, 500]`
   - Full-screen intent & heads-up display
4. **Auto Expiry & Cleanup**:
   - If no rider accepts within 45 seconds, the ride expires (`status: 'no_riders_available'`).
   - All alerted riders receive a silent data payload to dismiss the prompt automatically.
5. **Atomic Acceptance**: Prevents race conditions when multiple riders try to accept the same ride at once.
6. **Built-in HTTP Health Check**: Exposes `GET /` on `PORT` (default `8080`) for cloud health probes.

---

## Running Locally

1. Place your Firebase service account private key in this folder as `serviceAccountKey.json` (it is git-ignored for security).
2. Install dependencies:
   ```bash
   npm install
   ```
3. Run the dispatcher:
   ```bash
   npm start
   ```

---

## Deploying to Railway.app (24/7 Free Hosting)

1. Sign up / log in to [Railway.app](https://railway.app).
2. Click **+ New Project** -> **Deploy from GitHub repo**.
3. Select `bilaldurrani715/shango`.
4. In Railway project settings:
   - Set **Root Directory** to `functions`.
   - Under **Variables**, add:
     - `FIREBASE_SERVICE_ACCOUNT`: Copy the entire text content of your `serviceAccountKey.json` and paste it here.
5. Railway will automatically build using `npm install` and run `npm start` (`node standalone-dispatcher.js`).
6. Your dispatcher will now run 24/7 in the cloud for free!

---

## Deploying to Render.com (Alternative Free Hosting)

1. Sign up / log in to [Render.com](https://render.com).
2. Create a **New Web Service** connected to your GitHub repository.
3. Configure:
   - **Root Directory**: `functions`
   - **Build Command**: `npm install`
   - **Start Command**: `node standalone-dispatcher.js`
4. In **Environment Variables**:
   - Add `FIREBASE_SERVICE_ACCOUNT` with the contents of your `serviceAccountKey.json`.
5. Deploy.
