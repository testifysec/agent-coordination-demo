package m06

import "testing"

func TestID(t *testing.T) {
	if ID() != 6 {
		t.Fatal("wrong id")
	}
}
