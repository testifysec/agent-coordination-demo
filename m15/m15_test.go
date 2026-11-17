package m15

import "testing"

func TestID(t *testing.T) {
	if ID() != 15 {
		t.Fatal("wrong id")
	}
}
