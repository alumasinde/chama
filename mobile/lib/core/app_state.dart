import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

class GroupBundle {
  const GroupBundle({
    required this.dashboard,
    required this.members,
    required this.transactions,
    required this.loans,
    required this.welfare,
    required this.claims,
  });

  final GroupDashboard dashboard;
  final List<Member> members;
  final List<LedgerEntry> transactions;
  final List<Loan> loans;
  final WelfareFund? welfare;
  final List<WelfareClaim> claims;
}

class AppController extends ChangeNotifier {
  AppController({ApiClient? api}) : api = api ?? ApiClient();

  final ApiClient api;
  final Random _random = Random.secure();

  AppUser? user;
  List<Chama> groups = [];
  Chama? active;
  GroupDashboard? dashboard;
  List<LedgerEntry> recent = [];
  List<AppNotification> notifications = [];
  int unread = 0;
  bool booting = true;
  bool homeLoading = false;
  bool paymentBusy = false;
  String? homeError;
  String? workspaceError;

  Future<void> boot() async {
    booting = true;
    notifyListeners();
    try {
      final restored = await api.restoreSession();
      if (restored) {
        await _loadWorkspace();
      }
    } catch (_) {
      await api.clearSession();
      user = null;
      groups = [];
      active = null;
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> _loadWorkspace() async {
    user = await api.me();
    groups = await api.groups();
    _sortGroups();
    _pickActive();
    await Future.wait([refreshHome(), loadNotifications()]);
    notifyListeners();
  }

  void _pickActive() {
    if (groups.isEmpty) {
      active = null;
      return;
    }
    final currentId = active?.id;
    final current = currentId == null
        ? null
        : groups.where((group) => group.id == currentId).firstOrNull;
    final activeGroups = groups.where((group) => group.isActive).toList()
      ..sort((a, b) {
        final byMembers = b.activeMembers.compareTo(a.activeMembers);
        return byMembers != 0 ? byMembers : a.name.compareTo(b.name);
      });
    active =
        current ??
        (activeGroups.isNotEmpty ? activeGroups.first : groups.first);
  }

  Future<void> refreshGroups() async {
    groups = await api.groups();
    _sortGroups();
    _pickActive();
    notifyListeners();
  }

  void _sortGroups() {
    groups.sort((a, b) {
      final byMembers = b.activeMembers.compareTo(a.activeMembers);
      return byMembers != 0 ? byMembers : a.name.compareTo(b.name);
    });
  }

  Future<void> selectGroup(Chama group) async {
    active = group;
    dashboard = null;
    recent = [];
    homeError = null;
    notifyListeners();
    await refreshHome();
  }

  Future<void> refreshHome() async {
    final group = active;
    if (group == null || !group.isActive) {
      dashboard = null;
      recent = [];
      homeError = null;
      notifyListeners();
      return;
    }
    homeLoading = true;
    homeError = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([
        api.dashboard(group.id),
        api.transactions(group.id),
      ]);
      dashboard = results[0] as GroupDashboard;
      recent = results[1] as List<LedgerEntry>;
    } catch (error) {
      homeError = _message(error);
    } finally {
      homeLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadNotifications() async {
    try {
      final feed = await api.notifications();
      notifications = feed.items;
      unread = feed.unread;
      notifyListeners();
    } catch (_) {
      // Notifications are secondary; the rest of the app remains usable.
    }
  }

  Future<void> markAllRead() async {
    try {
      await api.markAllNotificationsRead();
      notifications = notifications
          .map(
            (item) => AppNotification(
              id: item.id,
              type: item.type,
              title: item.title,
              body: item.body,
              createdAt: item.createdAt,
              read: true,
            ),
          )
          .toList();
      unread = 0;
      notifyListeners();
    } catch (_) {
      rethrow;
    }
  }

  Future<GroupBundle> loadGroupBundle(String groupId) async {
    final dashboard = await api.dashboard(groupId);
    final results = await Future.wait<Object?>([
      api.members(groupId),
      api.transactions(groupId),
      _safeLoans(groupId),
      _safeWelfare(groupId),
      _safeClaims(groupId),
    ]);
    return GroupBundle(
      dashboard: dashboard,
      members: results[0] as List<Member>,
      transactions: results[1] as List<LedgerEntry>,
      loans: results[2] as List<Loan>,
      welfare: results[3] as WelfareFund?,
      claims: results[4] as List<WelfareClaim>,
    );
  }

  Future<List<Loan>> _safeLoans(String groupId) async {
    try {
      return await api.loans(groupId);
    } catch (_) {
      return [];
    }
  }

  Future<WelfareFund?> _safeWelfare(String groupId) async {
    try {
      return await api.welfare(groupId);
    } catch (_) {
      return null;
    }
  }

  Future<List<WelfareClaim>> _safeClaims(String groupId) async {
    try {
      return await api.welfareClaims(groupId);
    } catch (_) {
      return [];
    }
  }

  Future<OtpRequest> sendOtp(String phone) => api.requestOtp(phone);

  Future<OtpVerify> verifyOtp(String phone, String code) =>
      api.verifyOtp(phone, code);

  Future<void> finishSignIn(Session session) async {
    await api.setSession(session);
    user = session.user;
    notifyListeners();
    await _loadWorkspace();
  }

  Future<void> finishRegistration({
    required String registrationToken,
    required String firstName,
    required String lastName,
    required String pin,
  }) async {
    final session = await api.register(
      registrationToken: registrationToken,
      firstName: firstName,
      lastName: lastName,
      pin: pin,
    );
    await finishSignIn(session);
  }

  Future<JoinResult> joinChama(String code) async {
    final result = await api.joinChama(code.trim().toUpperCase());
    await refreshGroups();
    return result;
  }

  Future<Chama> createChama({
    required String name,
    required String amount,
    required String frequency,
    required int contributionDay,
  }) async {
    final created = await api.createChama(
      name: name.trim(),
      contributionAmount: amount.trim(),
      frequency: frequency,
      contributionDay: contributionDay,
    );
    await refreshGroups();
    active =
        groups.where((group) => group.id == created.id).firstOrNull ?? active;
    notifyListeners();
    await refreshHome();
    return created;
  }

  Future<StkResult> pay({
    required Chama group,
    required String pin,
    required String amount,
    required String purpose,
  }) async {
    paymentBusy = true;
    notifyListeners();
    try {
      final stepUp = await api.verifyPin(pin);
      if (stepUp.isEmpty) {
        throw const ApiException('Your PIN could not be verified.');
      }
      final key =
          '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
      final result = await api.requestStk(
        groupId: group.id,
        amount: amount,
        purpose: purpose,
        stepUpToken: stepUp,
        idempotencyKey: key,
      );
      if (active?.id == group.id) {
        await refreshHome();
      }
      return result;
    } finally {
      paymentBusy = false;
      notifyListeners();
    }
  }

  Future<Loan> applyLoan({
    required Chama group,
    required String pin,
    required String amount,
    required int termMonths,
    required String purpose,
    required List<({String userId, String amount})> guarantors,
  }) async {
    paymentBusy = true;
    notifyListeners();
    try {
      final stepUp = await api.verifyPin(pin);
      if (stepUp.isEmpty) {
        throw const ApiException('Your PIN could not be verified.');
      }
      final loan = await api.applyLoan(
        groupId: group.id,
        amount: amount,
        termMonths: termMonths,
        purpose: purpose,
        guarantors: guarantors,
        stepUpToken: stepUp,
      );
      if (active?.id == group.id) {
        await refreshHome();
      }
      return loan;
    } finally {
      paymentBusy = false;
      notifyListeners();
    }
  }

  Future<Loan> respondToGuarantee({
    required Chama group,
    required String loanId,
    required String decision,
  }) {
    return api.respondToGuarantee(
      groupId: group.id,
      loanId: loanId,
      decision: decision,
    );
  }

  Future<WelfareClaim> requestWelfareClaim({
    required Chama group,
    required String amount,
    required String reason,
  }) {
    return api.requestWelfareClaim(
      groupId: group.id,
      amount: amount,
      reason: reason,
    );
  }

  Future<AppUser> updateProfile({
    required String firstName,
    required String lastName,
    String? email,
  }) async {
    final updated = await api.updateProfile(
      firstName: firstName,
      lastName: lastName,
      email: email,
    );
    user = updated;
    notifyListeners();
    return updated;
  }

  Future<void> changePin({required String currentPin, required String newPin}) {
    return api.changePin(currentPin: currentPin, newPin: newPin);
  }

  Future<void> logout() async {
    await api.logout();
    user = null;
    groups = [];
    active = null;
    dashboard = null;
    recent = [];
    notifications = [];
    unread = 0;
    homeError = null;
    workspaceError = null;
    notifyListeners();
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    return 'Something went wrong. Try again.';
  }

  String get displayName => user?.displayName ?? '';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
