package m16

import "testing"

func TestF_burst_m16(t *testing.T) {
	if F_burst_m16() != 1 {
		t.Fatal("bad")
	}
}
