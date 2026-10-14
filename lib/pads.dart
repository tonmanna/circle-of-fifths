import 'package:flutter/material.dart';

import 'chords.dart';

/// Palette and type helpers live in main.dart; passed in to keep this file free of app imports.
typedef PadTheme = ({
  Color cream,
  Color ink,
  Color gold,
  Color woodDark,
  Color woodMid,
  Color woodLight,
  TextStyle Function(double, Color) display,
  TextStyle Function(double, Color) label,
});

/// 3×3 chord pads. [pressed] is the pad shown held down; tapping any pad calls [onTap]
/// with the global touch point (for particles).
class ChordPads extends StatelessWidget {
  const ChordPads({super.key, required this.chords, required this.pressed, required this.onTap, required this.t});
  final List<PadChord> chords;
  final int pressed;
  final void Function(int index, Offset global) onTap;
  final PadTheme t;

  /// Each row is one musical job, labelled so learners see why the chords sit together.
  static const _groups = ['Primary · home, away, return', 'Relative minors · softer colour', 'Tension & borrowed'];
  // Same left-to-right order as the wheel: V on the left, IV on the right (the wheel runs
  // in fourths clockwise), with each major's relative minor directly beneath it.
  static const _rows = [
    [5, 4, 3], // V I IV
    [2, 1, 0], // iii vi ii
    [7, 8, 6], // vii° iv ♭VII  (sharp side left, flat side right)
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (g, row) in _rows.indexed) ...[
        if (g > 0) const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 4),
          child: Text(_groups[g], style: t.label(13, t.cream.withValues(alpha: 0.85))),
        ),
        Row(
          children: [
            for (final (k, i) in row.indexed) ...[
              if (k > 0) const SizedBox(width: 8),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 2.1,
                  child: _Pad(chords[i], home: i == padCenter, down: i == pressed, onTap: (p) => onTap(i, p), t: t),
                ),
              ),
            ],
          ],
        ),
      ],
    ],
  );
}

class _Pad extends StatelessWidget {
  const _Pad(this.c, {required this.home, required this.down, required this.onTap, required this.t});
  final PadChord c;
  final bool home, down;
  final void Function(Offset global) onTap;
  final PadTheme t;

  @override
  Widget build(BuildContext context) {
    final maple = home || down;
    final fg = maple ? t.ink : t.cream;
    return Semantics(
      button: true,
      selected: down,
      label: '${c.numeral}, ${c.name}, play chord',
      child: GestureDetector(
        onTapDown: (e) => onTap(e.globalPosition),
        child: AnimatedScale(
          // Pressed pad sinks slightly, like a real pad under a finger.
          scale: down ? 0.94 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: maple ? t.woodLight : t.woodDark,
              image: DecorationImage(
                image: AssetImage(maple ? 'assets/wood/maple.jpg' : 'assets/wood/walnut.jpg'),
                fit: BoxFit.cover,
                colorFilter: maple ? null : const ColorFilter.mode(Color(0x8C1E140E), BlendMode.srcOver),
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: down ? t.gold : (maple ? t.woodLight : t.woodMid), width: down ? 2 : 1),
              boxShadow: [
                // Raised when idle, flush when pressed.
                if (!down) const BoxShadow(color: Color(0x66000000), offset: Offset(0, 3), blurRadius: 4),
                if (down) BoxShadow(color: t.gold.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 1),
              ],
            ),
            child: Stack(
              children: [
                Positioned(left: 10, top: 4, child: Text(c.numeral, style: t.display(14, fg.withValues(alpha: 0.85)))),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(c.name, style: t.display(24, fg)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Guitar chord box: 6 strings, 4 frets, dots for fingers, x/o above the nut.
class GuitarDiagram extends StatelessWidget {
  const GuitarDiagram({super.key, required this.shape, required this.t});
  final List<int> shape;
  final PadTheme t;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Guitar fingering, low to high: ${shape.map((f) => f < 0 ? 'muted' : '$f').join(', ')}',
    child: CustomPaint(size: const Size(140, 100), painter: _GuitarPainter(shape, t)),
  );
}

class _GuitarPainter extends CustomPainter {
  _GuitarPainter(this.shape, this.t);
  final List<int> shape;
  final PadTheme t;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 26.0, left = 26.0, frets = 4;
    final w = size.width - left - 10, h = size.height - top - 6;
    final dx = w / 5, dy = h / frets;
    final fretted = shape.where((f) => f > 0);
    final low = fretted.isEmpty ? 1 : fretted.reduce((a, b) => a < b ? a : b);
    final base = fretted.isEmpty || fretted.reduce((a, b) => a > b ? a : b) <= frets ? 1 : low;
    final line = Paint()
      ..color = t.cream.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;

    for (var s = 0; s < 6; s++) {
      canvas.drawLine(Offset(left + s * dx, top), Offset(left + s * dx, top + h), line);
    }
    for (var f = 0; f <= frets; f++) {
      final p = f == 0 && base == 1
          ? (Paint()
              ..color = t.cream
              ..strokeWidth = 4)
          : line;
      canvas.drawLine(Offset(left, top + f * dy), Offset(left + w, top + f * dy), p);
    }
    if (base > 1) _text(canvas, '${base}fr', Offset(left - 14, top + dy / 2), 12);

    final dot = Paint()..color = t.gold;
    for (final (s, f) in shape.indexed) {
      final x = left + s * dx;
      if (f < 0) {
        _text(canvas, '×', Offset(x, top - 12), 14);
      } else if (f == 0) {
        canvas.drawCircle(Offset(x, top - 11), 5, line..style = PaintingStyle.stroke);
        line.style = PaintingStyle.fill;
      } else {
        canvas.drawCircle(Offset(x, top + (f - base + 0.5) * dy), dx * 0.36, dot);
      }
    }
  }

  void _text(Canvas c, String s, Offset at, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: t.label(size, t.cream)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_GuitarPainter old) => old.shape.join() != shape.join();
}

/// Two-octave keyboard from C3 with the chord's notes lit.
class PianoDiagram extends StatelessWidget {
  const PianoDiagram({super.key, required this.midi, required this.t});
  final List<int> midi;
  final PadTheme t;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Piano keys: ${midi.map((m) => notes[m % 12]).join(' ')}',
    child: CustomPaint(size: const Size(double.infinity, 90), painter: _PianoPainter(midi.toSet(), t)),
  );
}

class _PianoPainter extends CustomPainter {
  _PianoPainter(this.lit, this.t);
  final Set<int> lit;
  final PadTheme t;

  static const _start = 36, _octaves = 3; // C2..B4 covers the doubled bass root
  static const _whiteSteps = [0, 2, 4, 5, 7, 9, 11];

  @override
  void paint(Canvas canvas, Size size) {
    final whites = [
      for (var o = 0; o < _octaves; o++)
        for (final s in _whiteSteps) _start + o * 12 + s,
    ];
    final ww = size.width / whites.length;
    final r = const Radius.circular(3);
    final white = Paint()..color = t.cream;
    final black = Paint()..color = const Color(0xFF1A110C);
    final hit = Paint()..color = t.gold;
    final edge = Paint()
      ..color = const Color(0xFF1A110C)
      ..style = PaintingStyle.stroke;

    for (final (i, m) in whites.indexed) {
      final rect = RRect.fromRectAndCorners(Rect.fromLTWH(i * ww, 0, ww, size.height), bottomLeft: r, bottomRight: r);
      canvas
        ..drawRRect(rect, lit.contains(m) ? hit : white)
        ..drawRRect(rect, edge);
    }
    for (final (i, m) in whites.indexed) {
      final step = m % 12;
      if (step == 4 || step == 11) continue; // no black key after E or B
      final b = m + 1;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH((i + 1) * ww - ww * 0.3, 0, ww * 0.6, size.height * 0.6),
        bottomLeft: r,
        bottomRight: r,
      );
      canvas.drawRRect(rect, lit.contains(b) ? hit : black);
    }
  }

  @override
  bool shouldRepaint(_PianoPainter old) => old.lit.length != lit.length || !old.lit.containsAll(lit);
}
