import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'admin_fleet_map_screen.dart';
import 'complete_profile_screen.dart';
import 'shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();

    // Directly open app Home/Map as Guest without forcing login on startup
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFFCC00),
        body: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/logo.jpg',
                      width: 130,
                      height: 130,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Logo(size: 50),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your ride, anytime.',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class LoginScreen extends StatefulWidget {
  final bool asModal;
  const LoginScreen({super.key, this.asModal = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();

  // Email & Password controllers
  final _emailFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isEmailLoading = false;
  bool _isGoogleLoading = false;
  bool get _isLoading => _isEmailLoading || _isGoogleLoading;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onSuccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final data = await _authService.getUserData(user.uid);
      if (!AuthService.isProfileComplete(data)) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CompleteProfileScreen(
              uid: user.uid,
              initialName: user.displayName,
              initialEmail: user.email,
              initialPhone: user.phoneNumber,
              asModal: widget.asModal,
            ),
          ),
        );
        return;
      }

      final bool isAdmin = data?['isAdmin'] == true || data?['role'] == 'admin' || user.email == 'shango1132@gmail.com' || user.email == 'shango@gmail.com';
      if (isAdmin) {
        if (user.email == 'shango1132@gmail.com' || user.email == 'shango@gmail.com') {
          await _authService.setUserAdminStatus(user.uid, isAdmin: true);
        }
        NotificationService().startLiveNotificationListener(user.uid, isAdmin: true);
      }
    }

    if (!mounted) return;
    if (widget.asModal) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 1. Email Sign-In
  Future<void> _handleEmailLogin() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _isEmailLoading = true);
    try {
      await _authService.signInWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (mounted) await _onSuccess();
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isEmailLoading = false);
    }
  }

  // 2. Google Sign-In
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null && mounted) {
        await _onSuccess();
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.asModal
            ? IconButton(
                icon: const Icon(Icons.close, color: C.black),
                onPressed: () => Navigator.pop(context, false),
              )
            : null,
        actions: [
          // Top-right Admin Console Quick Access
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: C.black,
                backgroundColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 16, color: C.black),
              label: const Text(
                'Admin',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.black),
              ),
              onPressed: () => _showAdminPinDialog(context),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App Logo & Subtitle
              Center(
                child: Column(
                  children: [
                    const Logo(size: 48),
                    const SizedBox(height: 6),
                    Text(
                      'Your ride, anytime.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Sign In',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: C.black),
              ),
              const SizedBox(height: 18),

              // Email & Password Form
              Form(
                key: _emailFormKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v != null && v.contains('@')) ? null : 'Enter a valid email',
                      decoration: const InputDecoration(
                        hintText: 'user@example.com',
                        prefixIcon: Icon(Icons.email_outlined, color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      validator: (v) => (v != null && v.length >= 6) ? null : 'Minimum 6 characters',
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, color: Colors.black54),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: Colors.black54,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      'Login',
                      isLoading: _isEmailLoading,
                      onTap: _isLoading ? null : _handleEmailLogin,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR',
                      style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
                ],
              ),
              const SizedBox(height: 20),

              // Clean Google Sign-In Button
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: BorderSide(color: Colors.grey.shade300, width: 1.2),
                  elevation: 0,
                ),
                onPressed: _isLoading ? null : _handleGoogleSignIn,
                child: _isGoogleLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: C.black,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4285F4),
                              shape: BoxShape.circle,
                            ),
                            child: const Text(
                              'G',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Continue with Google',
                            style: TextStyle(
                              color: C.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => SignupScreen(asModal: widget.asModal)),
                  ),
                  child: RichText(
                    text: const TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(color: Colors.black54, fontSize: 14),
                      children: [
                        TextSpan(
                          text: 'Create one',
                          style: TextStyle(color: C.black, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Admin Console Entry Point at Bottom
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 17),
                  label: const Text(
                    'Admin Console',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _showAdminPinDialog(context),
                ),
              ),

              if (widget.asModal)
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Continue as Guest', style: TextStyle(color: Colors.black54)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAdminPinDialog(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isLoggingIn = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: C.black),
              SizedBox(width: 10),
              Text('Admin Verification', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter administrator credentials:',
                style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                enabled: !isLoggingIn,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.email_outlined, color: Colors.black54, size: 20),
                  hintText: 'Email',
                  filled: true,
                  fillColor: C.grey,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                enabled: !isLoggingIn,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.black54, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.black54, size: 20),
                    onPressed: isLoggingIn
                        ? null
                        : () {
                            setDialogState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                  ),
                  hintText: 'Password',
                  filled: true,
                  fillColor: C.grey,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoggingIn ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: C.yellow,
                foregroundColor: C.black,
                disabledBackgroundColor: C.yellow.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isLoggingIn
                  ? null
                  : () async {
                      final email = emailController.text.trim().toLowerCase();
                      final pass = passwordController.text.trim();
                      if (email.isEmpty || pass.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Please enter admin email and password.')),
                        );
                        return;
                      }

                      setDialogState(() => isLoggingIn = true);

                      try {
                        final userCredential = await _authService.signInAdmin(
                          email: email,
                          password: pass,
                        );
                        final uid = userCredential.user?.uid;
                        if (uid != null) {
                          final data = await _authService.getUserData(uid);
                          final bool isAdmin = data?['isAdmin'] == true || data?['role'] == 'admin' || email == 'shango1132@gmail.com' || email == 'shango@gmail.com';
                          if (isAdmin) {
                            await _authService.setUserAdminStatus(uid, isAdmin: true);
                            NotificationService().startLiveNotificationListener('admin', isAdmin: true);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const AdminFleetMapScreen()),
                              (route) => false,
                            );
                            return;
                          } else {
                            if (!ctx.mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('This account does not have Admin privileges.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                        }
                      } catch (e) {
                        if (!ctx.mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Admin Login Failed: ${e.toString()}'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      } finally {
                        if (dialogCtx.mounted) {
                          setDialogState(() => isLoggingIn = false);
                        }
                      }
                    },
              child: isLoggingIn
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: C.black,
                      ),
                    )
                  : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class SignupScreen extends StatefulWidget {
  final bool asModal;
  const SignupScreen({super.key, this.asModal = false});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _authService = AuthService();
  bool _isRiderSignup = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  // Rider specific fields
  String _vehicleType = 'Bike';
  final _modelController = TextEditingController();
  final _plateController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _modelController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _authService.registerWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: _isRiderSignup ? 'rider' : 'customer',
        vehicleType: _isRiderSignup ? _vehicleType : null,
        vehicleModel: _isRiderSignup ? _modelController.text.trim() : null,
        plateNumber: _isRiderSignup ? _plateController.text.trim() : null,
      );
      if (mounted) {
        isRider.value = _isRiderSignup;
        if (widget.asModal) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeShell()), (r) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(children: [
              const SizedBox(height: 8),
              Center(
                child: Column(
                  children: [
                    const Logo(size: 48),
                    const SizedBox(height: 8),
                    Text(
                      _isRiderSignup ? 'Drive & Earn with ShanGo' : 'Join ShanGo today',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Role Selector Toggle
              Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFEFEF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isRiderSignup = false),
                        child: Container(
                          decoration: BoxDecoration(
                            color: !_isRiderSignup ? C.yellow : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Text('Customer', style: TextStyle(fontWeight: FontWeight.w800, color: C.black)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isRiderSignup = true),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _isRiderSignup ? C.yellow : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Text('Rider / Driver', style: TextStyle(fontWeight: FontWeight.w800, color: C.black)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                decoration: const InputDecoration(hintText: 'Full name', prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v != null && v.contains('@')) ? null : 'Enter a valid email',
                decoration: const InputDecoration(hintText: 'Email address', prefixIcon: Icon(Icons.email)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: (v) => (v != null && v.length >= 10) ? null : 'Enter valid phone number',
                decoration: const InputDecoration(hintText: '03XXXXXXXXX', prefixIcon: Icon(Icons.phone)),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                validator: (v) => (v != null && v.length >= 6) ? null : 'Minimum 6 characters',
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.black54),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.black54,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),

              // Rider Vehicle Form Fields
              if (_isRiderSignup) ...[
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Vehicle Information', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleType,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.two_wheeler)),
                  items: const [
                    DropdownMenuItem(value: 'Bike', child: Text('Motorbike / Scooter')),
                    DropdownMenuItem(value: 'Auto', child: Text('Rickshaw / Auto')),
                    DropdownMenuItem(value: 'Car', child: Text('Car / Taxi')),
                  ],
                  onChanged: (v) => setState(() => _vehicleType = v ?? 'Bike'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _modelController,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter vehicle model' : null,
                  decoration: const InputDecoration(hintText: 'Vehicle Model (e.g. Honda CD70)', prefixIcon: Icon(Icons.electric_moped)),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _plateController,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter number plate' : null,
                  decoration: const InputDecoration(hintText: 'Plate Number (e.g. BNU-1234)', prefixIcon: Icon(Icons.badge)),
                ),

                // Transparent Commission & Earnings Info
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF166534),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.monetization_on, color: C.yellow, size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'ShanGo Earnings & Commission Policy',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Color(0xFF166534),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFDCFCE7)),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Your Payout', style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 2),
                                  Text('85% Fare', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF15803D))),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFDCFCE7)),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ShanGo Platform Fee', style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 2),
                                  Text('15% Commission', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFFB45309))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• Example: On a PKR 1,000 trip, you keep PKR 850 net earnings.\n• Transparent pricing with zero hidden deduction fees.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF14532D), height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              PrimaryButton(
                _isRiderSignup ? 'Register as Rider' : 'Sign up',
                isLoading: _isLoading,
                onTap: _isLoading ? null : _handleSignup,
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: RichText(
                    text: const TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(color: Colors.black54, fontSize: 14),
                      children: [
                        TextSpan(
                          text: 'Log in',
                          style: TextStyle(color: C.black, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}
