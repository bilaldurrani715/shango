import 'package:flutter/material.dart';
import '../services/app_version_service.dart';
import 'force_update_screen.dart';

/// Wraps the application root to listen to real-time version status from Firestore.
/// If an update is mandated by the backend (via minVersion, minBuildNumber, or forceUpdate),
/// the application stops operating and switches immediately to the ForceUpdateScreen.
class AppUpdateGate extends StatefulWidget {
  final Widget child;

  const AppUpdateGate({
    super.key,
    required this.child,
  });

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  @override
  void initState() {
    super.initState();
    AppVersionService.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppVersionInfo>(
      stream: AppVersionService().streamVersionInfo(),
      builder: (context, snapshot) {
        // If snapshot has error or hasn't loaded initial data, let app proceed normally
        if (!snapshot.hasData) {
          return widget.child;
        }

        final info = snapshot.data!;
        final requiresUpdate = info.isUpdateRequired(
          currentVersion: AppVersionService.currentAppVersion,
          currentBuildNumber: AppVersionService.currentAppBuildNumber,
        );

        if (requiresUpdate) {
          return ForceUpdateScreen(info: info);
        }

        return widget.child;
      },
    );
  }
}
