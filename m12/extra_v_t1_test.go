package m12

import "testing"

func TestF_v_t1(t *testing.T) {
	if F_v_t1() != 1 {
		t.Fatal("bad")
	}
}
