package m02

import "testing"

func TestF_burst_m02(t *testing.T) {
	if F_burst_m02() != 1 {
		t.Fatal("bad")
	}
}
