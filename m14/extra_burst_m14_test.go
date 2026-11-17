package m14

import "testing"

func TestF_burst_m14(t *testing.T) {
	if F_burst_m14() != 1 {
		t.Fatal("bad")
	}
}
