package m03

import "testing"

func TestF_burst_m03(t *testing.T) {
	if F_burst_m03() != 1 {
		t.Fatal("bad")
	}
}
