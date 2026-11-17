package m29

import "testing"

func TestID(t *testing.T) {
	if ID() != 29 {
		t.Fatal("wrong id")
	}
}
