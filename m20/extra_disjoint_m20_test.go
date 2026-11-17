package m20

import "testing"

func TestF_disjoint_m20(t *testing.T) {
	if F_disjoint_m20() != 1 {
		t.Fatal("bad")
	}
}
