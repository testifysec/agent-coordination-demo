package m11

import "testing"

func TestF_v_o1(t *testing.T) {
	if F_v_o1() != 1 {
		t.Fatal("bad")
	}
}
