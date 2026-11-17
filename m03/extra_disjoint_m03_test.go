package m03

import "testing"

func TestF_disjoint_m03(t *testing.T) {
	if F_disjoint_m03() != 1 {
		t.Fatal("bad")
	}
}
