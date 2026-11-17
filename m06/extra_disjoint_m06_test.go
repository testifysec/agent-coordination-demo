package m06

import "testing"

func TestF_disjoint_m06(t *testing.T) {
	if F_disjoint_m06() != 1 {
		t.Fatal("bad")
	}
}
