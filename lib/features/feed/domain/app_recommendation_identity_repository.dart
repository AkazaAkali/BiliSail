final class AppRecommendationIdentity {
  const AppRecommendationIdentity({
    this.buvid = '',
    this.authorizedMid,
    this.expiresAt,
    this.expired = false,
  });
  final String buvid;
  final String? authorizedMid;
  final DateTime? expiresAt;
  final bool expired;
  static bool validBuvid(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value);
}

abstract interface class AppRecommendationIdentityRepository {
  int get revision;
  Stream<int> get changes;
  Future<AppRecommendationIdentity> load();
  Future<void> setBuvid(String value);
  Future<void> randomizeBuvid();
}
