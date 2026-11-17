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

func TestDescribeMatchesMode(t *testing.T) {
	if Describe() != "api:lenient" {
		t.Fatalf("Describe()=%q", Describe())
	}
}
