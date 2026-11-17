package m12

import "testing"

func TestF_disjoint_m12(t *testing.T) {
	if F_disjoint_m12() != 1 {
		t.Fatal("bad")
	}
}
