package m19

import "testing"

func TestID(t *testing.T) {
	if ID() != 19 {
		t.Fatal("wrong id")
	}
}
