package m28

import "testing"

func TestID(t *testing.T) {
	if ID() != 28 {
		t.Fatal("wrong id")
	}
}
