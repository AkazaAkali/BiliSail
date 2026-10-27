import '../api_client.dart';
import '../models.dart';
import '../models/app_recommendation_models.dart';

final class AppPassportClient {
  AppPassportClient(this.api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final BiliApiClient api;
  final DateTime Function() _clock;

  Future<ApiAppQrCode> generate({
    required String buvid,
    ApiRequestContext? context,
  }) async {
    final data = await api.requestAppJson(
      '/x/passport-tv-login/qrcode/auth_code',
      {'local_id': '0', 'platform': 'android', 'mobi_app': 'android_hd'},
      endpoint: 'app_qr_generate',
      buvid: buvid,
      context: context,
    );
    final code = data['auth_code'], rawUrl = data['url'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (code is! String ||
        code.isEmpty ||
        code.length > 1024 ||
        url == null ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.port != 443 ||
        !(url.host == 'bilibili.com' || url.host.endsWith('.bilibili.com'))) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'app_qr_generate');
    }
    return ApiAppQrCode(url: url, authCode: code);
  }

  Future<ApiAppQrPoll> poll({
    required String buvid,
    required String authCode,
    ApiRequestContext? context,
  }) async {
    final data = await api.requestAppJson(
      '/x/passport-tv-login/qrcode/poll',
      {'auth_code': authCode, 'local_id': '0'},
      endpoint: 'app_qr_poll',
      buvid: buvid,
      context: context,
    );
    final status = data['status_code'];
    if (status != null) {
      return ApiAppQrPoll(switch (status) {
        86038 => ApiQrStatus.expired,
        86090 => ApiQrStatus.waitingConfirm,
        _ => ApiQrStatus.waitingScan,
      });
    }
    final token = data['token_info'];
    if (token is! Map<String, Object?>) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'app_qr_poll');
    }
    final mid = '${token['mid'] ?? ''}',
        access = token['access_token'],
        seconds = token['expires_in'];
    if (!RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(mid) ||
        access is! String ||
        access.isEmpty ||
        access.length > 4096 ||
        seconds is! int ||
        seconds <= 0 ||
        seconds > 366 * 86400) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'app_qr_poll');
    }
    return ApiAppQrPoll(
      ApiQrStatus.confirmed,
      credentials: ApiAppCredentials(
        mid: mid,
        accessToken: access,
        expiresAt: _clock().add(Duration(seconds: seconds)),
      ),
    );
  }
}
