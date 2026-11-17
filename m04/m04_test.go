package m04

import "testing"

func TestID(t *testing.T) {
	if ID() != 4 {
		t.Fatal("wrong id")
	}
}
