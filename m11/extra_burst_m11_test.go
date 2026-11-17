package m11

import "testing"

func TestF_burst_m11(t *testing.T) {
	if F_burst_m11() != 1 {
		t.Fatal("bad")
	}
}
