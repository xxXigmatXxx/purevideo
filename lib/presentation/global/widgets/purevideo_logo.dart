import 'package:flutter/material.dart';

const Color kPureVideoRed = Color(0xFFE50914);
const Color kPureVideoDeepRed = Color(0xFFB1060F);
const Color kPureVideoDarkBg = Color(0xFF09090C);

/// Unified PureVideo geometric P+Play emblem matching ic_launcher and tv_banner 1:1.
class PureVideoMark extends StatelessWidget {
  final double size;
  final bool withDarkTile;

  const PureVideoMark({
    super.key,
    this.size = 28,
    this.withDarkTile = false,
  });

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PureVideoMarkPainter(),
      ),
    );
    if (!withDarkTile) return mark;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: kPureVideoDarkBg,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: Colors.white12, width: 0.8),
      ),
      child: CustomPaint(
        painter: _PureVideoMarkPainter(),
      ),
    );
  }
}

class _PureVideoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Normalized to the exact 0..108 emblem coordinates (bounding box ~28..84 x 20..88)
    final sx = size.width / 62.0;
    final sy = size.height / 72.0;
    final scale = sx < sy ? sx : sy;
    final dx = (size.width - 62.0 * scale) / 2.0 - 27.0 * scale;
    final dy = (size.height - 72.0 * scale) / 2.0 - 18.0 * scale;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    // 1. Vertical stem of P (deep crimson #B1060F)
    final stemPaint = Paint()
      ..color = kPureVideoDeepRed
      ..style = PaintingStyle.fill;
    final stemPath = Path()
      ..moveTo(31, 21)
      ..lineTo(46, 21)
      ..lineTo(46, 87)
      ..lineTo(31, 87)
      ..close();
    canvas.drawPath(stemPath, stemPaint);

    // 2. Curved ribbon loop of P (bright crimson #E50914)
    final loopPaint = Paint()
      ..color = kPureVideoRed
      ..style = PaintingStyle.fill;
    final loopPath = Path()
      ..moveTo(31, 21)
      ..lineTo(60, 21)
      ..cubicTo(75, 21, 83, 30.5, 83, 42.5)
      ..cubicTo(83, 54.5, 75, 64, 60, 64)
      ..lineTo(46, 64)
      ..lineTo(46, 52)
      ..lineTo(58.5, 52)
      ..cubicTo(65.5, 52, 69.5, 48, 69.5, 42.5)
      ..cubicTo(69.5, 37, 65.5, 33, 58.5, 33)
      ..lineTo(31, 33)
      ..close();
    canvas.drawPath(loopPath, loopPaint);

    // 3. White Play triangle inside the P bowl
    final playPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final playPath = Path()
      ..moveTo(50, 35.5)
      ..lineTo(64.5, 42.5)
      ..lineTo(50, 49.5)
      ..close();
    canvas.drawPath(playPath, playPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Unified PureVideo Emblem + "PureVideo" two-tone wordmark matching tv_banner.png.
class PureVideoWordmark extends StatelessWidget {
  final double height;
  final bool showText;

  const PureVideoWordmark({
    super.key,
    this.height = 28,
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PureVideoMark(size: height),
        if (showText) ...[
          SizedBox(width: height * 0.28),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: height * 0.72,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
                height: 1.0,
              ),
              children: const [
                TextSpan(
                  text: 'Pure',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: 'Video',
                  style: TextStyle(color: kPureVideoRed),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact badge rendered in top-left corner of movie posters.
class PureVideoPosterBadge extends StatelessWidget {
  final double size;

  const PureVideoPosterBadge({super.key, this.size = 13});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(175),
        borderRadius: BorderRadius.circular(4),
      ),
      child: PureVideoMark(size: size),
    );
  }
}
