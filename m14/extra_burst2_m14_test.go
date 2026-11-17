package m14

import "testing"

func TestF_burst2_m14(t *testing.T) {
	if F_burst2_m14() != 1 {
		t.Fatal("bad")
	}
}
