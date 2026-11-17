package m18

import "testing"

func TestID(t *testing.T) {
	if ID() != 18 {
		t.Fatal("wrong id")
	}
}
