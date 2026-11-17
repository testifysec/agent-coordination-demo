package m05

import "testing"

func TestID(t *testing.T) {
	if ID() != 5 {
		t.Fatal("wrong id")
	}
}
