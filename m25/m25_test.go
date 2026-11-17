package m25

import "testing"

func TestID(t *testing.T) {
	if ID() != 25 {
		t.Fatal("wrong id")
	}
}
