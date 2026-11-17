package m20

import "testing"

func TestF_burst_m20(t *testing.T) {
	if F_burst_m20() != 1 {
		t.Fatal("bad")
	}
}
