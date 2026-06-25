import 'package:flutter/material.dart';

/// Returns a variant of [color] whose WCAG contrast ratio against [surface] is
/// at least [minRatio] (AA for normal text = 4.5). If [color] already passes it
/// is returned unchanged. Otherwise its HSL lightness is stepped away from the
/// surface (darker on light surfaces, lighter on dark ones) until the ratio is
/// met or the color reaches black/white.
Color readableOn(Color color, Color surface, {double minRatio = 4.5}) {
  if (_contrastRatio(color, surface) >= minRatio) return color;
  final hsl = HSLColor.fromColor(color);
  final darken = surface.computeLuminance() > 0.5;
  var lightness = hsl.lightness;
  for (var i = 0; i < 100; i++) {
    lightness = (darken ? lightness - 0.02 : lightness + 0.02).clamp(0.0, 1.0);
    final candidate = hsl.withLightness(lightness).toColor();
    if (_contrastRatio(candidate, surface) >= minRatio) return candidate;
  }
  return hsl.withLightness(darken ? 0.0 : 1.0).toColor();
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
