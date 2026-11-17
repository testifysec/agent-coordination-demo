package m04

import "testing"

func TestF_burst_m04(t *testing.T) {
	if F_burst_m04() != 1 {
		t.Fatal("bad")
	}
}
