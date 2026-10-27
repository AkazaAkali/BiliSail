import '../../../domain/request_cancellation.dart';

final class AppRecommendationIdentity {
  const AppRecommendationIdentity({
    this.buvid = '',
    this.authorizedMid,
    this.expiresAt,
    this.expired = false,
    this.canAuthorize = false,
  });
  final String buvid;
  final String? authorizedMid;
  final DateTime? expiresAt;
  final bool expired;
  final bool canAuthorize;
  static bool validBuvid(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value);
}

final class AppRecommendationAuthorization {
  AppRecommendationAuthorization({required this.url, required this.expiresAt});
  final Uri url;
  final DateTime expiresAt;
}

enum AppRecommendationAuthorizationStatus {
  waitingScan,
  waitingConfirm,
  expired,
  confirmed,
}

abstract interface class AppRecommendationIdentityRepository {
  int get revision;
  Stream<int> get changes;
  Future<AppRecommendationIdentity> load();
  Future<void> setBuvid(String value);
  Future<void> randomizeBuvid();
  Future<void> clearAuthorization();
  Future<AppRecommendationAuthorization> beginAuthorization({
    required RequestCancellation cancellation,
  });
  Future<AppRecommendationAuthorizationStatus> pollAuthorization(
    AppRecommendationAuthorization attempt, {
    required RequestCancellation cancellation,
  });
}
