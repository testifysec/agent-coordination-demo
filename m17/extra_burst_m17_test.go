package m17

import "testing"

func TestF_burst_m17(t *testing.T) {
	if F_burst_m17() != 1 {
		t.Fatal("bad")
	}
}
