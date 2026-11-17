package m11

import "testing"

func TestF_v_o2(t *testing.T) {
	if F_v_o2() != 1 {
		t.Fatal("bad")
	}
}
