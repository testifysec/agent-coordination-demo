package m19

import "testing"

func TestF_burst_m19(t *testing.T) {
	if F_burst_m19() != 1 {
		t.Fatal("bad")
	}
}
