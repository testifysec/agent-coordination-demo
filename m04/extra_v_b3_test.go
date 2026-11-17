package m04

import "testing"

func TestF_v_b3(t *testing.T) {
	if F_v_b3() != 1 {
		t.Fatal("bad")
	}
}
