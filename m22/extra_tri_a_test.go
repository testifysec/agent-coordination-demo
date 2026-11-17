package m22

import "testing"

func TestF_tri_a(t *testing.T) {
	if F_tri_a() != 1 {
		t.Fatal("bad")
	}
}
