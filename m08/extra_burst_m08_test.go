package m08

import "testing"

func TestF_burst_m08(t *testing.T) {
	if F_burst_m08() != 1 {
		t.Fatal("bad")
	}
}
