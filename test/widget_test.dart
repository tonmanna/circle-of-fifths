import 'package:circle_of_fourths/chords.dart';
import 'package:circle_of_fourths/main.dart';
import 'package:circle_of_fourths/synth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('circle order', () {
    expect(circle.map((p) => notes[p]).join(' '), 'C F B♭ E♭ A♭ D♭ G♭ B E A D G');
  });

  test('pad chords', () {
    expect(padChords(0).map((c) => c.name), ['Dm', 'Am', 'Em', 'F', 'C', 'G', 'B♭', 'Bdim', 'Fm']);
    expect(padChords(7).map((c) => c.name), ['Am', 'Em', 'Bm', 'C', 'G', 'D', 'F', 'F♯dim', 'Cm']);
    expect(padChords(2).map((c) => c.name), ['Em', 'Bm', 'F♯m', 'G', 'D', 'A', 'C', 'C♯dim', 'Gm']);
    expect(padChords(2)[2].tones, ['F♯', 'A', 'C♯']);
    expect(padChords(3).map((c) => c.name), ['Fm', 'Cm', 'Gm', 'A♭', 'E♭', 'B♭', 'D♭', 'Ddim', 'A♭m']);
    expect(
      [for (var k = 0; k < 12; k++) relativeMinor(k)],
      ['Am', 'B♭m', 'Bm', 'Cm', 'C♯m', 'Dm', 'E♭m', 'Em', 'Fm', 'F♯m', 'Gm', 'G♯m'],
    );
    expect(padChords(0)[padCenter].tones, ['C', 'E', 'G']);
  });

  test('every chord spells with one letter per note, in every key', () {
    for (var key = 0; key < 12; key++) {
      for (final c in padChords(key)) {
        // Triads stack thirds: letters skip one each time (D-F-A, F♯-A-C♯).
        final idx = c.tones.map((n) => 'CDEFGAB'.indexOf(n[0])).toList();
        expect([(idx[1] - idx[0]) % 7, (idx[2] - idx[1]) % 7], [2, 2], reason: '${c.name} ${c.tones}');
        expect(c.tones.toSet().length, 3, reason: '${c.name} ${c.tones}');
      }
    }
  });

  test('guitar shapes sound the right notes', () {
    for (var key = 0; key < 12; key++) {
      for (final c in padChords(key)) {
        final shape = guitarShape(c);
        expect(shape.every((f) => f >= -1 && f <= 15), isTrue, reason: '${c.name} $shape');
        final pcs = guitarMidi(shape).map((m) => m % 12).toSet();
        final want = c.quality.intervals.map((i) => (c.root + i) % 12).toSet();
        expect(pcs, want, reason: '${c.name} $shape');
        // Lowest sounding note is the root (no inversions on a beginner diagram).
        expect(guitarMidi(shape).first % 12, c.root, reason: '${c.name} $shape');
      }
    }
    expect(guitarShape(padChords(0)[padCenter]), [-1, 3, 2, 0, 1, 0]); // open C
    expect(guitarShape(padChords(0)[5]), [3, 2, 0, 0, 0, 3]); // open G
  });

  test('chord wav', () {
    final c = padChords(0)[padCenter];
    expect(pianoMidi(c), [36, 48, 52, 55]); // C2 + C3 E3 G3
    for (final (inst, midi) in [(Instrument.piano, pianoMidi(c)), (Instrument.guitar, guitarMidi(guitarShape(c)))]) {
      final wav = chordWav(midi, inst);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(wav.length, 44 + (44100 * 1.8).round() * 2);
      expect(wav.skip(44).any((b) => b != 0), isTrue); // not silent
    }
  });

  for (final size in [const Size(390, 844), const Size(844, 390), const Size(360, 740)]) {
    testWidgets('no overflow at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: Home()));
      expect(t.takeException(), isNull);
      expect(find.text('Chords in C major'), findsOneWidget);
    });
  }

  testWidgets('rapid pad taps (A, B, A within a fade) do not crash the layout', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: Home()));
    for (final name in ['G', 'C', 'G', 'C']) {
      await t.tap(find.text(name).first);
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });
}
