import 'package:flutter/material.dart';
import 'theme.dart';

/// Current mode: false = Customer, true = Rider.
final ValueNotifier<bool> isRider = ValueNotifier(false);

class Logo extends StatelessWidget {
  final double size;
  final bool dark; // true when placed on a black background
  final bool useImage;
  const Logo({super.key, this.size = 40, this.dark = false, this.useImage = true});

  @override
  Widget build(BuildContext context) {
    if (useImage) {
      return Image.asset(
        'assets/images/logo.jpg',
        height: size * 1.8,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _textLogo(),
      );
    }
    return _textLogo();
  }

  Widget _textLogo() => RichText(
        text: TextSpan(
          style: TextStyle(fontSize: size, fontWeight: FontWeight.w900),
          children: [
            TextSpan(text: 'Shan', style: TextStyle(color: dark ? C.white : C.black)),
            const TextSpan(text: 'Go', style: TextStyle(color: C.yellow)),
          ],
        ),
      );
}

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final Color? bg, fg;
  final bool isLoading;
  const PrimaryButton(
    this.text, {
    super.key,
    this.onTap,
    this.bg,
    this.fg,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: bg ?? C.yellow,
            foregroundColor: fg ?? C.black,
            disabledBackgroundColor: (bg ?? C.yellow).withValues(alpha: 0.6),
            disabledForegroundColor: (fg ?? C.black).withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          onPressed: isLoading ? null : onTap,
          child: isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: fg ?? C.black,
                  ),
                )
              : Text(text),
        ),
      );
}

class BottomCard extends StatelessWidget {
  final Widget child;
  const BottomCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: C.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16)],
        ),
        child: SafeArea(top: false, child: child),
      );
}

/// Replace with GoogleMap later.
class MapPlaceholder extends StatelessWidget {
  final bool route;
  const MapPlaceholder({super.key, this.route = false});
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _MapPainter(route))),
        if (!route) const Center(child: Padding(padding: EdgeInsets.only(bottom: 48), child: Icon(Icons.location_pin, size: 48, color: C.black))),
      ]);
}

class _MapPainter extends CustomPainter {
  final bool route;
  _MapPainter(this.route);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFE9E9E9));
    final road = Paint()..color = C.white..strokeWidth = 14;
    for (var i = 1; i < 6; i++) {
      final y = s.height * i / 6;
      c.drawLine(Offset(0, y), Offset(s.width, y + (i.isEven ? 30 : -20)), road);
    }
    for (var i = 1; i < 4; i++) {
      c.drawLine(Offset(s.width * i / 4, 0), Offset(s.width * i / 4 + 20, s.height), road);
    }
    if (route) {
      final path = Path()
        ..moveTo(s.width * .25, s.height * .3)
        ..lineTo(s.width * .25, s.height * .5)
        ..lineTo(s.width * .7, s.height * .5)
        ..lineTo(s.width * .7, s.height * .2);
      c.drawPath(path, Paint()..color = C.black..strokeWidth = 5..style = PaintingStyle.stroke);
      c.drawCircle(Offset(s.width * .25, s.height * .3), 9, Paint()..color = C.black);
      c.drawCircle(Offset(s.width * .7, s.height * .2), 9, Paint()..color = C.yellow);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
