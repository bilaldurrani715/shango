import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Model representing remote version control settings stored in Firestore
class AppVersionInfo {
  final String minVersion;
  final int minBuildNumber;
  final String latestVersion;
  final bool forceUpdate;
  final String updateUrl;
  final String title;
  final String message;
  final String releaseNotes;

  const AppVersionInfo({
    required this.minVersion,
    required this.minBuildNumber,
    required this.latestVersion,
    required this.forceUpdate,
    required this.updateUrl,
    required this.title,
    required this.message,
    required this.releaseNotes,
  });

  factory AppVersionInfo.fromMap(Map<String, dynamic>? data) {
    if (data == null) {
      return AppVersionInfo.defaultInfo();
    }
    return AppVersionInfo(
      minVersion: (data['minVersion'] ?? data['min_version'] ?? '1.0.0').toString().trim(),
      minBuildNumber: (data['minBuildNumber'] ?? data['min_build_number'] as num?)?.toInt() ?? 1,
      latestVersion: (data['latestVersion'] ?? data['latest_version'] ?? '1.0.0').toString().trim(),
      forceUpdate: data['forceUpdate'] == true || data['force_update'] == true,
      updateUrl: (data['updateUrl'] ??
              data['update_url'] ??
              'https://play.google.com/store/apps/details?id=com.jabirulabs.shango')
          .toString()
          .trim(),
      title: (data['title'] ?? 'New Update Available!').toString().trim(),
      message: (data['message'] ??
              'A new and improved version of ShanGo is now available. Please update the app to continue using our services.')
          .toString()
          .trim(),
      releaseNotes: (data['releaseNotes'] ?? data['release_notes'] ?? '').toString().trim(),
    );
  }

  factory AppVersionInfo.defaultInfo() {
    return const AppVersionInfo(
      minVersion: '1.0.0',
      minBuildNumber: 1,
      latestVersion: '1.0.0',
      forceUpdate: false,
      updateUrl: 'https://play.google.com/store/apps/details?id=com.jabirulabs.shango',
      title: 'New Update Available!',
      message: 'A new version of ShanGo is available. Please update to the latest version to continue.',
      releaseNotes: '',
    );
  }

  /// Determines if the current installed app is outdated and must be updated
  bool isUpdateRequired({
    required String currentVersion,
    required int currentBuildNumber,
  }) {
    // 1. Explicit global kill switch / force update toggle in backend
    if (forceUpdate) return true;

    // 2. Build number check (e.g. current = 1, required = 2)
    if (currentBuildNumber < minBuildNumber) return true;

    // 3. Semantic version check (e.g. current = "1.0.0", required = "1.0.1")
    if (AppVersionService.compareVersions(currentVersion, minVersion) < 0) {
      return true;
    }

    return false;
  }
}

class AppVersionService {
  static final AppVersionService _instance = AppVersionService._internal();
  factory AppVersionService() => _instance;
  AppVersionService._internal();

  static PackageInfo? _packageInfo;

  /// Initializes package info dynamically from the operating system
  static Future<void> initialize() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
      debugPrint('AppVersionService loaded package info: ${_packageInfo?.version}+${_packageInfo?.buildNumber}');
    } catch (e) {
      debugPrint('AppVersionService PackageInfo load notice: $e');
    }
  }

  /// Current running app version (dynamically read from app package)
  static String get currentAppVersion => _packageInfo?.version ?? '1.0.2';
  static int get currentAppBuildNumber =>
      int.tryParse(_packageInfo?.buildNumber ?? '1') ?? 1;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Document reference in Firestore: collection('app_settings').doc('app_version')
  DocumentReference<Map<String, dynamic>> get _versionDoc =>
      _firestore.collection('app_settings').doc('app_version');

  /// Real-time stream of the version configuration from Firestore
  Stream<AppVersionInfo> streamVersionInfo() {
    return _versionDoc.snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return AppVersionInfo.defaultInfo();
      }
      return AppVersionInfo.fromMap(doc.data());
    });
  }

  /// One-time fetch of the version configuration
  Future<AppVersionInfo> fetchVersionInfo() async {
    try {
      final doc = await _versionDoc.get();
      if (!doc.exists || doc.data() == null) {
        return AppVersionInfo.defaultInfo();
      }
      return AppVersionInfo.fromMap(doc.data());
    } catch (e) {
      debugPrint('Error fetching AppVersionInfo: $e');
      return AppVersionInfo.defaultInfo();
    }
  }

  /// Update or initialize the remote version settings in Firestore
  Future<void> updateVersionSettings({
    required String minVersion,
    required int minBuildNumber,
    required String latestVersion,
    required bool forceUpdate,
    required String updateUrl,
    required String title,
    required String message,
    String releaseNotes = '',
  }) async {
    await _versionDoc.set({
      'minVersion': minVersion.trim(),
      'minBuildNumber': minBuildNumber,
      'latestVersion': latestVersion.trim(),
      'forceUpdate': forceUpdate,
      'updateUrl': updateUrl.trim(),
      'title': title.trim(),
      'message': message.trim(),
      'releaseNotes': releaseNotes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Launch the update link in Google Play Store or external web browser
  Future<bool> launchUpdateUrl(String rawUrl) async {
    if (rawUrl.isEmpty) return false;

    String target = rawUrl.trim();
    if (!target.startsWith('http://') &&
        !target.startsWith('https://') &&
        !target.startsWith('market://')) {
      target = 'https://$target';
    }

    try {
      final uri = Uri.parse(target);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback for market:// URLs to standard https://play.google.com
        if (target.startsWith('market://details?id=')) {
          final pkg = target.replaceFirst('market://details?id=', '');
          final webUri = Uri.parse('https://play.google.com/store/apps/details?id=$pkg');
          return await launchUrl(webUri, mode: LaunchMode.externalApplication);
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error launching update URL: $e');
      return false;
    }
  }

  /// Compare two semantic version strings (e.g., "1.0.0" vs "1.0.1")
  /// Returns -1 if v1 < v2, 1 if v1 > v2, 0 if v1 == v2
  static int compareVersions(String v1, String v2) {
    String sanitize(String v) =>
        v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;

    final parts1 = sanitize(v1).split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = sanitize(v2).split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 < p2) return -1;
      if (p1 > p2) return 1;
    }
    return 0;
  }
}
