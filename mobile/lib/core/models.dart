String _string(Map<String, dynamic> json, String key, [String fallback = '']) {
  final value = json[key];
  return value == null ? fallback : '$value';
}

int _integer(Map<String, dynamic> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value is int) return value;
  return int.tryParse('$value') ?? fallback;
}

List<dynamic> _list(dynamic value) => value is List ? value : const [];

class AppUser {
  const AppUser({
    required this.id,
    required this.phoneNumber,
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.pinSet,
    required this.hasPassword,
    this.email,
    this.createdAt,
  });

  final String id;
  final String phoneNumber;
  final String firstName;
  final String lastName;
  final String displayName;
  final bool pinSet;
  final bool hasPassword;
  final String? email;
  final String? createdAt;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: _string(json, 'id'),
    phoneNumber: _string(json, 'phone_number'),
    firstName: _string(json, 'first_name'),
    lastName: _string(json, 'last_name'),
    displayName: _string(json, 'display_name'),
    pinSet: json['pin_set'] == true,
    hasPassword: json['has_password'] == true,
    email: json['email']?.toString(),
    createdAt: json['created_at']?.toString(),
  );
}

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AppUser user;

  factory Session.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    return Session(
      accessToken: _string(json, 'access_token'),
      refreshToken: _string(json, 'refresh_token'),
      user: AppUser.fromJson(
        userJson is Map<String, dynamic> ? userJson : const {},
      ),
    );
  }
}

class OtpRequest {
  const OtpRequest({required this.devCode, required this.resendAfter});

  final String? devCode;
  final int resendAfter;

  factory OtpRequest.fromJson(Map<String, dynamic> json) => OtpRequest(
    devCode: json['dev_code']?.toString(),
    resendAfter: _integer(json, 'resend_after', 60),
  );
}

class OtpVerify {
  const OtpVerify({
    required this.newUser,
    required this.session,
    required this.registrationToken,
  });

  final bool newUser;
  final Session? session;
  final String? registrationToken;

  factory OtpVerify.fromJson(Map<String, dynamic> json) {
    final rawSession = json['session'];
    return OtpVerify(
      newUser: json['new_user'] == true,
      session: rawSession is Map<String, dynamic>
          ? Session.fromJson(rawSession)
          : null,
      registrationToken: json['registration_token']?.toString(),
    );
  }
}

class Chama {
  const Chama({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.currency,
    required this.contributionAmount,
    required this.contributionFrequency,
    required this.contributionDay,
    required this.role,
    required this.status,
    required this.activeMembers,
    this.description,
  });

  final String id;
  final String name;
  final String inviteCode;
  final String currency;
  final String contributionAmount;
  final String contributionFrequency;
  final int contributionDay;
  final String role;
  final String status;
  final int activeMembers;
  final String? description;

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get canManage => role == 'admin' || role == 'treasurer';

  factory Chama.fromJson(Map<String, dynamic> json) => Chama(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    inviteCode: _string(json, 'invite_code'),
    currency: _string(json, 'currency', 'KES'),
    contributionAmount: _string(json, 'contribution_amount', '0.00'),
    contributionFrequency: _string(json, 'contribution_frequency', 'monthly'),
    contributionDay: _integer(json, 'contribution_day', 1),
    role: _string(json, 'role', 'member'),
    status: _string(json, 'status', 'active'),
    activeMembers: _integer(json, 'active_members'),
    description: json['description']?.toString(),
  );
}

class GroupKpis {
  const GroupKpis({
    required this.collected,
    required this.outstandingLoans,
    required this.unpaidFines,
    required this.savings,
    required this.welfareBalance,
    required this.activeMembers,
    required this.pendingLoans,
  });

  final String collected;
  final String outstandingLoans;
  final String unpaidFines;
  final String savings;
  final String welfareBalance;
  final int activeMembers;
  final int pendingLoans;

  factory GroupKpis.fromJson(Map<String, dynamic> json) => GroupKpis(
    collected: _string(json, 'collected', '0.00'),
    outstandingLoans: _string(json, 'outstanding_loans', '0.00'),
    unpaidFines: _string(json, 'unpaid_fines', '0.00'),
    savings: _string(json, 'savings', '0.00'),
    welfareBalance: _string(json, 'welfare_balance', '0.00'),
    activeMembers: _integer(json, 'active_members'),
    pendingLoans: _integer(json, 'pending_loans'),
  );
}

class GroupDashboard {
  const GroupDashboard({
    required this.kpis,
    required this.periodLabel,
    required this.periodStart,
    required this.periodEnd,
    required this.contributionAmount,
    required this.contributionFrequency,
  });

  final GroupKpis kpis;
  final String periodLabel;
  final String periodStart;
  final String periodEnd;
  final String contributionAmount;
  final String contributionFrequency;

  factory GroupDashboard.fromJson(Map<String, dynamic> json) {
    final group = json['group'];
    final period = json['period'];
    final kpis = json['kpis'];
    final groupMap = group is Map<String, dynamic>
        ? group
        : <String, dynamic>{};
    final periodMap = period is Map<String, dynamic>
        ? period
        : <String, dynamic>{};
    return GroupDashboard(
      kpis: GroupKpis.fromJson(
        kpis is Map<String, dynamic> ? kpis : <String, dynamic>{},
      ),
      periodLabel: _string(periodMap, 'label'),
      periodStart: _string(periodMap, 'start'),
      periodEnd: _string(periodMap, 'end'),
      contributionAmount: _string(groupMap, 'contribution_amount', '0.00'),
      contributionFrequency: _string(
        groupMap,
        'contribution_frequency',
        'monthly',
      ),
    );
  }
}

class Member {
  const Member({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.role,
    required this.status,
    this.joinedAt,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String displayName;
  final String role;
  final String status;
  final String? joinedAt;

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: _string(json, 'user_id'),
    firstName: _string(json, 'first_name'),
    lastName: _string(json, 'last_name'),
    displayName: _string(json, 'display_name'),
    role: _string(json, 'role', 'member'),
    status: _string(json, 'status', 'active'),
    joinedAt: json['joined_at']?.toString(),
  );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.member,
    required this.type,
    required this.status,
    required this.amount,
    required this.narration,
    required this.createdAt,
    this.channel,
    this.referenceCode,
    this.periodLabel,
  });

  final String id;
  final String member;
  final String type;
  final String status;
  final String amount;
  final String narration;
  final String createdAt;
  final String? channel;
  final String? referenceCode;
  final String? periodLabel;

  bool get completed => status == 'completed';

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: _string(json, 'id'),
    member: _string(json, 'member'),
    type: _string(json, 'type', 'contribution'),
    status: _string(json, 'status', 'pending'),
    amount: _string(json, 'amount', '0.00'),
    narration: _string(json, 'narration'),
    createdAt: _string(json, 'created_at'),
    channel: json['channel']?.toString(),
    referenceCode: json['reference_code']?.toString(),
    periodLabel: json['period_label']?.toString(),
  );
}

class Loan {
  const Loan({
    required this.id,
    required this.borrower,
    required this.principal,
    required this.totalPayable,
    required this.paidToDate,
    required this.outstanding,
    required this.status,
    required this.termMonths,
    required this.purpose,
    required this.requestedAt,
    this.interestRate = '0.00',
    this.interestMethod = '',
    this.totalInterest = '0.00',
    this.approvedAt,
    this.disbursedAt,
    this.guarantors = const [],
    this.approvals = const [],
  });

  final String id;
  final String borrower;
  final String principal;
  final String totalPayable;
  final String paidToDate;
  final String outstanding;
  final String status;
  final int termMonths;
  final String purpose;
  final String requestedAt;
  final String interestRate;
  final String interestMethod;
  final String totalInterest;
  final String? approvedAt;
  final String? disbursedAt;
  final List<Guarantor> guarantors;
  final List<Approval> approvals;

  double get progress {
    final total = double.tryParse(totalPayable) ?? 0;
    final paid = double.tryParse(paidToDate) ?? 0;
    if (total <= 0) return 0;
    return (paid / total).clamp(0, 1).toDouble();
  }

  factory Loan.fromJson(Map<String, dynamic> json) => Loan(
    id: _string(json, 'id'),
    borrower: _string(json, 'borrower'),
    principal: _string(json, 'principal', '0.00'),
    totalPayable: _string(json, 'total_payable', '0.00'),
    paidToDate: _string(json, 'paid_to_date', '0.00'),
    outstanding: _string(json, 'outstanding', '0.00'),
    status: _string(json, 'status', 'pending_approval'),
    termMonths: _integer(json, 'term_months'),
    purpose: _string(json, 'purpose'),
    requestedAt: _string(json, 'requested_at'),
    interestRate: _string(json, 'interest_rate', '0.00'),
    interestMethod: _string(json, 'interest_method'),
    totalInterest: _string(json, 'total_interest', '0.00'),
    approvedAt: json['approved_at']?.toString(),
    disbursedAt: json['disbursed_at']?.toString(),
    guarantors: _list(json['guarantors'])
        .whereType<Map<String, dynamic>>()
        .map(Guarantor.fromJson)
        .toList(),
    approvals: _list(json['approvals'])
        .whereType<Map<String, dynamic>>()
        .map(Approval.fromJson)
        .toList(),
  );
}

class WelfareFund {
  const WelfareFund({
    required this.configured,
    required this.name,
    required this.monthlyAmount,
    required this.balance,
    required this.contributed,
    required this.paidOut,
    required this.isActive,
  });

  final bool configured;
  final String name;
  final String monthlyAmount;
  final String balance;
  final String contributed;
  final String paidOut;
  final bool isActive;

  factory WelfareFund.fromJson(Map<String, dynamic> json) => WelfareFund(
    configured: json['configured'] == true,
    name: _string(json, 'name', 'Welfare'),
    monthlyAmount: _string(json, 'monthly_amount', '0.00'),
    balance: _string(json, 'balance', '0.00'),
    contributed: _string(json, 'contributed_total', '0.00'),
    paidOut: _string(json, 'paid_out_total', '0.00'),
    isActive: json['is_active'] == true,
  );
}

class WelfareClaim {
  const WelfareClaim({
    required this.id,
    required this.member,
    required this.amount,
    required this.reason,
    required this.status,
    required this.requestedAt,
    this.decidedAt,
    this.comment,
    this.payoutTransactionId,
  });

  final String id;
  final String member;
  final String amount;
  final String reason;
  final String status;
  final String requestedAt;
  final String? decidedAt;
  final String? comment;
  final String? payoutTransactionId;

  factory WelfareClaim.fromJson(Map<String, dynamic> json) => WelfareClaim(
    id: _string(json, 'id'),
    member: _string(json, 'member'),
    amount: _string(json, 'amount', '0.00'),
    reason: _string(json, 'reason'),
    status: _string(json, 'status', 'pending'),
    requestedAt: _string(json, 'requested_at'),
    decidedAt: json['decided_at']?.toString(),
    comment: json['comment']?.toString(),
    payoutTransactionId: json['payout_transaction_id']?.toString(),
  );
}

class Fine {
  const Fine({
    required this.id,
    required this.userId,
    required this.member,
    required this.fineType,
    required this.amount,
    required this.reason,
    required this.status,
    required this.assessedOn,
    required this.paid,
    this.periodLabel,
    this.waiveReason,
  });

  final String id;
  final String userId;
  final String member;
  final String fineType;
  final String amount;
  final String reason;
  final String status;
  final String assessedOn;
  final bool paid;
  final String? periodLabel;
  final String? waiveReason;

  bool get isUnpaid => status == 'unpaid' && !paid;

  factory Fine.fromJson(Map<String, dynamic> json) => Fine(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    member: _string(json, 'member'),
    fineType: _string(json, 'fine_type', 'custom'),
    amount: _string(json, 'amount', '0.00'),
    reason: _string(json, 'reason'),
    status: _string(json, 'status', 'unpaid'),
    assessedOn: _string(json, 'assessed_on'),
    paid: json['paid'] == true,
    periodLabel: json['period_label']?.toString(),
    waiveReason: json['waive_reason']?.toString(),
  );
}

class LoanSettings {
  const LoanSettings({
    required this.allowLoans,
    required this.interestRate,
    required this.interestMethod,
    required this.maxMultiple,
    required this.maxTermMonths,
    required this.guarantorsRequired,
  });

  final bool allowLoans;
  final String interestRate;
  final String interestMethod;
  final String maxMultiple;
  final int maxTermMonths;
  final int guarantorsRequired;

  factory LoanSettings.fromJson(Map<String, dynamic> json) => LoanSettings(
    allowLoans: json['allow_loans'] == true,
    interestRate: _string(json, 'interest_rate', '0.00'),
    interestMethod: _string(json, 'interest_method', 'flat'),
    maxMultiple: _string(json, 'max_multiple_of_savings', '0.00'),
    maxTermMonths: _integer(json, 'max_term_months', 1),
    guarantorsRequired: _integer(json, 'guarantors_required'),
  );
}

class Guarantor {
  const Guarantor({
    required this.userId,
    required this.displayName,
    required this.amount,
    required this.status,
    this.respondedAt,
  });

  final String userId;
  final String displayName;
  final String amount;
  final String status;
  final String? respondedAt;

  factory Guarantor.fromJson(Map<String, dynamic> json) => Guarantor(
    userId: _string(json, 'user_id'),
    displayName: _string(json, 'display_name'),
    amount: _string(json, 'amount', '0.00'),
    status: _string(json, 'status', 'pending'),
    respondedAt: json['responded_at']?.toString(),
  );
}

class Approval {
  const Approval({
    required this.approverId,
    required this.displayName,
    required this.decision,
    this.comment,
    this.createdAt,
  });

  final String approverId;
  final String displayName;
  final String decision;
  final String? comment;
  final String? createdAt;

  factory Approval.fromJson(Map<String, dynamic> json) => Approval(
    approverId: _string(json, 'approver_id'),
    displayName: _string(json, 'display_name'),
    decision: _string(json, 'decision'),
    comment: json['comment']?.toString(),
    createdAt: json['created_at']?.toString(),
  );
}

class Installment {
  const Installment({
    required this.number,
    required this.dueDate,
    required this.principal,
    required this.interest,
    required this.paid,
    required this.total,
    this.paidAt,
  });

  final int number;
  final String dueDate;
  final String principal;
  final String interest;
  final String paid;
  final String total;
  final String? paidAt;

  bool get isPaid => paidAt != null;

  factory Installment.fromJson(Map<String, dynamic> json) => Installment(
    number: _integer(json, 'installment_no'),
    dueDate: _string(json, 'due_date'),
    principal: _string(json, 'principal_due', '0.00'),
    interest: _string(json, 'interest_due', '0.00'),
    paid: _string(json, 'paid_amount', '0.00'),
    total: _string(json, 'total_due', '0.00'),
    paidAt: json['paid_at']?.toString(),
  );
}

class RotationSlot {
  const RotationSlot({
    required this.id,
    required this.userId,
    required this.member,
    required this.position,
    required this.payoutDate,
    required this.paid,
  });

  final String id;
  final String userId;
  final String member;
  final int position;
  final String payoutDate;
  final bool paid;

  factory RotationSlot.fromJson(Map<String, dynamic> json) => RotationSlot(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    member: _string(json, 'member'),
    position: _integer(json, 'position'),
    payoutDate: _string(json, 'payout_date'),
    paid: json['paid'] == true,
  );
}

class RotationCycle {
  const RotationCycle({
    required this.id,
    required this.name,
    required this.status,
    required this.orderingMode,
    required this.contribution,
    required this.startsOn,
    required this.memberCount,
    required this.slotCount,
    required this.paidCount,
    required this.slots,
  });

  final String id;
  final String name;
  final String status;
  final String orderingMode;
  final String contribution;
  final String startsOn;
  final int memberCount;
  final int slotCount;
  final int paidCount;
  final List<RotationSlot> slots;

  double get progress => slotCount == 0 ? 0 : paidCount / slotCount;

  factory RotationCycle.fromJson(Map<String, dynamic> json) => RotationCycle(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    status: _string(json, 'status'),
    orderingMode: _string(json, 'ordering_mode'),
    contribution: _string(json, 'contribution_amount', '0.00'),
    startsOn: _string(json, 'starts_on'),
    memberCount: _integer(json, 'member_count'),
    slotCount: _integer(json, 'slot_count'),
    paidCount: _integer(json, 'paid_count'),
    slots: _list(json['slots'])
        .whereType<Map<String, dynamic>>()
        .map(RotationSlot.fromJson)
        .toList(),
  );
}

class RotationProposal {
  const RotationProposal({
    required this.id,
    required this.status,
    required this.forCount,
    required this.againstCount,
    required this.abstainCount,
    required this.total,
    required this.needed,
    required this.closesAt,
    this.myChoice,
  });

  final String id;
  final String status;
  final int forCount;
  final int againstCount;
  final int abstainCount;
  final int total;
  final int needed;
  final String closesAt;
  final String? myChoice;

  bool get isOpen => status == 'open';

  factory RotationProposal.fromJson(Map<String, dynamic> json) {
    final tally = json['tally'];
    final tallyMap = tally is Map<String, dynamic>
        ? tally
        : const <String, dynamic>{};
    final myVote = json['my_vote'];
    final voteMap = myVote is Map<String, dynamic>
        ? myVote
        : const <String, dynamic>{};
    return RotationProposal(
      id: _string(json, 'id'),
      status: _string(json, 'status'),
      forCount: _integer(tallyMap, 'for'),
      againstCount: _integer(tallyMap, 'against'),
      abstainCount: _integer(tallyMap, 'abstain'),
      total: _integer(tallyMap, 'total'),
      needed: _integer(tallyMap, 'needed'),
      closesAt: _string(json, 'closes_at'),
      myChoice: voteMap['choice']?.toString(),
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String createdAt;
  final bool read;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: _string(json, 'id'),
        type: _string(json, 'type', 'general'),
        title: _string(json, 'title'),
        body: _string(json, 'body'),
        createdAt: _string(json, 'created_at'),
        read: json['read_at'] != null,
      );
}

class NotificationFeed {
  const NotificationFeed({required this.items, required this.unread});

  final List<AppNotification> items;
  final int unread;
}

class JoinResult {
  const JoinResult({
    required this.groupId,
    required this.groupName,
    required this.status,
    required this.message,
  });

  final String groupId;
  final String groupName;
  final String status;
  final String message;

  factory JoinResult.fromJson(Map<String, dynamic> json) => JoinResult(
    groupId: _string(json, 'group_id'),
    groupName: _string(json, 'group_name'),
    status: _string(json, 'status', 'pending'),
    message: _string(json, 'message'),
  );
}

class StkResult {
  const StkResult({
    required this.paymentRequestId,
    required this.status,
    required this.amount,
    required this.purpose,
  });

  final String paymentRequestId;
  final String status;
  final String amount;
  final String purpose;

  factory StkResult.fromJson(Map<String, dynamic> json) => StkResult(
    paymentRequestId: _string(json, 'payment_request_id'),
    status: _string(json, 'status', 'pending'),
    amount: _string(json, 'amount', '0.00'),
    purpose: _string(json, 'purpose', 'contribution'),
  );
}

List<LedgerEntry> ledgerEntriesFromJson(Map<String, dynamic> json) =>
    _list(json['data'])
        .whereType<Map<String, dynamic>>()
        .map(LedgerEntry.fromJson)
        .toList();

List<Member> membersFromJson(Map<String, dynamic> json) =>
    _list(json['data'])
        .whereType<Map<String, dynamic>>()
        .map(Member.fromJson)
        .toList();

List<Loan> loansFromJson(Map<String, dynamic> json) =>
    _list(json['data'])
        .whereType<Map<String, dynamic>>()
        .map(Loan.fromJson)
        .toList();

List<WelfareClaim> claimsFromJson(Map<String, dynamic> json) =>
    _list(json['data'])
        .whereType<Map<String, dynamic>>()
        .map(WelfareClaim.fromJson)
        .toList();

List<Fine> finesFromJson(Map<String, dynamic> json) =>
    _list(json['data'])
        .whereType<Map<String, dynamic>>()
        .map(Fine.fromJson)
        .toList();

List<Installment> installmentsFromJson(Map<String, dynamic> json) =>
    _list(json['data'])
        .whereType<Map<String, dynamic>>()
        .map(Installment.fromJson)
        .toList();

List<RotationCycle> rotationCyclesFromJson(Map<String, dynamic> json) =>
    _list(json['data'])
        .whereType<Map<String, dynamic>>()
        .map(RotationCycle.fromJson)
        .toList();

List<RotationProposal> rotationProposalsFromJson(Map<String, dynamic> json) =>
    _list(json['data'])
        .whereType<Map<String, dynamic>>()
        .map(RotationProposal.fromJson)
        .toList();
