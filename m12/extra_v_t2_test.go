package m12

import "testing"

func TestF_v_t2(t *testing.T) {
	if F_v_t2() != 1 {
		t.Fatal("bad")
	}
}
