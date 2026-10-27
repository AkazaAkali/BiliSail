import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Public client profile, separate from a user's App access token.
abstract final class AppProfile {
  static const appKey = 'dfca71928277209b';
  static const _signingSalt = 'b5475a8825547a4fc26c7d518eaaa02e';
  static const userAgent =
      'BiliSail BiliDroid/2.0.1 mobi_app/android_hd build/2001100';

  static Map<String, String> sign(
    Map<String, String> parameters,
    DateTime now,
  ) {
    final values = {...parameters}..remove('sign');
    values['appkey'] = appKey;
    values['ts'] = '${now.millisecondsSinceEpoch ~/ 1000}';
    final keys = values.keys.toList()..sort();
    final query = keys
        .map(
          (key) => values[key]!.isEmpty
              ? Uri.encodeComponent(key)
              : '${Uri.encodeComponent(key)}=${Uri.encodeComponent(values[key]!)}',
        )
        .join('&');
    return {
      ...values,
      'sign': md5.convert(utf8.encode('$query$_signingSalt')).toString(),
    };
  }
}
