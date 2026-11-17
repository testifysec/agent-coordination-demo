package m26

import "testing"

func TestID(t *testing.T) {
	if ID() != 26 {
		t.Fatal("wrong id")
	}
}
