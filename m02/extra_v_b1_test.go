package m02

import "testing"

func TestF_v_b1(t *testing.T) {
	if F_v_b1() != 1 {
		t.Fatal("bad")
	}
}
