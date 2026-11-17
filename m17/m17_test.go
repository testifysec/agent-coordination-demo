package m17

import "testing"

func TestID(t *testing.T) {
	if ID() != 17 {
		t.Fatal("wrong id")
	}
}
