import 'package:chama_mobile/core/app_state.dart';
import 'package:chama_mobile/core/format.dart';
import 'package:chama_mobile/core/models.dart';
import 'package:chama_mobile/core/theme.dart';
import 'package:chama_mobile/screens/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money and phone formatting stay readable', () {
    expect(money('34500'), 'KES 34,500.00');
    expect(money('1500.50'), 'KES 1,500.50');
    expect(normalizedPhone('712 345 678'), '0712345678');
    expect(normalizedPhone('+254 712 345 678'), '0712345678');
    expect(maskPhone('0712345678'), '0712 ••• 678');
  });

  test('dashboard JSON maps the API money strings', () {
    final dashboard = GroupDashboard.fromJson({
      'group': {
        'contribution_amount': '1000.00',
        'contribution_frequency': 'monthly',
      },
      'period': {
        'label': 'Nov 2026',
        'start': '2026-11-01',
        'end': '2026-12-01',
      },
      'kpis': {
        'collected': '12000.00',
        'outstanding_loans': '3000.00',
        'unpaid_fines': '200.00',
        'savings': '85000.00',
        'welfare_balance': '2500.00',
        'active_members': 24,
        'pending_loans': 2,
      },
    });

    expect(dashboard.kpis.savings, '85000.00');
    expect(dashboard.kpis.activeMembers, 24);
    expect(dashboard.periodLabel, 'Nov 2026');
    expect(dashboard.contributionAmount, '1000.00');
  });

  test('fine, loan and rotation JSON map to member screens', () {
    final fine = Fine.fromJson({
      'id': 'fine-1',
      'user_id': 'user-1',
      'member': 'Amina Wanjiku',
      'fine_type': 'late_contribution',
      'amount': '250.00',
      'reason': 'Late November contribution',
      'status': 'unpaid',
      'assessed_on': '2026-11-08',
      'paid': false,
    });
    expect(fine.isUnpaid, isTrue);
    expect(fine.fineType, 'late_contribution');

    final loan = Loan.fromJson({
      'id': 'loan-1',
      'borrower': 'Amina Wanjiku',
      'principal': '3000.00',
      'total_payable': '3150.00',
      'paid_to_date': '0.00',
      'outstanding': '3150.00',
      'status': 'pending_guarantors',
      'term_months': 3,
      'purpose': 'Stock',
      'requested_at': '2026-11-01T09:00:00Z',
      'interest_rate': '5.00',
      'interest_method': 'flat',
      'guarantors': [
        {
          'user_id': 'user-2',
          'display_name': 'Peter Mwangi',
          'amount': '1500.00',
          'status': 'pending',
        },
      ],
    });
    expect(loan.guarantors.single.displayName, 'Peter Mwangi');
    expect(loan.interestRate, '5.00');

    final cycle = RotationCycle.fromJson({
      'id': 'cycle-1',
      'name': 'Cycle 1',
      'status': 'active',
      'ordering_mode': 'vote',
      'contribution_amount': '1000.00',
      'starts_on': '2026-11-01',
      'member_count': 2,
      'slot_count': 2,
      'paid_count': 1,
      'slots': [
        {
          'id': 'slot-1',
          'user_id': 'user-1',
          'member': 'Amina Wanjiku',
          'position': 1,
          'payout_date': '2026-11-15',
          'paid': false,
        },
      ],
    });
    expect(cycle.slots.single.position, 1);
    expect(cycle.progress, 0.5);
  });

  test('loan settings keep the chama policy values', () {
    final settings = LoanSettings.fromJson({
      'allow_loans': true,
      'interest_rate': '5.00',
      'interest_method': 'flat',
      'max_multiple_of_savings': '3.00',
      'max_term_months': 6,
      'guarantors_required': 2,
    });
    expect(settings.allowLoans, isTrue);
    expect(settings.maxTermMonths, 6);
    expect(settings.guarantorsRequired, 2);
  });

  testWidgets('sign-in screen starts with the phone form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildChamaTheme(),
        home: AuthScreen(controller: AppController()),
      ),
    );

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
