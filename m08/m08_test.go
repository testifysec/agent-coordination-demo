package m08

import "testing"

func TestID(t *testing.T) {
	if ID() != 8 {
		t.Fatal("wrong id")
	}
}
