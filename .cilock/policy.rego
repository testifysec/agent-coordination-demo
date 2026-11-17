package coordkit.tests_ran_and_passed

# RegoV0 syntax: cilock's evaluator parses `deny[msg] { ... }`.
# Input is the command-run/v0.2 predicate of the step named "test".
# Edit `expected_cmd` and the output checks to match your test command.

expected_cmd := ["go", "test", "./..."]

readable_exit { is_number(input.exitcode) }

deny[msg] {
	not readable_exit
	msg := "unreadable evidence: command-run has no numeric exitcode"
}

deny[msg] {
	readable_exit
	input.exitcode != 0
	msg := sprintf("tests exited %v, not 0", [input.exitcode])
}

# The run must be the real test command, not `true` or `go test -run NoSuch`.
deny[msg] {
	not input.cmd == expected_cmd
	msg := sprintf("step ran %v, expected %v", [input.cmd, expected_cmd])
}

# "ok  <pkg>" means a package's tests ran. "no tests to run" means they did not.
deny[msg] {
	not contains(object.get(input, "stdout", ""), "ok  \t")
	msg := "go test output has no passing package line"
}

deny[msg] {
	contains(object.get(input, "stdout", ""), "no tests to run")
	msg := "go test reported no tests to run"
}
