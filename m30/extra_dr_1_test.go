package m30

import "testing"

func TestF_dr_1(t *testing.T) {
	if F_dr_1() != 1 {
		t.Fatal("bad")
	}
}
