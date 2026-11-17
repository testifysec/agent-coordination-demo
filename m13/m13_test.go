package m13

import "testing"

func TestID(t *testing.T) {
	if ID() != 13 {
		t.Fatal("wrong id")
	}
}
