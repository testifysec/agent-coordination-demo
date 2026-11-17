package m01

import "testing"

func TestF_burst_m01(t *testing.T) {
	if F_burst_m01() != 1 {
		t.Fatal("bad")
	}
}
