import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'player_contract.dart';

/// Prefer Android's MediaCodec path, with mpv's safe decoder fallback. A usable
/// Surface must be attached in on_load before the decoder is created.
/// The actual decoder still depends on the device and source codec.
mkv.VideoControllerConfiguration videoDecoderConfiguration({
  required bool isAndroid,
  required VideoDecodingMode decoding,
}) => mkv.VideoControllerConfiguration(
  // Software decoding still uses the GPU video output. Desktop defaults remain
  // owned by the SDK; Android follows PiliPlus's MediaCodec preference order.
  hwdec: decoding == VideoDecodingMode.software
      ? 'no'
      : isAndroid
      ? 'mediacodec,auto-safe'
      : null,
  androidAttachSurfaceAfterVideoParameters:
      isAndroid && decoding == VideoDecodingMode.automatic ? false : null,
);
