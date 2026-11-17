package m18

import "testing"

func TestF_disjoint_m18(t *testing.T) {
	if F_disjoint_m18() != 1 {
		t.Fatal("bad")
	}
}
