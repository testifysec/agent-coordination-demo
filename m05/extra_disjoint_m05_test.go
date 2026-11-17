package m05

import "testing"

func TestF_disjoint_m05(t *testing.T) {
	if F_disjoint_m05() != 1 {
		t.Fatal("bad")
	}
}
