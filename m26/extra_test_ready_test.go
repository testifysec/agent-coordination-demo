package m26

import "testing"

func TestF_test_ready(t *testing.T) {
	if F_test_ready() != 1 {
		t.Fatal("bad")
	}
}
