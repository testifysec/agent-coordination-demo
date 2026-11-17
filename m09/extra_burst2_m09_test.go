package m09

import "testing"

func TestF_burst2_m09(t *testing.T) {
	if F_burst2_m09() != 1 {
		t.Fatal("bad")
	}
}
