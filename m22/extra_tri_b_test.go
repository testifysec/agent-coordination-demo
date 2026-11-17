package m22

import "testing"

func TestF_tri_b(t *testing.T) {
	if F_tri_b() != 1 {
		t.Fatal("bad")
	}
}
