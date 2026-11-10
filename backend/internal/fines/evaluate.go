package fines

import (
	"fmt"
	"time"
)

// PreviousPeriod returns the last completed contribution period for a cadence.
// Weekly periods start on Monday; monthly and quarterly on the first day.
func PreviousPeriod(now time.Time, frequency string) Period {
	now = now.UTC()
	switch frequency {
	case "weekly", "biweekly":
		step := 7
		if frequency == "biweekly" {
			step = 14
		}
		end := startOfISOWeek(now)
		start := end.AddDate(0, 0, -step)
		return Period{Start: start, End: end, Label: "week-" + start.Format("2006-01-02")}
	case "quarterly":
		quarterMonth := time.Month(((int(now.Month())-1)/3)*3 + 1)
		end := time.Date(now.Year(), quarterMonth, 1, 0, 0, 0, 0, time.UTC)
		start := end.AddDate(0, -3, 0)
		return Period{Start: start, End: end,
			Label: fmt.Sprintf("%d-Q%d", start.Year(), (int(start.Month())-1)/3+1)}
	default:
		end := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
		start := end.AddDate(0, -1, 0)
		return Period{Start: start, End: end, Label: start.Format("2006-01")}
	}
}

func startOfISOWeek(t time.Time) time.Time {
	day := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
	offset := (int(day.Weekday()) + 6) % 7
	return day.AddDate(0, 0, -offset)
}
