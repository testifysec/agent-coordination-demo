package api

import (
	"strings"
	"testing"
)

func TestDescribePrefix(t *testing.T) {
	if !strings.HasPrefix(Describe(), "api:") {
		t.Fatal("bad prefix")
	}
}

func TestDescribeIsStrict(t *testing.T) {
	if Describe() != "api:strict" {
		t.Fatalf("Describe()=%q, want api:strict", Describe())
	}
}
