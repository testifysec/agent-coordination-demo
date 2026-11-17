package m13

import "testing"

func TestF_burst2_m13(t *testing.T) {
	if F_burst2_m13() != 1 {
		t.Fatal("bad")
	}
}
