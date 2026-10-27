abstract final class VideoIdentifiers {
  static const _alphabet =
      'FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf';
  static const _limit = 1 << 51;
  static const _xor = 23442827791579;

  static String? bvidFromAid(String aid) {
    if (!RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(aid)) return null;
    final number = int.tryParse(aid);
    if (number == null || number >= _limit) return null;
    var encoded = (number | _limit) ^ _xor;
    final digits = List<String>.filled(9, _alphabet[0]);
    for (var index = digits.length - 1; index >= 0; index--) {
      digits[index] = _alphabet[encoded % 58];
      encoded ~/= 58;
    }
    final ordered = List.of(digits);
    ordered[0] = digits[6];
    ordered[6] = digits[0];
    ordered[1] = digits[4];
    ordered[4] = digits[1];
    return 'BV1${ordered.join()}';
  }
}
