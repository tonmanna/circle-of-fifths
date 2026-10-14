import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Full-screen overlay of glowing gold dust. Call [ParticlesState.burst] / [ParticlesState.ring]
/// with global coordinates. Ignores touches, and does nothing when the OS asks for reduced motion.
///
/// Performance: particles live in flat typed arrays (no per-particle objects), the glow is one
/// pre-rendered sprite, and every frame is a single `drawRawAtlas` call driven by a repaint
/// notifier, so the widget tree never rebuilds while particles move.
class Particles extends StatefulWidget {
  const Particles({super.key, required this.child});
  final Widget child;
  @override
  State<Particles> createState() => ParticlesState();
}

class ParticlesState extends State<Particles> with SingleTickerProviderStateMixin {
  static const _palette = [0xFFFFE3A3, 0xFFE0B887, 0xFFF2E2C6, 0xFFD9A441];
  static const _max = 300; // ring 56 + generous touch trails; oldest are recycled past this

  // Structure of arrays, ring buffer of _max slots.
  final _x = Float32List(_max), _y = Float32List(_max), _vx = Float32List(_max), _vy = Float32List(_max);
  final _age = Float32List(_max), _life = Float32List(_max), _size = Float32List(_max);
  final _color = Int32List(_max);
  int _next = 0, _alive = 0;

  final _rnd = Random();
  late final Ticker _ticker;
  final _repaint = ValueNotifier(0);
  Duration _last = Duration.zero;
  late final ui.Image _sprite;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _sprite = _makeSprite();
  }

  /// Soft radial glow with a bright core, white so the atlas can tint it per particle.
  static ui.Image _makeSprite() {
    const s = 64.0;
    final rec = ui.PictureRecorder();
    Canvas(rec).drawCircle(
      const Offset(s / 2, s / 2),
      s / 2,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(s / 2, s / 2),
          s / 2,
          const [Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF)],
          const [0, 0.12, 0.35, 1],
        ),
    );
    return rec.endRecording().toImageSync(s.toInt(), s.toInt());
  }

  bool get _enabled => !MediaQuery.disableAnimationsOf(context);

  Offset _local(Offset global) => (context.findRenderObject() as RenderBox).globalToLocal(global);

  void _spawn(Offset at, Offset v, double life, double size) {
    final i = _next;
    _next = (_next + 1) % _max;
    _x[i] = at.dx;
    _y[i] = at.dy;
    _vx[i] = v.dx;
    _vy[i] = v.dy;
    _age[i] = 0;
    _life[i] = life;
    _size[i] = size;
    _color[i] = _palette[_rnd.nextInt(_palette.length)];
    _alive = max(_alive, 1);
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  /// Sparks flung out in every direction from [global].
  void burst(Offset global, {int count = 14, double speed = 140}) {
    if (!_enabled) return;
    final at = _local(global);
    for (var i = 0; i < count; i++) {
      final v = Offset.fromDirection(_rnd.nextDouble() * 2 * pi, speed * (0.3 + _rnd.nextDouble()));
      _spawn(at, v, 0.5 + _rnd.nextDouble() * 0.6, 1.2 + _rnd.nextDouble() * 2.4);
    }
  }

  /// Dust lifting off the rim of a circle, as if the wheel shed its gilding.
  void ring(Offset globalCenter, double radius, {int count = 56}) {
    if (!_enabled) return;
    final c = _local(globalCenter);
    for (var i = 0; i < count; i++) {
      final a = i / count * 2 * pi + _rnd.nextDouble() * 0.1;
      final out = Offset.fromDirection(a, 1);
      final v = out * (40 + _rnd.nextDouble() * 70) + Offset.fromDirection(a + pi / 2, 30);
      _spawn(c + out * radius, v, 0.7 + _rnd.nextDouble() * 0.6, 1 + _rnd.nextDouble() * 2);
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : min(0.05, (now - _last).inMicroseconds / 1e6);
    _last = now;
    final drag = pow(0.06, dt).toDouble(); // velocity keeps 6% per second
    final g = 60 * dt; // light gravity: dust settles
    var alive = 0;
    for (var i = 0; i < _max; i++) {
      if (_age[i] >= _life[i]) continue;
      _age[i] += dt;
      if (_age[i] >= _life[i]) continue;
      alive++;
      _vx[i] *= drag;
      _vy[i] = _vy[i] * drag + g;
      _x[i] += _vx[i] * dt;
      _y[i] += _vy[i] * dt;
    }
    _alive = alive;
    if (alive == 0) _ticker.stop();
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _sprite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(child: CustomPaint(painter: _Painter(this))),
        ),
      ),
    ],
  );
}

class _Painter extends CustomPainter {
  _Painter(this.s) : super(repaint: s._repaint);
  final ParticlesState s;

  static const _max = ParticlesState._max;
  // Reused across frames; sized for the worst case.
  final _xf = Float32List(_max * 4);
  final _rect = Float32List(_max * 4);
  final _colors = Int32List(_max);
  final _paint = Paint()
    ..blendMode = BlendMode.plus
    ..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    if (s._alive == 0) return;
    final sprite = s._sprite;
    final half = sprite.width / 2;
    var n = 0;
    for (var i = 0; i < _max; i++) {
      final age = s._age[i], life = s._life[i];
      if (age >= life) continue;
      final t = age / life;
      final fade = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;
      // Twinkle: brightness flickers a little over life.
      final a = (fade * (0.75 + 0.25 * sin(age * 30 + s._size[i] * 10))).clamp(0.0, 1.0);
      // Sprite covers the glow radius, 3x the core size, shrinking as it fades.
      final scale = s._size[i] * 3 * (1 - t * 0.4) / half;
      final j = n * 4;
      _xf[j] = scale;
      _xf[j + 1] = 0;
      _xf[j + 2] = s._x[i] - half * scale;
      _xf[j + 3] = s._y[i] - half * scale;
      _rect[j] = 0;
      _rect[j + 1] = 0;
      _rect[j + 2] = sprite.width.toDouble();
      _rect[j + 3] = sprite.height.toDouble();
      _colors[n] = ((a * 255).round() << 24) | (s._color[i] & 0xFFFFFF);
      n++;
    }
    if (n == 0) return;
    canvas.drawRawAtlas(
      sprite,
      Float32List.sublistView(_xf, 0, n * 4),
      Float32List.sublistView(_rect, 0, n * 4),
      Int32List.sublistView(_colors, 0, n),
      BlendMode.modulate, // tint the white sprite by each particle's color and alpha
      null,
      _paint,
    );
  }

  @override
  bool shouldRepaint(_Painter old) => old.s != s;
}
