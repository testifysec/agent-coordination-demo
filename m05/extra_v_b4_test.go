package m05

import "testing"

func TestF_v_b4(t *testing.T) {
	if F_v_b4() != 1 {
		t.Fatal("bad")
	}
}
