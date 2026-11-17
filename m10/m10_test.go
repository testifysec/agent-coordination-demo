package m10

import "testing"

func TestID(t *testing.T) {
	if ID() != 10 {
		t.Fatal("wrong id")
	}
}
