package m21

import "testing"

func TestID(t *testing.T) {
	if ID() != 21 {
		t.Fatal("wrong id")
	}
}
