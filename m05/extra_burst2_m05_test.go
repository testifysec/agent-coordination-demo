package m05

import "testing"

func TestF_burst2_m05(t *testing.T) {
	if F_burst2_m05() != 1 {
		t.Fatal("bad")
	}
}
