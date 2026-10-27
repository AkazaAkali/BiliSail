import '../models.dart';

enum ApiAppFeedbackKind { dislike, feedback }

final class ApiAppFeedbackReason {
  const ApiAppFeedbackReason({
    required this.id,
    required this.name,
    required this.kind,
  });
  final String id, name;
  final ApiAppFeedbackKind kind;
}

final class ApiAppRecommendation {
  const ApiAppRecommendation({
    required this.video,
    required this.aid,
    required this.reasons,
  });
  final ApiVideoSummary video;
  final String aid;
  final List<ApiAppFeedbackReason> reasons;
}

final class ApiAppQrCode {
  const ApiAppQrCode({required this.url, required this.authCode});
  final Uri url;
  final String authCode;
}

final class ApiAppCredentials {
  const ApiAppCredentials({
    required this.mid,
    required this.accessToken,
    required this.expiresAt,
  });
  final String mid, accessToken;
  final DateTime expiresAt;
}

final class ApiAppQrPoll {
  const ApiAppQrPoll(this.status, {this.credentials});
  final ApiQrStatus status;
  final ApiAppCredentials? credentials;
}
