package m04

import "testing"

func TestF_disjoint_m04(t *testing.T) {
	if F_disjoint_m04() != 1 {
		t.Fatal("bad")
	}
}
