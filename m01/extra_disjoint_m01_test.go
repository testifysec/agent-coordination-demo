package m01

import "testing"

func TestF_disjoint_m01(t *testing.T) {
	if F_disjoint_m01() != 1 {
		t.Fatal("bad")
	}
}
