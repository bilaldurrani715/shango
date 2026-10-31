import 'package:flutter/material.dart';
import '../services/app_version_service.dart';
import '../theme.dart';
import '../widgets.dart';

/// Full-screen, non-dismissible screen displayed when an app update is required.
/// The app stops operating and directs the user to either Google Play Store
/// or the official website download link configured in Firebase Firestore.
class ForceUpdateScreen extends StatefulWidget {
  final AppVersionInfo info;

  const ForceUpdateScreen({
    super.key,
    required this.info,
  });

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  bool _isLaunching = false;
  bool _isCheckingAgain = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  bool get _isPlayStoreLink {
    final url = widget.info.updateUrl.toLowerCase();
    return url.contains('play.google.com') || url.contains('market://');
  }

  Future<void> _handleUpdateTap() async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);

    final success = await AppVersionService().launchUpdateUrl(widget.info.updateUrl);
    if (mounted) {
      setState(() => _isLaunching = false);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: ${widget.info.updateUrl}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _handleCheckAgain() async {
    if (_isCheckingAgain) return;
    setState(() => _isCheckingAgain = true);

    await Future.delayed(const Duration(milliseconds: 800));
    final latest = await AppVersionService().fetchVersionInfo();

    if (mounted) {
      setState(() => _isCheckingAgain = false);
      final isStillRequired = latest.isUpdateRequired(
        currentVersion: AppVersionService.currentAppVersion,
        currentBuildNumber: AppVersionService.currentAppBuildNumber,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isStillRequired
                ? 'Update is still required. Please install the latest release to proceed.'
                : '✅ You are on the latest version! Thank you.',
          ),
          backgroundColor: isStillRequired ? Colors.black87 : Colors.green.shade800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope prevents user from tapping Android hardware/gesture Back button
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFFBFBFB),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App Logo & Animated Update Badge
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/images/logo.jpg',
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Logo(size: 40),
                          ),
                        ),
                      ),
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: C.black,
                            shape: BoxShape.circle,
                            border: Border.all(color: C.yellow, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: C.yellow.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.system_update_alt_rounded,
                            color: C.yellow,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Pill: Mandatory Update Notice
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 6),
                        Text(
                          'MANDATORY UPDATE REQUIRED',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Title from Backend or Default
                  Text(
                    widget.info.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: C.black,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Version badges comparison
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: C.grey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Current: v${AppVersionService.currentAppVersion}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.black45),
                        ),
                        Text(
                          'New: v${widget.info.latestVersion}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: C.black,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Descriptive message from Firebase
                  Text(
                    widget.info.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  // Release notes card if present
                  if (widget.info.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.auto_awesome, size: 16, color: Color(0xFFE5A100)),
                              SizedBox(width: 6),
                              Text(
                                "What's New in this release:",
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: C.black,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.info.releaseNotes,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Main Update Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: C.black,
                        foregroundColor: C.yellow,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isLaunching ? null : _handleUpdateTap,
                      icon: _isLaunching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: C.yellow, strokeWidth: 2.5),
                            )
                          : Icon(
                              _isPlayStoreLink ? Icons.shop_two_rounded : Icons.public_rounded,
                              size: 22,
                            ),
                      label: Text(
                        _isLaunching
                            ? 'Opening...'
                            : _isPlayStoreLink
                                ? 'Update on Google Play'
                                : 'Download Update from Website',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Re-check button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isCheckingAgain ? null : _handleCheckAgain,
                      icon: _isCheckingAgain
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        _isCheckingAgain ? 'Checking status...' : 'Already updated? Check again',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Support footer
                  Text(
                    'ShanGo Transport Network • Support: shango1132@gmail.com',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
