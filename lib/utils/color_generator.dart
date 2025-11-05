import 'dart:math';
import 'dart:ui';

/// Utility class for generating random HSL colors
class ColorGenerator {
  static final Random _random = Random();

  /// Generate a random vibrant color using HSL
  static Color randomColor() {
    final (hue, saturation, lightness) = generateRandomHSL(
      minHue: 0,
      maxHue: 360,
      minSaturation: 0.5,
      maxSaturation: 1.0,
      minLightness: 0.5,
      maxLightness: 0.7,
    );

    return colorFromHSL(hue, saturation, lightness);
  }

  /// Convert HSL to RGB Color
  static Color colorFromHSL(double hue, double saturation, double lightness) {
    // Ensure hue is within [0, 360] range
    hue = hue % 360;

    // Ensure saturation and lightness are within [0, 1] range
    saturation = saturation.clamp(0.0, 1.0);
    lightness = lightness.clamp(0.0, 1.0);

    final chroma = (1 - (2 * lightness - 1).abs()) * saturation;
    final huePrime = hue / 60.0;
    final x = chroma * (1 - ((huePrime % 2) - 1).abs());

    double r, g, b;
    if (huePrime >= 0 && huePrime < 1) {
      r = chroma;
      g = x;
      b = 0;
    } else if (huePrime >= 1 && huePrime < 2) {
      r = x;
      g = chroma;
      b = 0;
    } else if (huePrime >= 2 && huePrime < 3) {
      r = 0;
      g = chroma;
      b = x;
    } else if (huePrime >= 3 && huePrime < 4) {
      r = 0;
      g = x;
      b = chroma;
    } else if (huePrime >= 4 && huePrime < 5) {
      r = x;
      g = 0;
      b = chroma;
    } else {
      r = chroma;
      g = 0;
      b = x;
    }

    final m = lightness - 0.5 * chroma;
    r += m;
    g += m;
    b += m;

    return Color.fromARGB(
      255,
      (r * 255).round(),
      (g * 255).round(),
      (b * 255).round(),
    );
  }

  /// Generate random HSL values within specified ranges
  static (double, double, double) generateRandomHSL({
    double minHue = 0,
    double maxHue = 360,
    double minSaturation = 0,
    double maxSaturation = 1,
    double minLightness = 0,
    double maxLightness = 1,
  }) {
    final hue = _random.nextDouble() * (maxHue - minHue) + minHue;
    final saturation =
        _random.nextDouble() * (maxSaturation - minSaturation) + minSaturation;
    final lightness =
        _random.nextDouble() * (maxLightness - minLightness) + minLightness;

    return (hue, saturation, lightness);
  }
}


