package lib

import "testing"

func TestModeSet(t *testing.T) {
	if Mode == "" {
		t.Fatal("Mode is empty")
	}
}
