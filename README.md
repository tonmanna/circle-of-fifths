# Circle of Fifths

A Flutter app (iOS & Android) for guitar and piano learners: spin a wooden circle-of-fifths wheel to pick a key, then play its chords on a 3×3 pad.

- **Wheel** — swipe to rotate or tap a key; snaps with haptics, plays the I chord, and sheds gold dust.
- **Chord pads** — 9 chords grouped by role (primary, relative minors, tension & borrowed), laid out in the wheel's order. Tap to play.
- **Guitar / Piano** — sound and diagram follow the setting: a chord box for guitar, a lit keyboard for piano. Sounds are synthesized in code (`lib/synth.dart`), no audio files.
- **Correct spelling** — chords are spelled per key (D major → F♯m, C♯dim).
- Portrait and landscape layouts; respects the OS "reduce motion" setting.

## Run

```sh
flutter pub get
flutter run
flutter test
```

Release APK: `flutter build apk --release` (currently signed with the debug key; add a release keystore before publishing to Play Store).

## Credits

Fonts: Libre Caslon Text, Libre Franklin, Noto Music (subset), all SIL Open Font License; see `assets/fonts/`. Icon, splash and wood textures were generated with an image model.
