package m22

import "testing"

func TestF_tri_c(t *testing.T) {
	if F_tri_c() != 1 {
		t.Fatal("bad")
	}
}
