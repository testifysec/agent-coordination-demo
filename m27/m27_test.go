package m27

import "testing"

func TestID(t *testing.T) {
	if ID() != 27 {
		t.Fatal("wrong id")
	}
}
