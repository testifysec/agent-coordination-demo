package m07

import "testing"

func TestF_burst_m07(t *testing.T) {
	if F_burst_m07() != 1 {
		t.Fatal("bad")
	}
}
