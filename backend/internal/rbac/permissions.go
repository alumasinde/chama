// Package rbac maps group roles to capabilities; roles always come from the database.
package rbac

const (
	PermGroupRead            = "group.read"
	PermGroupUpdate          = "group.update"
	PermMemberRead           = "member.read"
	PermMemberManage         = "member.manage"
	PermInviteRotate         = "invite.rotate"
	PermPaymentSettingsRead  = "payment_settings.read"
	PermPaymentSettingsWrite = "payment_settings.write"
	PermPaymentRecord        = "payment.record"
	PermLoanSettingsWrite    = "loan_settings.write"
	PermLoanApply            = "loan.apply"
	PermLoanManage           = "loan.manage"
	PermLoanDisburse         = "loan.disburse"
	PermLoanRepay            = "loan.repay"
	PermFineRulesWrite       = "fine_rules.write"
	PermFineManage           = "fine.manage"
	PermFinePay              = "fine.pay"
	PermFineWaive            = "fine.waive"
	PermFineEvaluate         = "fine.evaluate"
	PermWelfareManage        = "welfare.manage"
	PermWelfareContribute    = "welfare.contribute"
	PermRotationManage       = "rotation.manage"
	PermRotationVote         = "rotation.vote"
	PermReportRead           = "report.read"
	PermReportExport         = "report.export"
	PermAuditRead            = "audit.read"
)

var roleCapabilities = map[string]map[string]bool{
	"admin": {
		PermGroupRead: true, PermGroupUpdate: true, PermMemberRead: true,
		PermMemberManage: true, PermInviteRotate: true,
		PermPaymentSettingsRead: true, PermPaymentSettingsWrite: true,
		PermPaymentRecord:     true,
		PermLoanSettingsWrite: true, PermLoanApply: true, PermLoanManage: true,
		PermLoanDisburse: true, PermLoanRepay: true,
		PermFineRulesWrite: true, PermFineManage: true, PermFinePay: true,
		PermFineWaive: true, PermFineEvaluate: true,
		PermWelfareManage: true, PermWelfareContribute: true,
		PermRotationManage: true, PermRotationVote: true,
		PermReportRead: true, PermReportExport: true, PermAuditRead: true,
	},
	"treasurer": {
		PermGroupRead: true, PermMemberRead: true,
		PermPaymentSettingsRead: true, PermPaymentSettingsWrite: true,
		PermPaymentRecord:     true,
		PermLoanSettingsWrite: true, PermLoanApply: true, PermLoanManage: true,
		PermLoanDisburse: true, PermLoanRepay: true,
		PermFineRulesWrite: true, PermFineManage: true, PermFinePay: true,
		PermFineWaive: true, PermFineEvaluate: true,
		PermWelfareManage: true, PermWelfareContribute: true,
		PermRotationManage: true, PermRotationVote: true,
		PermReportRead: true, PermReportExport: true,
	},
	"secretary": {
		PermGroupRead: true, PermMemberRead: true,
		PermLoanApply: true, PermFineEvaluate: true, PermRotationVote: true,
		PermReportRead: true, PermReportExport: true,
	},
	"member": {
		PermGroupRead: true, PermMemberRead: true, PermLoanApply: true, PermRotationVote: true,
	},
}

// Allows is the single source of truth for role capabilities.
func Allows(role, permission string) bool {
	caps, ok := roleCapabilities[role]
	if !ok {
		return false
	}
	return caps[permission]
}

// Rank orders roles so a member can never change someone of higher rank.
func Rank(role string) int {
	switch role {
	case "admin":
		return 3
	case "treasurer":
		return 2
	case "secretary":
		return 1
	case "member":
		return 0
	default:
		return -1
	}
}

func ValidRole(role string) bool { return roleCapabilities[role] != nil }

func ValidStatus(status string) bool {
	switch status {
	case "pending", "active", "suspended", "exited":
		return true
	default:
		return false
	}
}
