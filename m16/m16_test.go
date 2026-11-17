package m16

import "testing"

func TestID(t *testing.T) {
	if ID() != 16 {
		t.Fatal("wrong id")
	}
}
