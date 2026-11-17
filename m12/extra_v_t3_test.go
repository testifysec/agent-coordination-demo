package m12

import "testing"

func TestF_v_t3(t *testing.T) {
	if F_v_t3() != 1 {
		t.Fatal("bad")
	}
}
