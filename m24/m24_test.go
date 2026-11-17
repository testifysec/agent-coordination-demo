package m24

import "testing"

func TestID(t *testing.T) {
	if ID() != 24 {
		t.Fatal("wrong id")
	}
}
