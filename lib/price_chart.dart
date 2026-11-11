import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format.dart';
import 'price_history.dart';

// Ruang kosong di sekeliling area grafik (untuk label sumbu)
const double _padLeft = 8;
const double _padRight = 76;
const double _padTop = 12;
const double _padBottom = 24;

/// Tampilan grafik garis (harga)
class PriceChart extends StatefulWidget {
  final List<PricePoint> points;
  final PricePeriod period;

  const PriceChart({super.key, required this.points, required this.period});

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? _touchIndex;

  @override
  void didUpdateWidget(covariant PriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) _touchIndex = null;
  }

  // Mengubah posisi sentuhan (x) menjadi index titik data terdekat
  void _touch(double dx, double width) {
    final n = widget.points.length;
    final w = width - _padLeft - _padRight;
    if (n < 2 || w <= 0) return;
    final t = ((dx - _padLeft) / w).clamp(0.0, 1.0);
    setState(() => _touchIndex = (t * (n - 1)).round());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _touch(d.localPosition.dx, c.maxWidth),
          onHorizontalDragStart: (d) => _touch(d.localPosition.dx, c.maxWidth),
          onHorizontalDragUpdate: (d) => _touch(d.localPosition.dx, c.maxWidth),
          child: CustomPaint(
            size: Size.infinite,
            painter: _ChartPainter(
              points: widget.points,
              period: widget.period,
              touchIndex: _touchIndex,
            ),
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<PricePoint> points;
  final PricePeriod period;
  final int? touchIndex;

  _ChartPainter({
    required this.points,
    required this.period,
    required this.touchIndex,
  });

  static const _up = Color(0xFF2E7D32);
  static const _upFill = Color(0x222E7D32);
  static const _down = Color(0xFFC62828);
  static const _downFill = Color(0x22C62828);
  static const _grid = Color(0xFFE0E0E0);
  static const _label = Color(0xFF616161);

  TextPainter _text(String text, TextStyle style) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    final w = size.width - _padLeft - _padRight;
    final h = size.height - _padTop - _padBottom;
    if (n < 2 || w <= 0 || h <= 0) return;

    // Rentang harga (min-max) + sedikit ruang atas/bawah
    var minP = points.first.price;
    var maxP = minP;
    for (final p in points) {
      if (p.price < minP) minP = p.price;
      if (p.price > maxP) maxP = p.price;
    }
    var range = maxP - minP;
    if (range <= 0) range = maxP.abs() * 0.02;
    if (range <= 0) range = 1;
    final lo = minP - range * 0.08;
    final hi = maxP + range * 0.08;
    final span = hi - lo;

    double xOf(int i) => _padLeft + w * i / (n - 1);
    double yOf(double price) => _padTop + h * (1 - (price - lo) / span);

    // Garis bantu horizontal + label harga di sisi kanan
    const labelStyle = TextStyle(fontSize: 10, color: _label);
    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = _padTop + h * i / 4;
      canvas.drawLine(Offset(_padLeft, y), Offset(_padLeft + w, y), gridPaint);
      final tp = _text(
        formatUsdShort(hi - span * i / 4, withPrefix: false),
        labelStyle,
      );
      tp.paint(canvas, Offset(_padLeft + w + 6, y - tp.height / 2));
    }

    // Label waktu di sumbu X (4 titik)
    for (var k = 0; k < 4; k++) {
      final i = ((n - 1) * k / 3).round();
      final tp = _text(formatAxisDate(points[i].time, period), labelStyle);
      final maxDx = math.max(0.0, _padLeft + w - tp.width);
      final dx = (xOf(i) - tp.width / 2).clamp(0.0, maxDx).toDouble();
      tp.paint(canvas, Offset(dx, _padTop + h + 6));
    }

    // Garis harga + area di bawahnya (hijau jika naik, merah jika turun)
    final rising = points.last.price >= points.first.price;
    final path = Path()..moveTo(xOf(0), yOf(points.first.price));
    for (var i = 1; i < n; i++) {
      path.lineTo(xOf(i), yOf(points[i].price));
    }
    final area = Path.from(path)
      ..lineTo(xOf(n - 1), _padTop + h)
      ..lineTo(xOf(0), _padTop + h)
      ..close();
    canvas.drawPath(area, Paint()..color = rising ? _upFill : _downFill);
    canvas.drawPath(
      path,
      Paint()
        ..color = rising ? _up : _down
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Penanda sentuhan + tooltip
    final ti = touchIndex;
    if (ti != null && ti >= 0 && ti < n) {
      final x = xOf(ti);
      final y = yOf(points[ti].price);

      canvas.drawLine(
        Offset(x, _padTop),
        Offset(x, _padTop + h),
        Paint()
          ..color = _label
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, y),
        3.5,
        Paint()..color = rising ? _up : _down,
      );

      final priceTp = _text(
        formatUsd(points[ti].price),
        const TextStyle(
          fontSize: 12,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      );
      final dateTp = _text(
        formatFullDate(points[ti].time, period),
        const TextStyle(fontSize: 10, color: Colors.white70),
      );
      final boxW = math.max(priceTp.width, dateTp.width) + 16;
      final boxH = priceTp.height + dateTp.height + 12;
      final maxLeft = math.max(0.0, size.width - boxW);
      final left = (x - boxW / 2).clamp(0.0, maxLeft).toDouble();
      final top = _padTop + 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, boxW, boxH),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xEE263238),
      );
      priceTp.paint(canvas, Offset(left + 8, top + 5));
      dateTp.paint(canvas, Offset(left + 8, top + 5 + priceTp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.points != points ||
      old.period != period ||
      old.touchIndex != touchIndex;
}
