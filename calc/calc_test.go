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
