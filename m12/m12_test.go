package m12

import "testing"

func TestID(t *testing.T) {
	if ID() != 12 {
		t.Fatal("wrong id")
	}
}
