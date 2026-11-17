package coordkit.sleep_ran

# The experiment's "test" is a constant sleep. The policy pins the exact command and a clean exit.
expected_cmd := ["sleep", "120"]

readable_exit { is_number(input.exitcode) }

deny[msg] {
	not readable_exit
	msg := "unreadable evidence: command-run has no numeric exitcode"
}

deny[msg] {
	readable_exit
	input.exitcode != 0
	msg := sprintf("test exited %v, not 0", [input.exitcode])
}

deny[msg] {
	not input.cmd == expected_cmd
	msg := sprintf("step ran %v, expected %v", [input.cmd, expected_cmd])
}
