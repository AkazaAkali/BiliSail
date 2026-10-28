import 'package:bili_player/bili_player.dart';
import 'package:bilisail/features/video/presentation/inline_video_height.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double height(
    VideoDimensions? dimensions, {
    bool phone = true,
    double available = 800,
  }) => inlineVideoHeight(
    width: 390,
    availableHeight: available,
    portraitPhone: phone,
    dimensions: dimensions,
  );

  test('portrait phone video grows with a bounded information area', () {
    expect(height(const VideoDimensions(1080, 1920)), 520);
    expect(height(const VideoDimensions(100, 101)), 393.9);
    expect(height(const VideoDimensions(100, 10000)), 520);
  });

  test('landscape, square, unknown and invalid sources retain 16:9', () {
    for (final dimensions in [
      null,
      const VideoDimensions(1920, 1080),
      const VideoDimensions(1080, 1080),
      const VideoDimensions(0, 1920),
      const VideoDimensions(-1, 1920),
    ]) {
      expect(height(dimensions), 390 * 9 / 16);
    }
  });

  test('desktop, tablet and landscape viewport keep the previous layout', () {
    expect(
      height(const VideoDimensions(1080, 1920), phone: false),
      390 * 9 / 16,
    );
  });

  test('unbounded or small viewport does not inflate or shrink fallback', () {
    expect(
      height(const VideoDimensions(1080, 1920), available: double.infinity),
      390 * 9 / 16,
    );
    expect(
      height(const VideoDimensions(1080, 1920), available: 200),
      390 * 9 / 16,
    );
  });
}
