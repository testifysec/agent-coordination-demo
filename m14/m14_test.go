package m14

import "testing"

func TestID(t *testing.T) {
	if ID() != 14 {
		t.Fatal("wrong id")
	}
}
