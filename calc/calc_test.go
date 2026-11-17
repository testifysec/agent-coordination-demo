package calc

import "testing"

func TestAdd(t *testing.T) {
	cases := []struct{ a, b, want int }{{2, 3, 5}, {-1, 1, 0}, {0, 0, 0}}
	for _, c := range cases {
		if got := Add(c.a, c.b); got != c.want {
			t.Fatalf("Add(%d,%d)=%d, want %d", c.a, c.b, got, c.want)
		}
	}
}

func TestSub(t *testing.T) {
	if got := Sub(5, 3); got != 2 {
		t.Fatalf("Sub(5,3)=%d, want 2", got)
	}
}

func TestMul(t *testing.T) {
	if got := Mul(4, 3); got != 12 {
		t.Fatalf("Mul(4,3)=%d, want 12", got)
	}
}
