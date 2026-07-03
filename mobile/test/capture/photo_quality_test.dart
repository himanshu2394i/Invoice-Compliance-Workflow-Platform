import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:invoice_capture/features/capture/photo_quality.dart';

img.Image _documentImage({
  int width = 640,
  int height = 900,
  int docLeft = 80,
  int docTop = 80,
  int docRight = 560,
  int docBottom = 820,
  int background = 180,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(background, background, background));
  img.fillRect(
    image,
    x1: docLeft,
    y1: docTop,
    x2: docRight,
    y2: docBottom,
    color: img.ColorRgb8(248, 248, 248),
  );
  img.drawRect(
    image,
    x1: docLeft,
    y1: docTop,
    x2: docRight,
    y2: docBottom,
    color: img.ColorRgb8(20, 20, 20),
    thickness: 4,
  );
  for (var y = docTop + 60; y < docBottom - 40; y += 42) {
    img.drawLine(
      image,
      x1: docLeft + 45,
      y1: y,
      x2: docRight - 45,
      y2: y,
      color: img.ColorRgb8(40, 40, 40),
      thickness: 3,
    );
  }
  return image;
}

bool _hasIssue(PhotoQualityResult result, String code) =>
    result.issues.any((issue) => issue.code == code);

void main() {
  test('well-lit sharp centered document does not warn', () {
    final result = PhotoQualityService.analyzeImage(_documentImage());

    expect(result.shouldWarn, false);
    expect(result.issues, isEmpty);
  });

  test('dark image warns for lighting', () {
    final image = _documentImage(background: 20);
    img.fillRect(
      image,
      x1: 80,
      y1: 80,
      x2: 560,
      y2: 820,
      color: img.ColorRgb8(35, 35, 35),
    );

    final result = PhotoQualityService.analyzeImage(image);

    expect(result.shouldWarn, true);
    expect(_hasIssue(result, 'dark'), true);
  });

  test('blurred image warns for sharpness', () {
    final blurred = img.gaussianBlur(_documentImage(), radius: 12);

    final result = PhotoQualityService.analyzeImage(blurred);

    expect(result.shouldWarn, true);
    expect(_hasIssue(result, 'blurry'), true);
  });

  test('tiny or cut-off document warns for framing', () {
    final tiny = _documentImage(
      docLeft: 250,
      docTop: 330,
      docRight: 390,
      docBottom: 570,
    );
    final cropped = _documentImage(
      docLeft: -30,
      docTop: 20,
      docRight: 640,
      docBottom: 880,
    );

    final tinyResult = PhotoQualityService.analyzeImage(tiny);
    final croppedResult = PhotoQualityService.analyzeImage(cropped);

    expect(_hasIssue(tinyResult, 'framing'), true);
    expect(_hasIssue(croppedResult, 'framing'), true);
  });
}
