package m20

import "testing"

func TestID(t *testing.T) {
	if ID() != 20 {
		t.Fatal("wrong id")
	}
}
