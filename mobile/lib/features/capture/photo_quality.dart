import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class PhotoQualityIssue {
  final String code;
  final String message;

  const PhotoQualityIssue({
    required this.code,
    required this.message,
  });
}

class PhotoQualityResult {
  final double brightness;
  final double sharpness;
  final double contentCoverage;
  final List<PhotoQualityIssue> issues;

  const PhotoQualityResult({
    required this.brightness,
    required this.sharpness,
    required this.contentCoverage,
    required this.issues,
  });

  bool get shouldWarn => issues.isNotEmpty;
}

class PhotoQualityService {
  static const double _tooDark = 55;
  static const double _tooBright = 238;
  static const double _minSharpness = 85;
  static const double _minContentCoverage = 0.30;
  static const double _minContentWidthRatio = 0.52;
  static const double _minContentHeightRatio = 0.52;
  static const double _edgeTouchMarginRatio = 0.035;

  static Future<PhotoQualityResult> analyzeFile(File file) async {
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      return const PhotoQualityResult(
        brightness: 0,
        sharpness: 0,
        contentCoverage: 0,
        issues: [
          PhotoQualityIssue(
            code: 'decode',
            message: 'Photo could not be checked',
          ),
        ],
      );
    }
    return analyzeImage(image);
  }

  static PhotoQualityResult analyzeImage(img.Image image) {
    final sample = _resizeForAnalysis(image);
    final gray = _grayscale(sample);
    final brightness = _average(gray);
    final sharpness = _laplacianVariance(gray, sample.width, sample.height);
    final bounds = _edgeBounds(gray, sample.width, sample.height);
    final contentCoverage = bounds == null
        ? 0.0
        : (bounds.width * bounds.height) / (sample.width * sample.height);
    final issues = <PhotoQualityIssue>[];

    if (brightness < _tooDark) {
      issues.add(const PhotoQualityIssue(
        code: 'dark',
        message: 'Too dark',
      ));
    } else if (brightness > _tooBright) {
      issues.add(const PhotoQualityIssue(
        code: 'bright',
        message: 'Too bright',
      ));
    }

    if (sharpness < _minSharpness) {
      issues.add(const PhotoQualityIssue(
        code: 'blurry',
        message: 'May be blurry',
      ));
    }

    if (_hasFramingIssue(bounds, sample.width, sample.height, contentCoverage)) {
      issues.add(const PhotoQualityIssue(
        code: 'framing',
        message: 'Document may be too small or cut off',
      ));
    }

    return PhotoQualityResult(
      brightness: brightness,
      sharpness: sharpness,
      contentCoverage: contentCoverage,
      issues: issues,
    );
  }

  static img.Image _resizeForAnalysis(img.Image image) {
    const maxSide = 420;
    final longest = math.max(image.width, image.height);
    if (longest <= maxSide) return image;
    if (image.width >= image.height) {
      return img.copyResize(image, width: maxSide);
    }
    return img.copyResize(image, height: maxSide);
  }

  static List<double> _grayscale(img.Image image) {
    final values = List<double>.filled(image.width * image.height, 0);
    var index = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        values[index++] = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      }
    }
    return values;
  }

  static double _average(List<double> values) {
    if (values.isEmpty) return 0;
    var sum = 0.0;
    for (final value in values) {
      sum += value;
    }
    return sum / values.length;
  }

  static double _laplacianVariance(List<double> gray, int width, int height) {
    if (width < 3 || height < 3) return 0;
    final samples = <double>[];
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final i = y * width + x;
        final response = (4 * gray[i]) -
            gray[i - 1] -
            gray[i + 1] -
            gray[i - width] -
            gray[i + width];
        samples.add(response.abs());
      }
    }
    if (samples.isEmpty) return 0;
    final mean = _average(samples);
    var sum = 0.0;
    for (final sample in samples) {
      final delta = sample - mean;
      sum += delta * delta;
    }
    return sum / samples.length;
  }

  static _Bounds? _edgeBounds(List<double> gray, int width, int height) {
    if (width < 3 || height < 3) return null;
    const threshold = 32.0;
    var left = width;
    var right = -1;
    var top = height;
    var bottom = -1;

    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final i = y * width + x;
        final gx = (gray[i + 1] - gray[i - 1]).abs();
        final gy = (gray[i + width] - gray[i - width]).abs();
        if (gx + gy < threshold) continue;
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
      }
    }

    if (right < left || bottom < top) return null;
    return _Bounds(left: left, top: top, right: right, bottom: bottom);
  }

  static bool _hasFramingIssue(
    _Bounds? bounds,
    int width,
    int height,
    double coverage,
  ) {
    if (bounds == null) return true;
    final contentWidthRatio = bounds.width / width;
    final contentHeightRatio = bounds.height / height;
    if (coverage < _minContentCoverage ||
        contentWidthRatio < _minContentWidthRatio ||
        contentHeightRatio < _minContentHeightRatio) {
      return true;
    }

    final marginX = width * _edgeTouchMarginRatio;
    final marginY = height * _edgeTouchMarginRatio;
    var touchedSides = 0;
    if (bounds.left <= marginX) touchedSides++;
    if (bounds.top <= marginY) touchedSides++;
    if (bounds.right >= width - marginX) touchedSides++;
    if (bounds.bottom >= height - marginY) touchedSides++;
    return touchedSides >= 2;
  }
}

class _Bounds {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const _Bounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  int get width => right - left + 1;
  int get height => bottom - top + 1;
}
