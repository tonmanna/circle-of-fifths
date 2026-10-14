import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef WoodTextures = ({ui.Image walnut, ui.Image maple});

/// Wood images for the wheel's CustomPainter, which needs decoded `ui.Image`s rather than widgets.
/// Null until loaded; the wheel paints flat colors meanwhile.
final woodTextures = ValueNotifier<WoodTextures?>(null);

Future<void> loadWoodTextures() async {
  Future<ui.Image> load(String name) async {
    final data = await rootBundle.load('assets/wood/$name.jpg');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 512);
    return (await codec.getNextFrame()).image;
  }

  woodTextures.value = (walnut: await load('walnut'), maple: await load('maple'));
}
