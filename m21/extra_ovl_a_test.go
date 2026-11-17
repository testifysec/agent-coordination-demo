package m21

import "testing"

func TestF_ovl_a(t *testing.T) {
	if F_ovl_a() != 1 {
		t.Fatal("bad")
	}
}
