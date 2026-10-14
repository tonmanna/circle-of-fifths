/// Key names as they appear on the wheel (flat side uses flats; G♭ rather than F♯).
const notes = ['C', 'D♭', 'D', 'E♭', 'E', 'F', 'G♭', 'G', 'A♭', 'A', 'B♭', 'B'];

const _letters = 'CDEFGAB';
const _naturalPc = [0, 2, 4, 5, 7, 9, 11];

/// Spells pitch class [pc] on the letter [steps] above [fromLetter] (C=0..B=6),
/// so D major gets F♯ (not G♭) and E♭ major gets A♭ (not G♯).
String spell(int pc, int fromLetter, int steps) {
  final l = (fromLetter + steps) % 7;
  final acc = switch ((pc - _naturalPc[l]) % 12) {
    0 => '',
    1 => '♯',
    2 => '𝄪',
    11 => '♭',
    10 => '𝄫',
    _ => throw StateError('pc $pc is not near ${_letters[l]}'),
  };
  return _letters[l] + acc;
}

/// Letter index of a key's tonic, from its wheel name.
int keyLetter(int key) => _letters.indexOf(notes[key][0]);

/// Relative minor spelled in the key (A major → F♯m, not G♭m).
String relativeMinor(int key) => '${spell((key + 9) % 12, keyLetter(key), 5)}m';

enum Quality {
  major('', [0, 4, 7]),
  minor('m', [0, 3, 7]),
  dim('dim', [0, 3, 6]);

  const Quality(this.suffix, this.intervals);
  final String suffix;
  final List<int> intervals;
}

/// [letter] is the root's letter index (C=0..B=6), fixing how the chord is spelled.
typedef PadChord = ({String numeral, int root, int letter, Quality quality});

extension PadChordX on PadChord {
  String get name => spell(root, letter, 0) + quality.suffix;
  List<String> get tones => [for (final (k, i) in quality.intervals.indexed) spell((root + i) % 12, letter, k * 2)];
}

/// The 9 pad chords of a key: (numeral, semitones above the key, scale degree for spelling, quality).
const padCenter = 4;
List<PadChord> padChords(int key) => [
  for (final (numeral, offset, degree, quality) in const [
    ('ii', 2, 1, Quality.minor),
    ('vi', 9, 5, Quality.minor),
    ('iii', 4, 2, Quality.minor),
    ('IV', 5, 3, Quality.major),
    ('I', 0, 0, Quality.major),
    ('V', 7, 4, Quality.major),
    ('♭VII', 10, 6, Quality.major),
    ('vii°', 11, 6, Quality.dim),
    ('iv', 5, 3, Quality.minor),
  ])
    (numeral: numeral, root: (key + offset) % 12, letter: (keyLetter(key) + degree) % 7, quality: quality),
];

/// Standard tuning, low E to high e, as MIDI notes.
const guitarStrings = [40, 45, 50, 55, 59, 64];

const _openShapes = {
  'C': [-1, 3, 2, 0, 1, 0],
  'D': [-1, -1, 0, 2, 3, 2],
  'G': [3, 2, 0, 0, 0, 3],
  'Dm': [-1, -1, 0, 2, 3, 1],
};

/// Fret per string, low E to high e; -1 = muted. Open chords where common,
/// otherwise the lower of the E-shape and A-shape barre positions.
List<int> guitarShape(PadChord c) {
  if (_openShapes[c.name] case final open?) return open;
  final e = (c.root - 4) % 12, a = (c.root - 9) % 12; // root's fret on the low E / A string
  return switch (c.quality) {
    Quality.dim => [-1, a, a + 1, a + 2, a + 1, -1],
    Quality.minor when e <= a => [e, e + 2, e + 2, e, e, e],
    Quality.major when e <= a => [e, e + 2, e + 2, e + 1, e, e],
    Quality.minor => [-1, a, a + 2, a + 2, a + 1, a],
    Quality.major => [-1, a, a + 2, a + 2, a + 2, a],
  };
}

List<int> guitarMidi(List<int> shape) => [
  for (final (i, f) in shape.indexed)
    if (f >= 0) guitarStrings[i] + f,
];

/// Close voicing from C3..B3 with the root doubled an octave below.
List<int> pianoMidi(PadChord c) {
  final r = 48 + c.root;
  return [r - 12, for (final i in c.quality.intervals) r + i];
}
