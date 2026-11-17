package m10

import "testing"

func TestF_burst2_m10(t *testing.T) {
	if F_burst2_m10() != 1 {
		t.Fatal("bad")
	}
}
