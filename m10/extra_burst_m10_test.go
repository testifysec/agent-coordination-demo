package m10

import "testing"

func TestF_burst_m10(t *testing.T) {
	if F_burst_m10() != 1 {
		t.Fatal("bad")
	}
}
