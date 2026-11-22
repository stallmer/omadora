#!/usr/bin/env bats
# The drop-in that keeps systemd-remount-fs from failing on a composefs root.
#
# Run with: bats tests/template/remount-fs-dropin_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
DROPIN="${SCRIPT_DIR}/../../custom/files/usr/lib/systemd/system/systemd-remount-fs.service.d/10-omadora-composefs-skip.conf"

@test "remount-fs drop-in: it skips the unit when / is not writable" {
	[ -f "${DROPIN}" ]
	grep -qx '\[Unit\]' "${DROPIN}"
	grep -qx 'ConditionPathIsReadWrite=/' "${DROPIN}"
}

@test "remount-fs drop-in: it is a drop-in, not a mask or an override of the unit" {
	run grep -c -E '^(ExecStart|Exec|\[Service\]|Mask|Wants)' "${DROPIN}"
	[ "$output" = "0" ]
	# A masked unit would be a symlink to /dev/null; this must be a regular file.
	[ ! -L "${DROPIN}" ]
}
