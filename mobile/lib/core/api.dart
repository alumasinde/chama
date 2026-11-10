import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.requestId,
    this.fields = const {},
  });

  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;
  final Map<String, String> fields;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class TokenStore {
  static const _accessKey = 'chama.access_token';
  static const _refreshKey = 'chama.refresh_token';

  Future<(String?, String?)> read() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_accessKey), prefs.getString(_refreshKey));
  }

  Future<void> write(String access, String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }
}

class ApiClient {
  ApiClient({http.Client? client, TokenStore? store})
    : _http = client ?? http.Client(),
      _store = store ?? TokenStore();

  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) return 'http://localhost:8081';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8081';
    }
    return 'http://localhost:8081';
  }

  final http.Client _http;
  final TokenStore _store;
  String? _access;
  String? _refresh;

  bool get hasSession => _access != null;

  Future<bool> restoreSession() async {
    final (access, refresh) = await _store.read();
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty) {
      return false;
    }
    _access = access;
    _refresh = refresh;
    return true;
  }

  Future<void> setSession(Session session) async {
    _access = session.accessToken;
    _refresh = session.refreshToken;
    await _store.write(session.accessToken, session.refreshToken);
  }

  Future<void> clearSession() async {
    _access = null;
    _refresh = null;
    await _store.clear();
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    String? bearer,
    bool authenticated = true,
    bool retryOnUnauthorized = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    request.headers['X-Client'] = 'mobile';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (headers != null) request.headers.addAll(headers);
    final token = bearer ?? _access;
    if (authenticated && token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    late http.Response response;
    try {
      final streamed = await _http
          .send(request)
          .timeout(const Duration(seconds: 25));
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException('The request took too long. Try again.');
    } on Exception {
      throw const ApiException(
        'We could not reach the server. Check your connection.',
      );
    }

    if (response.statusCode == 401 &&
        retryOnUnauthorized &&
        authenticated &&
        bearer == null &&
        await _refreshSession()) {
      return _send(
        method,
        path,
        body: body,
        headers: headers,
        bearer: bearer,
        authenticated: authenticated,
        retryOnUnauthorized: false,
      );
    }
    return response;
  }

  Future<bool> _refreshSession() async {
    final refresh = _refresh;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final response = await _http
          .post(
            Uri.parse('$baseUrl/api/v1/auth/token/refresh'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'X-Client': 'mobile',
            },
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final session = Session.fromJson(_decode(response));
      await setSession(session);
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return const {};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    String? bearer,
    bool authenticated = true,
  }) async {
    final response = await _send(
      method,
      path,
      body: body,
      headers: headers,
      bearer: bearer,
      authenticated: authenticated,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response);
    }

    Map<String, dynamic> envelope = const {};
    try {
      envelope = _decode(response);
    } catch (_) {
      // Leave the generic message below when the server returns a non-JSON body.
    }
    final error = envelope['error'];
    final errorMap = error is Map<String, dynamic> ? error : const {};
    final fields = <String, String>{};
    final rawFields = errorMap['fields'];
    if (rawFields is Map) {
      for (final entry in rawFields.entries) {
        fields['${entry.key}'] = '${entry.value}';
      }
    }
    throw ApiException(
      errorMap['message']?.toString() ?? 'Something went wrong. Try again.',
      statusCode: response.statusCode,
      code: errorMap['code']?.toString(),
      requestId: response.headers['x-request-id'],
      fields: fields,
    );
  }

  Future<OtpRequest> requestOtp(String phone) async {
    final json = await _json(
      'POST',
      '/api/v1/auth/otp/request',
      body: {'phone_number': phone, 'purpose': 'login'},
      authenticated: false,
    );
    return OtpRequest.fromJson(json);
  }

  Future<OtpVerify> verifyOtp(String phone, String code) async {
    final json = await _json(
      'POST',
      '/api/v1/auth/otp/verify',
      body: {'phone_number': phone, 'code': code, 'purpose': 'login'},
      authenticated: false,
    );
    return OtpVerify.fromJson(json);
  }

  Future<Session> register({
    required String registrationToken,
    required String firstName,
    required String lastName,
    required String pin,
  }) async {
    final json = await _json(
      'POST',
      '/api/v1/auth/register',
      bearer: registrationToken,
      body: {'first_name': firstName, 'last_name': lastName, 'pin': pin},
    );
    return Session.fromJson(json);
  }

  Future<AppUser> me() async {
    final json = await _json('GET', '/api/v1/me');
    final user = json['user'];
    return AppUser.fromJson(user is Map<String, dynamic> ? user : const {});
  }

  Future<AppUser> updateProfile({
    required String firstName,
    required String lastName,
    String? email,
  }) async {
    final json = await _json(
      'PATCH',
      '/api/v1/me',
      body: {
        'first_name': firstName,
        'last_name': lastName,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      },
    );
    final user = json['user'];
    return AppUser.fromJson(user is Map<String, dynamic> ? user : json);
  }

  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    await _json(
      'POST',
      '/api/v1/me/pin',
      body: {'current_pin': currentPin, 'new_pin': newPin},
    );
  }

  Future<List<Chama>> groups() async {
    final json = await _json('GET', '/api/v1/groups');
    return (json['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Chama.fromJson)
        .toList();
  }

  Future<Chama> group(String id) async {
    final json = await _json('GET', '/api/v1/groups/$id');
    return Chama.fromJson(json);
  }

  Future<GroupDashboard> dashboard(String groupId) async {
    final json = await _json(
      'GET',
      '/api/v1/groups/$groupId/reports/dashboard',
    );
    return GroupDashboard.fromJson(json);
  }

  Future<List<Member>> members(String groupId) async {
    final json = await _json('GET', '/api/v1/groups/$groupId/members');
    return membersFromJson(json);
  }

  Future<List<LedgerEntry>> transactions(String groupId) async {
    final json = await _json(
      'GET',
      '/api/v1/groups/$groupId/transactions?limit=50',
    );
    return ledgerEntriesFromJson(json);
  }

  Future<List<Loan>> loans(String groupId) async {
    final json = await _json('GET', '/api/v1/groups/$groupId/loans?limit=50');
    return loansFromJson(json);
  }

  Future<LoanSettings> loanSettings(String groupId) async {
    final json = await _json('GET', '/api/v1/groups/$groupId/loans/settings');
    return LoanSettings.fromJson(json);
  }

  Future<Loan> applyLoan({
    required String groupId,
    required String amount,
    required int termMonths,
    required String purpose,
    required List<({String userId, String amount})> guarantors,
    required String stepUpToken,
  }) async {
    final json = await _json(
      'POST',
      '/api/v1/groups/$groupId/loans',
      headers: {'X-Step-Up-Token': stepUpToken},
      body: {
        'amount': amount,
        'term_months': termMonths,
        'purpose': purpose,
        'guarantors': [
          for (final guarantor in guarantors)
            {'user_id': guarantor.userId, 'amount': guarantor.amount},
        ],
      },
    );
    return Loan.fromJson(json);
  }

  Future<Loan> loanDetail(String groupId, String loanId) async {
    final json = await _json('GET', '/api/v1/groups/$groupId/loans/$loanId');
    return Loan.fromJson(json);
  }

  Future<List<Installment>> loanSchedule(String groupId, String loanId) async {
    final json = await _json(
      'GET',
      '/api/v1/groups/$groupId/loans/$loanId/schedule',
    );
    return installmentsFromJson(json);
  }

  Future<Loan> respondToGuarantee({
    required String groupId,
    required String loanId,
    required String decision,
  }) async {
    final json = await _json(
      'POST',
      '/api/v1/groups/$groupId/loans/$loanId/guarantors/respond',
      body: {'decision': decision},
    );
    return Loan.fromJson(json);
  }

  Future<List<Fine>> fines(String groupId) async {
    final json = await _json('GET', '/api/v1/groups/$groupId/fines?limit=100');
    return finesFromJson(json);
  }

  Future<WelfareFund> welfare(String groupId) async {
    final json = await _json('GET', '/api/v1/groups/$groupId/welfare');
    return WelfareFund.fromJson(json);
  }

  Future<List<WelfareClaim>> welfareClaims(String groupId) async {
    final json = await _json(
      'GET',
      '/api/v1/groups/$groupId/welfare/claims?limit=50',
    );
    return claimsFromJson(json);
  }

  Future<WelfareClaim> requestWelfareClaim({
    required String groupId,
    required String amount,
    required String reason,
  }) async {
    final json = await _json(
      'POST',
      '/api/v1/groups/$groupId/welfare/claims',
      body: {'amount': amount, 'reason': reason},
    );
    final claim = json['claim'] ?? json['data'];
    return WelfareClaim.fromJson(claim is Map<String, dynamic> ? claim : json);
  }

  Future<List<RotationCycle>> rotationCycles(String groupId) async {
    final json = await _json(
      'GET',
      '/api/v1/groups/$groupId/rotation/cycles?limit=20',
    );
    return rotationCyclesFromJson(json);
  }

  Future<NotificationFeed> notifications() async {
    final json = await _json('GET', '/api/v1/notifications?limit=50');
    final items = (json['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList();
    return NotificationFeed(
      items: items,
      unread: int.tryParse('${json['unread_count']}') ?? 0,
    );
  }

  Future<void> markAllNotificationsRead() async {
    await _json(
      'POST',
      '/api/v1/notifications/read',
      body: const {'all': true},
    );
  }

  Future<JoinResult> joinChama(String inviteCode) async {
    final json = await _json(
      'POST',
      '/api/v1/groups/join',
      body: {'invite_code': inviteCode},
    );
    return JoinResult.fromJson(json);
  }

  Future<Chama> createChama({
    required String name,
    required String contributionAmount,
    required String frequency,
    required int contributionDay,
  }) async {
    final json = await _json(
      'POST',
      '/api/v1/groups',
      body: {
        'name': name,
        'contribution_amount': contributionAmount,
        'contribution_frequency': frequency,
        'contribution_day': contributionDay,
      },
    );
    return Chama.fromJson(json);
  }

  Future<String> verifyPin(String pin) async {
    final json = await _json(
      'POST',
      '/api/v1/auth/pin/verify',
      body: {'pin': pin},
    );
    return json['step_up_token']?.toString() ?? '';
  }

  Future<StkResult> requestStk({
    required String groupId,
    required String amount,
    required String purpose,
    required String stepUpToken,
    required String idempotencyKey,
  }) async {
    final json = await _json(
      'POST',
      '/api/v1/groups/$groupId/payments/stk',
      headers: {
        'X-Step-Up-Token': stepUpToken,
        'Idempotency-Key': idempotencyKey,
      },
      body: {'amount': amount, 'purpose': purpose},
    );
    return StkResult.fromJson(json);
  }

  Future<void> logout() async {
    if (!hasSession) return;
    try {
      await _json('POST', '/api/v1/auth/logout');
    } catch (_) {
      // The local session is cleared even if the server is unreachable.
    } finally {
      await clearSession();
    }
  }
}
