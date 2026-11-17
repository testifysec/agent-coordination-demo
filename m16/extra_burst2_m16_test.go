package m16

import "testing"

func TestF_burst2_m16(t *testing.T) {
	if F_burst2_m16() != 1 {
		t.Fatal("bad")
	}
}
