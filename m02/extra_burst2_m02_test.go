package m02

import "testing"

func TestF_burst2_m02(t *testing.T) {
	if F_burst2_m02() != 1 {
		t.Fatal("bad")
	}
}
