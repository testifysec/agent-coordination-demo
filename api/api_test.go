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
