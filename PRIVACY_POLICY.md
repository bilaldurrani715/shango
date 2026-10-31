# Privacy Policy for ShanGo

**Application Name:** ShanGo  
**Package Name:** `com.jabirulabs.shango`  
**Platform Owner & Operator:** ShanGo  
**Technical App Developer:** Jabiru Labs  
**Effective Date:** October 2026  
**Primary Support Email:** [shango@gmail.com](mailto:shango@gmail.com)  
**Developer Technical Contact:** [bilaldurrani715@gmail.com](mailto:bilaldurrani715@gmail.com)  

---

## 1. Introduction
Welcome to **ShanGo** ("we," "our," or "us"), a ride-booking and transportation platform owned and operated by **ShanGo**. The application software was developed by **Jabiru Labs** as the technical development partner. This Privacy Policy explains our practices regarding the collection, use, and disclosure of your personal data when you use our mobile application ("ShanGo") on Android and associated services.

By installing and using ShanGo, you agree to the collection and handling of your information as outlined in this policy.

---

## 2. Information We Collect

### A. Personal Information
- **Account Details:** Name, email address, telephone/mobile number, profile image, and authentication credentials (via Firebase Auth / Google Sign-In).
- **Driver Verification Data (for Drivers):** Driver's license number and images, vehicle registration, license plate number, vehicle make and model, and identity verification documents.
- **In-App Communication:** Phone call intents and messages initiated between riders and drivers to coordinate pickups and drop-offs.

### B. Precise & Approximate Location Data (Crucial for Ride Services)
- **Permissions:** `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`.
- **Purpose of Collection:**
  - Finding the rider's current pickup location.
  - Matching riders with nearby available drivers.
  - Calculating real-time travel routes, estimated arrival times (ETA), and ride pricing/fares.
  - Enabling live turn-by-turn navigation and active trip tracking for passenger and driver safety.
- **Background & Foreground Collection:** Location data is collected while the app is actively used in the foreground and during an active trip. Users can revoke location permissions at any time via Android device settings, though core ride booking functionality will not function without it.

### C. Ride & Transaction Data
- Trip history, pickup points, drop-off destinations, routes taken, distance traveled, trip duration, fares, and transaction timestamps.
- Ratings, reviews, and feedback exchanged between riders and drivers.

### D. Device and Technical Information
- Hardware model, operating system version, unique device identifiers, IP address, and push notification tokens (Firebase Cloud Messaging).
- Crash diagnostics and error telemetry to maintain app stability.

---

## 3. How We Use Your Information
We use collected data solely for legitimate business and operational purposes:
1. **Service Fulfillment:** Booking rides, driver assignment, ride dispatch, and trip completion.
2. **Safety and Tracking:** Displaying real-time driver progress to riders and monitoring trip safety.
3. **Push Notifications:** Sending critical ride alerts (e.g., driver arrived, booking confirmed, trip completed) via Firebase Cloud Messaging.
4. **Customer Support:** Resolving disputes, handling lost item inquiries, and investigating safety reports.
5. **Fraud Prevention & Security:** Preventing duplicate registrations, unauthorized account access, and policy violations.

---

## 4. Third-Party Services
ShanGo integrates trusted third-party SDKs that process data in accordance with their privacy policies:
- **Google Play Services:** [Privacy Policy](https://policies.google.com/privacy)
- **Firebase Authentication:** [Firebase Privacy & Security](https://firebase.google.com/support/privacy)
- **Cloud Firestore & Firebase Realtime Database:** [Firebase Privacy & Security](https://firebase.google.com/support/privacy)
- **Firebase Cloud Messaging (FCM):** [Firebase Privacy & Security](https://firebase.google.com/support/privacy)
- **Google Sign-In:** [Google Privacy Policy](https://policies.google.com/privacy)
- **OpenStreetMap / Flutter Map:** [OSM Foundation Privacy Policy](https://wiki.osmfoundation.org/wiki/Privacy_Policy)

---

## 5. Information Sharing and Disclosure
- **Between Rider and Driver:** When a ride is booked, the driver receives the rider's name, pickup location, destination, and contact method. The rider receives the driver's name, vehicle make/model/plate, driver photo, and real-time location.
- **Service Providers:** Cloud infrastructure providers (Google Cloud / Firebase) hosting database and backend operations.
- **Legal Obligations:** If compelled by law enforcement, judicial order, or to prevent imminent danger or fraud.
- **No Sale of Data:** We never sell, rent, or monetize your personal information to third-party data brokers or advertisers.

---

## 6. Account Deletion and Data Retention (Google Play Compliance)
Users have full rights to request complete deletion of their account and associated personal data:
- **In-App:** Open **ShanGo > Profile / Settings > Delete Account**.
- **By Email:** Send a deletion request to [shango@gmail.com](mailto:shango@gmail.com) with the subject *"Account Deletion Request - ShanGo"*, including your registered mobile number or email.
- **Processing Time:** Personal data will be deleted or anonymized within 30 days, except records required by law for taxation or audit compliance.

---

## 7. Children's Privacy
ShanGo is not directed at children under the age of 13 (or under the age of 18 without parental consent). We do not knowingly collect personal data from minors. If identified, such data is promptly deleted.

---

## 8. Security Measures
We use industry-standard encryption (HTTPS / TLS) for all data in transit, strict Firestore database security rules, and authenticated access protocols to protect your personal information.

---

## 9. Contact Information
For any questions, requests, or privacy-related concerns:
- **Platform & Service Owner:** ShanGo
- **Primary Support Email:** [shango@gmail.com](mailto:shango@gmail.com)
- **Technical App Developer:** Jabiru Labs ([bilaldurrani715@gmail.com](mailto:bilaldurrani715@gmail.com))
- **Application Package:** `com.jabirulabs.shango`
