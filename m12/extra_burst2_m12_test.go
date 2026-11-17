package m12

import "testing"

func TestF_burst2_m12(t *testing.T) {
	if F_burst2_m12() != 1 {
		t.Fatal("bad")
	}
}
