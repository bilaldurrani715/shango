import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/app_version_service.dart';
import 'theme.dart';
import 'screens/auth.dart';
import 'widgets/app_update_gate.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    await FirebaseAnalytics.instance.logAppOpen();
    await NotificationService().initialize(navKey: appNavigatorKey);
    ConnectivityService().initialize();
    await AppVersionService.initialize();
    debugPrint('Firebase & App Services successfully initialized!');
  } catch (e) {
    debugPrint('Firebase initialization notice: $e');
  }
  runApp(const ShanGoApp());
}

class ShanGoApp extends StatelessWidget {
  const ShanGoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ShanGo',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        theme: appTheme(),
        builder: (context, child) => AppUpdateGate(
          child: child ?? const SizedBox.shrink(),
        ),
        home: const SplashScreen(),
      );
}
