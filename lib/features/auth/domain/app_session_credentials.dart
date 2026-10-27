/// Internal data-port credentials; UI consumes AuthState summaries instead.
final class AppSessionCredentials {
  const AppSessionCredentials({
    required this.mid,
    required this.accessToken,
    required this.expiresAt,
    required this.buvid,
    this.refreshToken,
    this.invalid = false,
  });
  final String mid, accessToken, buvid;
  final String? refreshToken;
  final DateTime expiresAt;
  final bool invalid;
}

abstract interface class AppSessionCredentialsPort {
  AppSessionCredentials? get appCredentials;
  Future<void> invalidateAppCredentials(AppSessionCredentials expected);
}
