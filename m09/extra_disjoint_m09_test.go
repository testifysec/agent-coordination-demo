package m09

import "testing"

func TestF_disjoint_m09(t *testing.T) {
	if F_disjoint_m09() != 1 {
		t.Fatal("bad")
	}
}
