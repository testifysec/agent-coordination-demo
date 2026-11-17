package m15

import "testing"

func TestF_burst_m15(t *testing.T) {
	if F_burst_m15() != 1 {
		t.Fatal("bad")
	}
}
