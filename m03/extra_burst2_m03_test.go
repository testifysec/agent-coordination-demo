package m03

import "testing"

func TestF_burst2_m03(t *testing.T) {
	if F_burst2_m03() != 1 {
		t.Fatal("bad")
	}
}
