import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nooka/ui/core/color_contrast.dart';

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const lightSurface = Color(0xFFFFFFFF);
  const darkSurface = Color(0xFF121212);

  test('raises a low-contrast color to >= 4.5:1 on a light surface', () {
    const orange = Color(0xFFFB8C00); // palette orange: weak on white
    final out = readableOn(orange, lightSurface);
    expect(_ratio(out, lightSurface), greaterThanOrEqualTo(4.5));
  });

  test('raises a low-contrast color to >= 4.5:1 on a dark surface', () {
    const purple = Color(0xFF5E35B1); // palette purple: weak on near-black
    final out = readableOn(purple, darkSurface);
    expect(_ratio(out, darkSurface), greaterThanOrEqualTo(4.5));
  });

  test('returns the color unchanged when it already passes', () {
    const black = Color(0xFF000000);
    expect(readableOn(black, lightSurface), black);
  });

  test('returns the clamped extreme when no candidate can meet the ratio', () {
    // minRatio above the theoretical max (21) is never satisfiable, so the
    // search exhausts and falls back to the clamped extreme.
    final result = readableOn(
      const Color(0xFF808080),
      const Color(0xFFFFFFFF),
      minRatio: 99,
    );
    expect(
      result,
      const Color(0xFF000000),
    ); // black: darkest on a light surface
  });
}
