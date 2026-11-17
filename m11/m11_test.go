package m11

import "testing"

func TestID(t *testing.T) {
	if ID() != 11 {
		t.Fatal("wrong id")
	}
}
