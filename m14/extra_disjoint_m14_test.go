package m14

import "testing"

func TestF_disjoint_m14(t *testing.T) {
	if F_disjoint_m14() != 1 {
		t.Fatal("bad")
	}
}
