package m23

import "testing"

func TestID(t *testing.T) {
	if ID() != 23 {
		t.Fatal("wrong id")
	}
}
