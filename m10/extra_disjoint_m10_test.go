package m10

import "testing"

func TestF_disjoint_m10(t *testing.T) {
	if F_disjoint_m10() != 1 {
		t.Fatal("bad")
	}
}
