// Package api describes the current mode.
package api

import "github.com/testifysec/agent-coordination-demo/lib"

// Describe returns a label for the current mode.
func Describe() string { return "api:" + lib.Mode }
