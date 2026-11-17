package m03

import "testing"

func TestID(t *testing.T) {
	if ID() != 3 {
		t.Fatal("wrong id")
	}
}
