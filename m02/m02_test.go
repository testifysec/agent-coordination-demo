package m02

import "testing"

func TestID(t *testing.T) {
	if ID() != 2 {
		t.Fatal("wrong id")
	}
}
