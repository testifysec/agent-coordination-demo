package m13

import "testing"

func TestF_disjoint_m13(t *testing.T) {
	if F_disjoint_m13() != 1 {
		t.Fatal("bad")
	}
}
