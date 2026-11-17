package m03

import "testing"

func TestF_v_b2(t *testing.T) {
	if F_v_b2() != 1 {
		t.Fatal("bad")
	}
}
