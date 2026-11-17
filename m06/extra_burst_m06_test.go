package m06

import "testing"

func TestF_burst_m06(t *testing.T) {
	if F_burst_m06() != 1 {
		t.Fatal("bad")
	}
}
