package m01

import "testing"

func TestID(t *testing.T) {
	if ID() != 1 {
		t.Fatal("wrong id")
	}
}
