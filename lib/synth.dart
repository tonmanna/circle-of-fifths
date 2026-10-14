import 'dart:math';
import 'dart:typed_data';

enum Instrument { piano, guitar, off }

const _rate = 44100;
const _seconds = 1.8;

double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

/// Renders [midi] notes as a 16-bit mono WAV.
Uint8List chordWav(List<int> midi, Instrument inst) {
  final n = (_rate * _seconds).round();
  final mix = Float64List(n);
  for (final (i, m) in midi.indexed) {
    final f = _hz(m);
    if (inst == Instrument.guitar) {
      _pluck(mix, f, start: (i * 0.03 * _rate).round(), seed: m); // downstroke strum
    } else {
      _strike(mix, f);
    }
  }
  final peak = mix.fold<double>(0, (a, v) => max(a, v.abs()));
  final gain = peak == 0 ? 0 : 0.8 / peak;

  final data = ByteData(44 + n * 2);
  void str(int o, String s) {
    for (final (i, c) in s.codeUnits.indexed) {
      data.setUint8(o + i, c);
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVEfmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, _rate, Endian.little)
    ..setUint32(28, _rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final fadeOut = min(1.0, (n - i) / (_rate * 0.05)); // avoid a click at the end
    data.setInt16(44 + i * 2, (mix[i] * gain * fadeOut * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Piano-ish: a few decaying harmonics with a soft hammer attack.
// ponytail: additive approximation, swap for SoundFont samples if realism matters.
void _strike(Float64List out, double f) {
  const harmonics = [1.0, 0.5, 0.3, 0.15, 0.08];
  for (var i = 0; i < out.length; i++) {
    final t = i / _rate;
    final attack = min(1.0, t / 0.004);
    var s = 0.0;
    for (final (h, amp) in harmonics.indexed) {
      s += amp * exp(-t * (1.8 + h * 1.2)) * sin(2 * pi * f * (h + 1) * t);
    }
    out[i] += s * attack;
  }
}

/// Guitar: Karplus-Strong plucked string.
void _pluck(Float64List out, double f, {required int start, required int seed}) {
  final period = (_rate / f).round();
  final rnd = Random(seed);
  final buf = Float64List.fromList(List.generate(period, (_) => rnd.nextDouble() * 2 - 1));
  for (var i = start, k = 0; i < out.length; i++, k++) {
    final j = k % period;
    final v = buf[j];
    buf[j] = 0.996 * 0.5 * (v + buf[(j + 1) % period]);
    out[i] += v * 0.6;
  }
}
