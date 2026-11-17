package m07

import "testing"

func TestID(t *testing.T) {
	if ID() != 7 {
		t.Fatal("wrong id")
	}
}
