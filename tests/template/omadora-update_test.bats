#!/usr/bin/env bats
# Unit tests for custom/files/usr/bin/omadora-update.
#
# sudo, systemctl, bootc, jq and omadora-setup are stubbed on PATH. Each stub
# appends its arguments to one shared log, so the tests can check order.
# STAGED=1 makes the jq stub report a staged system image. UUPD_FAILS=n makes the
# first n `systemctl start uupd.service` calls fail (a large n fails them all).
# BOOTC_FAIL=1 makes `bootc status` fail; JQ_FAIL=1 makes jq exit with an error.
#
# Run with: bats tests/template/omadora-update_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
UPDATE_SRC="${SCRIPT_DIR}/../../custom/files/usr/bin/omadora-update"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/omadora-update.${BATS_TEST_NUMBER:-0}.$$"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	CALL_LOG="${TEST_ROOT}/calls.log"
	mkdir -p "${STUB_BIN}"

	# sudo runs its arguments, so the stubbed systemctl and bootc log themselves.
	cat >"${STUB_BIN}/sudo" <<'STUB'
#!/usr/bin/bash
exec "$@"
STUB
	cat >"${STUB_BIN}/systemctl" <<'STUB'
#!/usr/bin/bash
printf 'systemctl %s\n' "$*" >> "${CALL_LOG}"
if [ "$1 $2" = "start uupd.service" ] && [ -n "${UUPD_FAILS:-}" ]; then
  n="$(grep -c '^systemctl start uupd.service$' "${CALL_LOG}")"
  [ "$n" -le "${UUPD_FAILS}" ] && exit 1
fi
exit 0
STUB
	cat >"${STUB_BIN}/bootc" <<'STUB'
#!/usr/bin/bash
printf 'bootc %s\n' "$*" >> "${CALL_LOG}"
[ -n "${BOOTC_FAIL:-}" ] && exit 1
echo '{}'
STUB
	cat >"${STUB_BIN}/jq" <<'STUB'
#!/usr/bin/bash
cat >/dev/null
[ -n "${JQ_FAIL:-}" ] && exit 5
[ -n "${STAGED:-}" ]
STUB
	cat >"${STUB_BIN}/omadora-setup" <<'STUB'
#!/usr/bin/bash
printf 'omadora-setup %s\n' "$*" >> "${CALL_LOG}"
[ -n "${SETUP_FAIL:-}" ] && exit 1
exit 0
STUB
	chmod +x "${STUB_BIN}"/*

	export PATH="${STUB_BIN}:${PATH}"
	export CALL_LOG
	export OMADORA_UPDATE_RETRY_DELAY=0
	unset STAGED UUPD_FAILS SETUP_FAIL BOOTC_FAIL JQ_FAIL
}

@test "omadora-update: the default run updates the system and then the dotfiles" {
	run "${UPDATE_SRC}"
	[ "$status" -eq 0 ]
	mapfile -t calls <"${CALL_LOG}"
	[ "${calls[0]}" = "systemctl start uupd.service" ]
	[ "${calls[1]}" = "bootc status --json" ]
	[ "${calls[2]}" = "omadora-setup " ]
	[[ "$output" == *"Up to date"* ]]
}

@test "omadora-update: --system skips the dotfiles" {
	run "${UPDATE_SRC}" --system
	[ "$status" -eq 0 ]
	run grep -c omadora-setup "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "omadora-update: --dotfiles skips the system update" {
	run "${UPDATE_SRC}" --dotfiles
	[ "$status" -eq 0 ]
	[ "$(cat "${CALL_LOG}")" = "omadora-setup " ]
}

@test "omadora-update: --system and --dotfiles together exit 2 and run nothing" {
	run "${UPDATE_SRC}" --system --dotfiles
	[ "$status" -eq 2 ]
	[[ "$output" == *"cannot be combined"* ]]
	[ ! -e "${CALL_LOG}" ]
}

@test "omadora-update: an unknown argument exits 2 with the usage line and runs nothing" {
	run "${UPDATE_SRC}" --bogus
	[ "$status" -eq 2 ]
	[[ "$output" == *"usage: omadora-update"* ]]
	[ ! -e "${CALL_LOG}" ]
}

@test "omadora-update: --help prints the usage comment and runs nothing" {
	run "${UPDATE_SRC}" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"omadora-update --reboot"* ]]
	[ ! -e "${CALL_LOG}" ]
}

@test "omadora-update: a staged image prints the reboot hint and does not reboot" {
	STAGED=1 run "${UPDATE_SRC}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Reboot to run it"* ]]
	run grep -c "systemctl reboot" "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "omadora-update: --reboot reboots when an image is staged" {
	STAGED=1 run "${UPDATE_SRC}" --reboot
	[ "$status" -eq 0 ]
	[ "$(tail -n1 "${CALL_LOG}")" = "systemctl reboot" ]
}

@test "omadora-update: --reboot does nothing when no image is staged" {
	run "${UPDATE_SRC}" --reboot
	[ "$status" -eq 0 ]
	run grep -c "systemctl reboot" "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "omadora-update: a failed uupd start is retried and the run then succeeds" {
	UUPD_FAILS=1 run "${UPDATE_SRC}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"retrying in 0 seconds (attempt 1 of 3)"* ]]
	run grep -c '^systemctl start uupd.service$' "${CALL_LOG}"
	[ "$output" = "2" ]
	run grep -c "^omadora-setup" "${CALL_LOG}"
	[ "$output" = "1" ]
}

@test "omadora-update: uupd failing three times stops before the dotfiles" {
	UUPD_FAILS=99 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"uupd failed 3 times"* ]]
	run grep -c '^systemctl start uupd.service$' "${CALL_LOG}"
	[ "$output" = "3" ]
	run grep -c omadora-setup "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "omadora-update: a failing bootc status is an error, not 'nothing staged'" {
	BOOTC_FAIL=1 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"'bootc status' failed"* ]]
	[[ "$output" != *"Up to date"* ]]
	run grep -c omadora-setup "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "omadora-update: unreadable bootc status output is an error" {
	JQ_FAIL=1 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"could not read the output of 'bootc status'"* ]]
}

@test "omadora-update: a failed dotfiles update exits 1 and suggests --force" {
	SETUP_FAIL=1 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"omadora-setup --force"* ]]
}
