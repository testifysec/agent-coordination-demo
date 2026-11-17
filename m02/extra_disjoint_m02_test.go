package m02

import "testing"

func TestF_disjoint_m02(t *testing.T) {
	if F_disjoint_m02() != 1 {
		t.Fatal("bad")
	}
}
