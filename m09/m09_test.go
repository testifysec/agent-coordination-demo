package m09

import "testing"

func TestID(t *testing.T) {
	if ID() != 9 {
		t.Fatal("wrong id")
	}
}
