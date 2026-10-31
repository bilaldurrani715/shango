import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  Timer? _pollingTimer;
  bool _isChecking = false;

  void initialize() {
    if (_pollingTimer != null) return;
    checkNow();
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      checkNow();
    });
  }

  Future<bool> checkNow() async {
    if (_isChecking) return isOnline.value;
    _isChecking = true;
    try {
      final res = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      final connected = res.isNotEmpty && res[0].rawAddress.isNotEmpty;
      if (isOnline.value != connected) {
        isOnline.value = connected;
      }
      return connected;
    } catch (_) {
      if (isOnline.value != false) {
        isOnline.value = false;
      }
      return false;
    } finally {
      _isChecking = false;
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService().isOnline,
      builder: (context, online, _) {
        if (online) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No internet connection. Viewing offline cached map & data.',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              InkWell(
                onTap: () => ConnectivityService().checkNow(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
