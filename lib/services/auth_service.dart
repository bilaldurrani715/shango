import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Current User Stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Stream user document data (role, vehicle, name, etc.) from Firestore
  Stream<Map<String, dynamic>?> streamUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) => doc.data());
  }

  /// Get user document data once
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      debugPrint('Error getting user data: $e');
      return null;
    }
  }

  /// Check if user has completed mandatory profile setup (role, phone, vehicle if rider)
  static bool isProfileComplete(Map<String, dynamic>? data) {
    if (data == null) return false;
    final role = data['role'] as String?;
    final phone = data['phone'] as String?;
    if (role == null || role.isEmpty) return false;
    if (phone == null || phone.trim().isEmpty) return false;

    if (role == 'rider') {
      final vehicleModel = data['vehicleModel'] as String?;
      final plateNumber = data['plateNumber'] as String?;
      if (vehicleModel == null || vehicleModel.trim().isEmpty) return false;
      if (plateNumber == null || plateNumber.trim().isEmpty) return false;
    }
    return true;
  }

  /// Update full user profile
  Future<void> updateUserProfile({
    required String uid,
    String? name,
    String? phone,
    String? role,
    String? vehicleType,
    String? vehicleModel,
    String? plateNumber,
  }) async {
    final Map<String, dynamic> data = {};
    if (name != null && name.isNotEmpty) data['name'] = name;
    if (phone != null && phone.isNotEmpty) data['phone'] = phone;
    if (role != null && role.isNotEmpty) data['role'] = role;
    if (vehicleType != null) data['vehicleType'] = vehicleType;
    if (vehicleModel != null) data['vehicleModel'] = vehicleModel;
    if (plateNumber != null) data['plateNumber'] = plateNumber;
    data['updatedAt'] = FieldValue.serverTimestamp();

    await _firestore.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  /// Get current user role ('customer' or 'rider')
  Future<String> getUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return (doc.data()?['role'] as String?) ?? 'customer';
      }
    } catch (e) {
      debugPrint('Error getting user role: $e');
    }
    return 'customer';
  }

  /// Update user role ('customer' <-> 'rider')
  Future<void> updateUserRole(String uid, String role) async {
    await _firestore.collection('users').doc(uid).set({
      'role': role,
      if (role == 'rider') 'isApproved': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Admin approve or revoke rider account
  Future<void> setRiderApprovalStatus(String uid, {required bool isApproved}) async {
    await _firestore.collection('users').doc(uid).set({
      'isApproved': isApproved,
      'approvedAt': isApproved ? FieldValue.serverTimestamp() : null,
    }, SetOptions(merge: true));
  }

  /// Admin suspend or unsuspend any user (rider or passenger)
  Future<void> setUserSuspensionStatus(String uid, {required bool isSuspended, String? reason}) async {
    await _firestore.collection('users').doc(uid).set({
      'isSuspended': isSuspended,
      'suspensionReason': isSuspended ? (reason ?? 'Account suspended by Admin') : null,
      'suspendedAt': isSuspended ? FieldValue.serverTimestamp() : null,
    }, SetOptions(merge: true));
  }

  /// Driver toggles availability for scheduled / intercity rides (ON / OFF)
  Future<void> setDriverScheduledAvailability(String uid, bool isAvailable) async {
    await _firestore.collection('users').doc(uid).set({
      'isAvailableForScheduled': isAvailable,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Submit a request to switch account type (requires admin approval)
  Future<void> submitAccountSwitchRequest({
    required String uid,
    required String requestedRole,
    String? vehicleType,
    String? vehicleModel,
    String? plateNumber,
    String? phone,
    String? reason,
  }) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final currentRole = (userDoc.data()?['role'] as String?) ?? 'customer';
    final userName = (userDoc.data()?['name'] as String?) ?? 'User';
    final userEmail = (userDoc.data()?['email'] as String?) ?? '';
    final existingPhone = (userDoc.data()?['phone'] as String?) ?? '';

    final Map<String, dynamic> updateData = {
      'switchRequest': {
        'status': 'pending',
        'requestedRole': requestedRole,
        'currentRole': currentRole,
        'userName': userName,
        'userEmail': userEmail,
        'userPhone': (phone != null && phone.isNotEmpty) ? phone : existingPhone,
        'vehicleType': vehicleType,
        'vehicleModel': vehicleModel,
        'plateNumber': plateNumber,
        'reason': reason,
        'requestedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (phone != null && phone.isNotEmpty) {
      updateData['phone'] = phone;
    }

    await _firestore.collection('users').doc(uid).set(updateData, SetOptions(merge: true));
  }

  /// Cancel a pending account switch request
  Future<void> cancelAccountSwitchRequest(String uid) async {
    await _firestore.collection('users').doc(uid).set({
      'switchRequest': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Admin approves an account switch request
  Future<void> approveAccountSwitchRequest(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return;
    final data = doc.data() ?? {};
    final req = data['switchRequest'] as Map<String, dynamic>?;
    if (req == null) return;

    final newRole = (req['requestedRole'] as String?) ?? 'customer';
    final Map<String, dynamic> updateData = {
      'role': newRole,
      'switchRequest': {
        ...req,
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (newRole == 'rider') {
      updateData['isApproved'] = true;
      if (req['vehicleType'] != null) updateData['vehicleType'] = req['vehicleType'];
      if (req['vehicleModel'] != null) updateData['vehicleModel'] = req['vehicleModel'];
      if (req['plateNumber'] != null) updateData['plateNumber'] = req['plateNumber'];
      if (req['userPhone'] != null && (req['userPhone'] as String).isNotEmpty) {
        updateData['phone'] = req['userPhone'];
      }
    }

    await _firestore.collection('users').doc(uid).set(updateData, SetOptions(merge: true));
  }

  /// Admin rejects an account switch request
  Future<void> rejectAccountSwitchRequest(String uid, {String? reason}) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return;
    final data = doc.data() ?? {};
    final req = data['switchRequest'] as Map<String, dynamic>? ?? {};

    await _firestore.collection('users').doc(uid).set({
      'switchRequest': {
        ...req,
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': reason ?? 'Declined by Admin',
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream all pending account switch requests for admin
  Stream<List<Map<String, dynamic>>> streamSwitchRequests() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final req = data['switchRequest'] as Map<String, dynamic>?;
        if (req != null && req['status'] == 'pending') {
          final item = Map<String, dynamic>.from(data);
          item['uid'] = doc.id;
          list.add(item);
        }
      }
      list.sort((a, b) {
        final reqA = a['switchRequest'] as Map<String, dynamic>?;
        final reqB = b['switchRequest'] as Map<String, dynamic>?;
        final timeA = reqA?['requestedAt'] as Timestamp?;
        final timeB = reqB?['requestedAt'] as Timestamp?;
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1;
        if (timeB == null) return -1;
        return timeB.compareTo(timeA);
      });
      return list;
    });
  }

  /// Set or remove Admin privilege for a user
  Future<void> setUserAdminStatus(String uid, {required bool isAdmin}) async {
    await _firestore.collection('users').doc(uid).set({
      'isAdmin': isAdmin,
      if (isAdmin) 'role': 'admin',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Sign in or auto-provision administrator in Firebase Auth
  Future<UserCredential> signInAdmin({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      if (cred.user != null) {
        await setUserAdminStatus(cred.user!.uid, isAdmin: true);
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      if ((cleanEmail == 'shango1132@gmail.com' || cleanEmail == 'shango@gmail.com') &&
          (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'invalid-email' || e.code == 'channel-error')) {
        // Auto-provision master super admin account in Firebase Auth
        try {
          final newCred = await _auth.createUserWithEmailAndPassword(
            email: cleanEmail,
            password: password,
          );
          if (newCred.user != null) {
            await newCred.user!.updateDisplayName('ShanGo Super Admin');
            await _firestore.collection('users').doc(newCred.user!.uid).set({
              'name': 'ShanGo Super Admin',
              'email': cleanEmail,
              'role': 'admin',
              'isAdmin': true,
              'phone': '+923000000000',
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
          return newCred;
        } catch (createErr) {
          debugPrint('Error creating default admin user: $createErr');
        }
      }
      throw _handleAuthException(e);
    }
  }

  // 1. EMAIL & PASSWORD LOGIN
  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // 1.1 EMAIL & PASSWORD SIGN UP WITH ROLE & VEHICLE INFO
  Future<UserCredential> registerWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
    String? phone,
    String role = 'customer',
    String? vehicleType,
    String? vehicleModel,
    String? plateNumber,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (displayName != null && displayName.isNotEmpty) {
        await credential.user?.updateDisplayName(displayName);
      }

      // Save user profile & role in Firestore
      final uid = credential.user?.uid;
      if (uid != null) {
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'name': displayName ?? 'User',
          'email': email.trim(),
          'phone': phone ?? '',
          'role': role,
          'vehicleType': vehicleType,
          'vehicleModel': vehicleModel,
          'plateNumber': plateNumber,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // 2. GOOGLE SIGN-IN
  Future<UserCredential?> signInWithGoogle({String role = 'customer'}) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final uid = userCredential.user?.uid;
      if (uid != null) {
        final doc = await _firestore.collection('users').doc(uid).get();
        if (!doc.exists) {
          await _firestore.collection('users').doc(uid).set({
            'uid': uid,
            'name': userCredential.user?.displayName ?? 'Google User',
            'email': userCredential.user?.email ?? '',
            'phone': userCredential.user?.phoneNumber ?? '',
            'role': role,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }

  // 3. PHONE NUMBER AUTHENTICATION (OTP)
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(FirebaseAuthException e) onVerificationFailed,
    required Function(PhoneAuthCredential credential) onVerificationCompleted,
    required Function(String verificationId) onCodeAutoRetrievalTimeout,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: onVerificationCompleted,
      verificationFailed: onVerificationFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: onCodeAutoRetrievalTimeout,
      timeout: const Duration(seconds: 60),
    );
  }

  // 3.1 SUBMIT OTP CODE
  Future<UserCredential> signInWithOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // SIGN OUT
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Delete Account: wipes Firestore user data, online rider record, notifications, and Firebase Auth account
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;

    try {
      // 1. Remove from online riders pool if registered as rider
      await _firestore.collection('online_riders').doc(uid).delete().catchError((_) {});

      // 2. Clean up user notifications
      try {
        final notifs = await _firestore.collection('notifications').where('recipientUid', isEqualTo: uid).get();
        for (final doc in notifs.docs) {
          await doc.reference.delete().catchError((_) {});
        }
      } catch (_) {}

      // 3. Delete user document from users collection
      await _firestore.collection('users').doc(uid).delete().catchError((_) {});

      // 4. Delete the Firebase Authentication account
      await user.delete();

      // 5. Sign out Google / local session
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw 'For security reasons, deleting your account requires recent authentication. Please log out, log in again, and retry.';
      }
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to delete account: $e';
    }
  }

  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'invalid-phone-number':
        return 'The phone number entered is invalid.';
      case 'invalid-verification-code':
        return 'The OTP entered is incorrect or expired.';
      case 'session-expired':
        return 'The OTP session has expired. Please resend code.';
      case 'operation-not-allowed':
        return 'Phone Sign-in is disabled in Firebase Console. Enable "Phone" under Firebase Console > Authentication > Sign-in method, or sign in with Email / Google.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please sign in with Email / Google or test phone numbers.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again in a few moments or sign in with Email / Google.';
      default:
        final msg = e.message ?? '';
        if (msg.contains('BILLING_NOT_ENABLED') || msg.contains('billing')) {
          return 'Real carrier SMS requires a Firebase billing account. For 100% free testing, add your phone number under Firebase Console > Auth > Sign-in method > Phone (Phone numbers for testing).';
        }
        if (msg.contains('disabled') || msg.contains('not allowed') || msg.contains('region')) {
          return 'Phone Sign-In / SMS region is disabled in Firebase Console. Please enable Phone in Firebase Authentication > Sign-in method.';
        }
        return msg.isNotEmpty ? msg : 'Authentication failed. Please try again.';
    }
  }
}
