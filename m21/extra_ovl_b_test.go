package m21

import "testing"

func TestF_ovl_b(t *testing.T) {
	if F_ovl_b() != 1 {
		t.Fatal("bad")
	}
}
