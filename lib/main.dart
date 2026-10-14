import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chords.dart';
import 'pads.dart';
import 'particles.dart';
import 'synth.dart';
import 'textures.dart';

const step = 2 * pi / 12;

/// Clockwise from the top: each key is a fourth above the previous (a fifth anticlockwise).
final circle = List.generate(12, (i) => i * 5 % 12);

// Wood palette.
const bg = Color(0xFF241812);
const woodDark = Color(0xFF4A3022);
const woodMid = Color(0xFF5E3D2B);
const woodNear = Color(0xFF9A6A44);
const woodLight = Color(0xFFE0B887);
const tan = Color(0xFFD4A574);
const gold = Color(0xFFB8925A);
const cream = Color(0xFFF2E2C6);
const ink = Color(0xFF2E1D14);

// Type: Libre Caslon Text (sturdy book serif, readable small) + Libre Franklin (labels).
// Neither has ♭/♯, so a 3-glyph Noto Music subset is the fallback for accidentals.
const _accidentals = ['NotoMusicAccidentals'];
const hintColor = Color(0xFFE8D3B0);

TextStyle display(double size, Color color, {double weight = 700}) => TextStyle(
  fontFamily: 'LibreCaslonText',
  fontFamilyFallback: _accidentals,
  fontSize: size,
  height: 1.1,
  color: color,
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  // Optical size follows font size: sturdier hairlines when small.
  fontVariations: [FontVariation.weight(weight)],
);

TextStyle label(double size, Color color, {double weight = 500, double tracking = 0}) => TextStyle(
  fontFamily: 'LibreFranklin',
  fontFamilyFallback: _accidentals,
  fontSize: size,
  letterSpacing: tracking,
  color: color,
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  fontVariations: [FontVariation.weight(weight)],
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  loadWoodTextures();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Circle of Fifths',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(seedColor: tan, brightness: Brightness.dark),
      ),
      home: const Home(),
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  late final _rot = AnimationController.unbounded(vsync: this)..addListener(_onRotate);
  int _selected = 0; // index into [circle], the key at 12 o'clock
  double? _lastAngle;
  // ponytail: instrument choice resets on launch; add shared_preferences if users want it remembered.
  Instrument _instrument = Instrument.piano;
  final _player = AudioPlayer();
  final _fx = GlobalKey<ParticlesState>();
  final _wheelKey = GlobalKey();
  final _wheelCache = _WheelCache();
  int _pressed = padCenter; // pad shown held down; follows the last chord played
  int _taps = 0; // unique key per diagram swap: C→G→C quickly must not give two 'C' children mid-fade

  List<PadChord> get _pads => padChords(_root);
  PadChord get _current => _pads[_pressed];

  /// Plays the pressed pad's chord, voiced as on the instrument (guitar uses the diagram's shape).
  /// WAVs are rendered once and cached in temp (audioplayers can't play raw bytes on iOS).
  Future<void> _play() async {
    if (_instrument == Instrument.off) return;
    final c = _current;
    final midi = _instrument == Instrument.guitar ? guitarMidi(guitarShape(c)) : pianoMidi(c);
    final file = File('${Directory.systemTemp.path}/chord_${_instrument.name}_${midi.join('-')}.wav');
    if (!file.existsSync()) await file.writeAsBytes(chordWav(midi, _instrument));
    await _player.stop();
    await _player.play(DeviceFileSource(file.path));
  }

  void _tapPad(int i, Offset global) {
    HapticFeedback.lightImpact();
    _fx.currentState?.burst(global, count: 10, speed: 110);
    setState(() {
      _pressed = i;
      _taps++;
    });
    _play();
  }

  PadTheme get _padTheme => (
    cream: cream,
    ink: ink,
    gold: gold,
    woodDark: woodDark,
    woodMid: woodMid,
    woodLight: woodLight,
    display: (size, color) => display(size, color),
    label: (size, color) => label(size, color, weight: 600),
  );

  void _onRotate() {
    final i = (-_rot.value / step).round() % 12;
    if (i != _selected) {
      HapticFeedback.selectionClick();
      setState(() {
        _selected = i;
        _pressed = padCenter;
      });
    }
  }

  double _angle(Offset p, Size s) => atan2(p.dy - s.height / 2, p.dx - s.width / 2);

  // Sound once the wheel settles, not on every key it passes while spinning.
  void _snapTo(double target) =>
      _rot.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOutBack).then((_) {
        _play();
        _celebrate();
      });

  /// Gold dust off the wheel's rim when it lands on a key.
  void _celebrate() {
    final box = _wheelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _fx.currentState?.ring(box.localToGlobal(box.size.center(Offset.zero)), box.size.width / 2);
  }

  void _bringToTop(int index) {
    final delta = ((index - _selected + 6) % 12) - 6; // shortest way round
    _snapTo(-(_selected + delta) * step);
  }

  @override
  void dispose() {
    _rot.dispose();
    _player.dispose();
    _wheelCache.dispose();
    super.dispose();
  }

  int get _root => circle[_selected];

  Widget get _soundMenu => PopupMenuButton<Instrument>(
    tooltip: 'Chord sound',
    iconSize: 22,
    icon: Icon(_instrument == Instrument.off ? Icons.volume_off_outlined : Icons.tune, color: cream),
    initialValue: _instrument,
    color: woodDark,
    onSelected: (i) {
      setState(() => _instrument = i);
      _play();
    },
    itemBuilder: (_) => [
      for (final (i, text) in [
        (Instrument.piano, 'Piano'),
        (Instrument.guitar, 'Guitar'),
        (Instrument.off, 'Sound off'),
      ])
        CheckedPopupMenuItem(
          value: i,
          checked: i == _instrument,
          child: Text(text, style: label(16, cream)),
        ),
    ],
  );

  Widget _wheel() => LayoutBuilder(
    builder: (context, c) {
      const pointer = 16.0;
      // Never negative: on a very short screen the wheel collapses rather than throwing.
      final d = max(0.0, min(c.maxWidth, c.maxHeight - pointer));
      final size = Size.square(d);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(size: const Size(20, pointer), painter: _Pointer()),
            GestureDetector(
              onPanStart: (e) {
                _fx.currentState?.burst(e.globalPosition, count: 8, speed: 80);
                _rot.stop();
                _lastAngle = _angle(e.localPosition, size);
              },
              onPanUpdate: (e) {
                final a = _angle(e.localPosition, size);
                var delta = a - _lastAngle!;
                if (delta > pi) delta -= 2 * pi;
                if (delta < -pi) delta += 2 * pi;
                _rot.value += delta;
                _lastAngle = a;
                // A trail of sparks follows the finger while spinning.
                if (Random().nextDouble() < 0.5) _fx.currentState?.burst(e.globalPosition, count: 2, speed: 50);
              },
              onPanEnd: (_) => _snapTo((_rot.value / step).round() * step),
              onTapUp: (e) {
                _fx.currentState?.burst(e.globalPosition);
                final a = _angle(e.localPosition, size) + pi / 2 - _rot.value;
                _bringToTop((a / step).round() % 12);
              },
              child: Semantics(
                label: 'Circle of fifths, selected key ${notes[_root]} major. Swipe to rotate.',
                // Own layer: spinning repaints only the wheel, not the background and cards.
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_rot, woodTextures]),
                    builder: (context, _) => CustomPaint(
                      key: _wheelKey,
                      size: size,
                      painter: _WheelPainter(
                        _rot.value,
                        _selected,
                        woodTextures.value,
                        MediaQuery.devicePixelRatioOf(context),
                        _wheelCache,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget get _padsAndDiagram {
    final t = _padTheme;
    final c = _current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChordPads(chords: _pads, pressed: _pressed, onTap: _tapPad, t: t),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Row(
            key: ValueKey('${c.name}-${_instrument.name}-$_taps'),
            children: [
              SizedBox(
                width: 92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: display(26, cream)),
                    const SizedBox(height: 4),
                    Text(c.tones.join(' · '), style: label(14, hintColor, weight: 600)),
                  ],
                ),
              ),
              Expanded(
                child: _instrument == Instrument.guitar
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: GuitarDiagram(shape: guitarShape(c), t: t),
                      )
                    : PianoDiagram(midi: pianoMidi(c), t: t),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Text get _chordsTitle => Text('Chords in ${notes[_root]} major', style: display(22, cream));
  Widget get _hint => Text('Swipe to rotate · tap a key to bring it up', style: label(14, hintColor, weight: 400));

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return Scaffold(
      body: Particles(
        key: _fx,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: bg,
            image: DecorationImage(image: AssetImage('assets/wood/bg.jpg'), fit: BoxFit.cover),
          ),
          child: SafeArea(
            child: portrait
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        // Slim header: the wheel scrolls up beneath it, so keep it out of the way.
                        padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
                        child: Row(
                          children: [
                            Expanded(child: Text('Circle of Fifths', style: display(20, cream))),
                            _soundMenu,
                          ],
                        ),
                      ),
                      // No scrolling: the wheel gets whatever height is left after the pads and diagram,
                      // so the pointer and selected key are always visible.
                      Expanded(
                        child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 4), child: _wheel()),
                      ),
                      Center(child: _hint),
                      Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 6), child: _chordsTitle),
                      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: _padsAndDiagram),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Padding(padding: const EdgeInsets.all(16), child: _wheel()),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 16, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  _chordsTitle,
                                  _soundMenu,
                                  Text('Swipe to rotate · tap a key', style: label(14, hintColor, weight: 400)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: _padsAndDiagram,
                                ),
                              ),
                            ],
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

class _Pointer extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) => canvas.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height * 0.75)
      ..close(),
    Paint()..color = gold,
  );

  @override
  bool shouldRepaint(_) => false;
}

/// Wheel art cached between frames. Wood, seams and rings only change with the selected key,
/// so they're rendered once into an image that is just rotated while spinning; labels stay
/// upright, so their laid-out text is cached and only repositioned.
class _WheelCache {
  ui.Image? disk;
  Object? diskKey;
  List<TextPainter> labels = [];
  Object? labelKey;

  void dispose() {
    disk?.dispose();
    for (final t in labels) {
      t.dispose();
    }
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.rotation, this.selected, this.wood, this.dpr, this.cache);
  final double rotation, dpr;
  final int selected;
  final WoodTextures? wood;
  final _WheelCache cache;

  static const _hubRatio = 0.42, _minorRatio = 0.70;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 1) return; // toImageSync can't make a 0×0 image
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final rMinor = r * _minorRatio, rHub = r * _hubRatio;

    final diskKey = (selected, wood, size, dpr);
    if (cache.diskKey != diskKey) {
      cache.disk?.dispose();
      cache.disk = _renderDisk(size);
      cache.diskKey = diskKey;
    }
    final disk = cache.disk!;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(rotation)
      ..drawImageRect(
        disk,
        Offset.zero & Size(disk.width.toDouble(), disk.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height),
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..restore();

    final labelKey = (selected, r);
    if (cache.labelKey != labelKey) {
      for (final t in cache.labels) {
        t.dispose();
      }
      final root = circle[selected];
      cache.labels = [
        for (var i = 0; i < 12; i++) ...[
          _layout(notes[circle[i]], display(r * 0.12, i == selected ? ink : cream)),
          _layout(relativeMinor(circle[i]), label(r * 0.08, cream, weight: 600)),
        ],
        _layout(notes[root], display(r * 0.28, cream)),
        _layout('major', label(r * 0.075, cream, weight: 600)),
        _layout('relative ${relativeMinor(root)}', label(r * 0.062, cream, weight: 500)),
      ];
      cache.labelKey = labelKey;
    }
    final l = cache.labels;
    for (var i = 0; i < 12; i++) {
      final mid = -pi / 2 + i * step + rotation;
      _paintAt(canvas, l[i * 2], center + Offset.fromDirection(mid, (r + rMinor) / 2));
      _paintAt(canvas, l[i * 2 + 1], center + Offset.fromDirection(mid, (rMinor + rHub) / 2));
    }
    _paintAt(canvas, l[24], center - Offset(0, r * 0.1));
    _paintAt(canvas, l[25], center + Offset(0, r * 0.12));
    _paintAt(canvas, l[26], center + Offset(0, r * 0.24));
  }

  /// Wedges, seams, hub and rings at rotation 0, at device resolution.
  ui.Image _renderDisk(Size size) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final rMinor = r * _minorRatio, rHub = r * _hubRatio;
    final seam = Paint()
      ..color = const Color(0xFF2A1A12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final fill = Paint()..isAntiAlias = true;

    for (var i = 0; i < 12; i++) {
      final mid = -pi / 2 + i * step;
      final d = ((i - selected) % 12 + 12) % 12;
      final isSel = d == 0, isNear = d == 1 || d == 11;
      for (final (outer, color) in [
        (r, isSel ? woodLight : (isNear ? woodNear : woodMid)),
        (rMinor, isSel ? const Color(0xFF7A5236) : woodDark),
      ]) {
        final rect = Rect.fromCircle(center: center, radius: outer);
        final wedge = Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(rect, mid - step / 2, step, false)
          ..close();
        final maple = isSel && outer == r;
        if (wood case final w?) {
          // Real wood, grain running along the wedge (radially), tinted to the segment's tone.
          final img = maple ? w.maple : w.walnut;
          final scale = (2 * outer) / img.width;
          final m = Matrix4.identity()
            ..translateByDouble(center.dx, center.dy, 0, 1)
            ..rotateZ(mid + pi / 2)
            ..scaleByDouble(scale, scale, 1, 1)
            ..translateByDouble(-img.width / 2, -img.height.toDouble() + (i * 37 % 100), 0, 1);
          fill
            ..color =
                const Color(0xFFFFFFFF) // opaque: the shared paint still holds the last tint's alpha
            ..shader = ImageShader(img, TileMode.mirror, TileMode.mirror, m.storage)
            ..colorFilter = ColorFilter.mode(color.withValues(alpha: maple ? 0.15 : 0.55), BlendMode.color);
          canvas.drawPath(wedge, fill);
          fill
            ..shader = null
            ..colorFilter = null
            ..color = color.withValues(alpha: maple ? 0.0 : 0.35);
          canvas.drawPath(wedge, fill);
        } else {
          fill.color = color;
          canvas.drawPath(wedge, fill);
        }
        canvas.drawArc(rect, mid - step / 2, step, true, seam);
      }
    }

    final ring = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke;
    canvas
      ..drawCircle(center, rHub, Paint()..color = const Color(0xFF1E140E))
      ..drawCircle(center, rHub, ring..strokeWidth = 2)
      ..drawCircle(center, rMinor, ring..strokeWidth = 1)
      ..drawCircle(center, r - 1.5, ring..strokeWidth = 3);
    final px = (size.width * dpr).ceil();
    return rec.endRecording().toImageSync(px, px);
  }

  TextPainter _layout(String s, TextStyle style) => TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  void _paintAt(Canvas c, TextPainter tp, Offset at) => tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.rotation != rotation || old.selected != selected || old.wood != wood || old.dpr != dpr;
}
