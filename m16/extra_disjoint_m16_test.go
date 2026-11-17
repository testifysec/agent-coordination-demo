package m16

import "testing"

func TestF_disjoint_m16(t *testing.T) {
	if F_disjoint_m16() != 1 {
		t.Fatal("bad")
	}
}
