package auth

import (
	"errors"
	"strings"
)

// weakPINs are the values attackers try first; four digits are never strong, so block the obvious.
var weakPINs = map[string]bool{
	"0000": true, "1111": true, "2222": true, "3333": true, "4444": true,
	"5555": true, "6666": true, "7777": true, "8888": true, "9999": true,
	"1234": true, "4321": true, "0123": true, "3210": true, "1122": true,
	"1212": true, "2121": true, "6969": true, "0852": true, "2580": true,
}

// ValidatePIN enforces exactly four digits and rejects predictable values.
func ValidatePIN(pin string) error {
	if len(pin) != 4 {
		return errors.New("PIN must be exactly 4 digits")
	}
	for _, r := range pin {
		if r < '0' || r > '9' {
			return errors.New("PIN must be exactly 4 digits")
		}
	}
	if weakPINs[pin] {
		return errors.New("choose a less predictable PIN")
	}
	ascending, descending := true, true
	for i := 1; i < len(pin); i++ {
		if pin[i] != pin[i-1]+1 {
			ascending = false
		}
		if pin[i]+1 != pin[i-1] {
			descending = false
		}
	}
	if ascending || descending {
		return errors.New("choose a less predictable PIN")
	}
	return nil
}

func ValidatePassword(password string) error {
	if len(password) < 8 {
		return errors.New("password must be at least 8 characters")
	}
	if len(password) > 128 {
		return errors.New("password must be at most 128 characters")
	}
	if strings.TrimSpace(password) != password {
		return errors.New("password must not start or end with a space")
	}
	return nil
}
