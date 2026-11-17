package m22

import "testing"

func TestID(t *testing.T) {
	if ID() != 22 {
		t.Fatal("wrong id")
	}
}
