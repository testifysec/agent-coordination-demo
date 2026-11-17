package m30

import "testing"

func TestID(t *testing.T) {
	if ID() != 30 {
		t.Fatal("wrong id")
	}
}
