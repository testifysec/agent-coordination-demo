package m18

import "testing"

func TestF_burst_m18(t *testing.T) {
	if F_burst_m18() != 1 {
		t.Fatal("bad")
	}
}
