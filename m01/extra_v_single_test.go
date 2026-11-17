package m01

import "testing"

func TestF_v_single(t *testing.T) {
	if F_v_single() != 1 {
		t.Fatal("bad")
	}
}
