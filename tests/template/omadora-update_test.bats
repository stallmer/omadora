#!/usr/bin/env bats
# Unit tests for custom/files/usr/bin/omadora-update.
#
# sudo, systemctl, bootc, jq and omadora-setup are stubbed on PATH. Each stub
# appends its arguments to one shared log, so the tests can check order.
# STAGED=1 makes the bootc and jq stubs report a staged system image.
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
[ -n "${UUPD_FAIL:-}" ] && [ "$1 $2" = "start uupd.service" ] && exit 1
exit 0
STUB
	cat >"${STUB_BIN}/bootc" <<'STUB'
#!/usr/bin/bash
printf 'bootc %s\n' "$*" >> "${CALL_LOG}"
echo '{}'
STUB
	cat >"${STUB_BIN}/jq" <<'STUB'
#!/usr/bin/bash
cat >/dev/null
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
	unset STAGED UUPD_FAIL SETUP_FAIL
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

@test "omadora-update: a failed system update stops before the dotfiles" {
	UUPD_FAIL=1 run "${UPDATE_SRC}"
	[ "$status" -ne 0 ]
	run grep -c omadora-setup "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "omadora-update: a failed dotfiles update exits 1 and suggests --force" {
	SETUP_FAIL=1 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"omadora-setup --force"* ]]
}
