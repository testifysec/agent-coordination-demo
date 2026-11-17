package m20

import "testing"

func TestF_burst2_m20(t *testing.T) {
	if F_burst2_m20() != 1 {
		t.Fatal("bad")
	}
}
