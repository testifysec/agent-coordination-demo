package m17

import "testing"

func TestF_burst2_m17(t *testing.T) {
	if F_burst2_m17() != 1 {
		t.Fatal("bad")
	}
}
