#!/usr/bin/env bats
# Unit tests for custom/files/usr/bin/omadora-update.
#
# sudo, systemctl, bootc, jq and omadora-setup are stubbed on PATH. Each stub
# appends its arguments to one shared log, so the tests can check order.
# STAGED=1 makes the jq stub report a staged system image. UUPD_FAILS=n makes the
# first n `systemctl start uupd.service` calls fail (a large n fails them all).
# BOOTC_FAIL=1 makes `bootc status` fail; JQ_FAIL=1 makes jq exit with an error.
# BOOTC_NOISE=1 makes `bootc status --json` print the fstab hint ahead of the JSON, as
# it does on a machine installed from the ISO. The jq stub rejects input that does
# not start with a JSON object, as the real jq would.
# After a failed start the script reads `systemctl show uupd.service`: ACTIVE_SEQ is a
# space-separated list of ActiveState values, one per check (the last repeats), and
# RESULT is the Result value (default success). After the start it also reads
# ConditionResult: CONDITION_RESULT=no simulates systemd skipping the unit because
# a start condition was unmet, such as ConditionACPower on battery (default yes).
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
if [ "$1" = "show" ]; then
  case "$*" in
    *"-p ActiveState"*)
      n="$(grep -c '^systemctl show uupd.service -p ActiveState' "${CALL_LOG}")"
      read -r -a seq <<< "${ACTIVE_SEQ:-inactive}"
      idx=$((n - 1))
      [ "${idx}" -ge "${#seq[@]}" ] && idx=$((${#seq[@]} - 1))
      echo "${seq[${idx}]}" ;;
    *"-p Result"*) echo "${RESULT:-success}" ;;
    *"-p ConditionResult"*) echo "${CONDITION_RESULT:-yes}" ;;
  esac
  exit 0
fi
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
if [ -n "${BOOTC_NOISE:-}" ]; then
  echo "mount: (hint) your fstab has been modified, but systemd still uses"
  echo "       the old version; use 'systemctl daemon-reload' to reload."
fi
if [ -n "${BOOTC_GARBAGE:-}" ]; then echo "not json at all"; exit 0; fi
echo '{}'
STUB
	cat >"${STUB_BIN}/jq" <<'STUB'
#!/usr/bin/bash
input="$(cat)"
case "${input}" in
  "{"*) ;;
  *) echo "jq: parse error: Invalid numeric literal at line 1, column 6" >&2; exit 2 ;;
esac
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
	export OMADORA_UPDATE_POLL_INTERVAL=0
	unset STAGED UUPD_FAILS SETUP_FAIL BOOTC_FAIL JQ_FAIL BOOTC_NOISE BOOTC_GARBAGE ACTIVE_SEQ RESULT OMADORA_UPDATE_POLL_LIMIT
}

@test "omadora-update: the default run updates the system and then the dotfiles" {
	run "${UPDATE_SRC}"
	[ "$status" -eq 0 ]
	mapfile -t calls <"${CALL_LOG}"
	[ "${calls[0]}" = "systemctl start uupd.service" ]
	[ "${calls[1]}" = "systemctl show uupd.service -p ConditionResult --value" ]
	[ "${calls[2]}" = "bootc status --json" ]
	[ "${calls[3]}" = "omadora-setup --update" ]
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
	[ "$(cat "${CALL_LOG}")" = "omadora-setup --update" ]
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

@test "omadora-update: a failed start followed by systemd's own successful restart counts as success" {
	UUPD_FAILS=1 ACTIVE_SEQ="activating activating inactive" run "${UPDATE_SRC}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"uupd is retrying on its own"* ]]
	run grep -c '^systemctl start uupd.service$' "${CALL_LOG}"
	[ "$output" = "1" ]
	run grep -c 'reset-failed' "${CALL_LOG}"
	[ "$output" = "0" ]
	run grep -c "^omadora-setup" "${CALL_LOG}"
	[ "$output" = "1" ]
}

@test "omadora-update: a failed unit is cleared with reset-failed before it is started again" {
	UUPD_FAILS=1 ACTIVE_SEQ="failed" run "${UPDATE_SRC}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"starting it again"* ]]
	mapfile -t calls <"${CALL_LOG}"
	starts=0
	reset_before_second=0
	for c in "${calls[@]}"; do
		[ "${c}" = "systemctl start uupd.service" ] && starts=$((starts + 1))
		[ "${c}" = "systemctl reset-failed uupd.service" ] && [ "${starts}" -eq 1 ] && reset_before_second=1
	done
	[ "${starts}" -eq 2 ]
	[ "${reset_before_second}" -eq 1 ]
}

@test "omadora-update: an inactive unit whose last result was a failure is not success" {
	UUPD_FAILS=1 ACTIVE_SEQ="inactive" RESULT="exit-code" run "${UPDATE_SRC}"
	[ "$status" -eq 0 ]
	run grep -c '^systemctl start uupd.service$' "${CALL_LOG}"
	[ "$output" = "2" ]
}

@test "omadora-update: uupd failing three times stops before the dotfiles" {
	UUPD_FAILS=99 ACTIVE_SEQ="failed" run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"uupd failed 3 times"* ]]
	run grep -c '^systemctl start uupd.service$' "${CALL_LOG}"
	[ "$output" = "3" ]
	# reset-failed runs between attempts, not after the last one.
	run grep -c 'reset-failed' "${CALL_LOG}"
	[ "$output" = "2" ]
	run grep -c omadora-setup "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "omadora-update: waiting for a unit that never settles is bounded" {
	UUPD_FAILS=99 ACTIVE_SEQ="activating" OMADORA_UPDATE_POLL_LIMIT=3 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	run grep -c 'show uupd.service -p ActiveState' "${CALL_LOG}"
	# At most 3 checks for each of the 3 attempts.
	[ "$output" -le 9 ]
	[ "$output" -ge 3 ]
}

@test "omadora-update: a failing bootc status is an error, not 'nothing staged'" {
	BOOTC_FAIL=1 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"'bootc status' failed"* ]]
	[[ "$output" != *"Up to date"* ]]
	run grep -c omadora-setup "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "omadora-update: the fstab hint that bootc prints before the JSON is ignored" {
	BOOTC_NOISE=1 run "${UPDATE_SRC}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Up to date"* ]]
}

@test "omadora-update: with the fstab hint present a staged image is still detected and --reboot reboots" {
	BOOTC_NOISE=1 STAGED=1 run "${UPDATE_SRC}" --reboot
	[ "$status" -eq 0 ]
	[ "$(tail -n1 "${CALL_LOG}")" = "systemctl reboot" ]
}

@test "omadora-update: output with no JSON object at all is still an error" {
	BOOTC_GARBAGE=1 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"could not read the output of 'bootc status'"* ]]
}

@test "omadora-update: unreadable bootc status output is an error" {
	JQ_FAIL=1 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"could not read the output of 'bootc status'"* ]]
}

@test "omadora-update: a failed dotfiles update exits 1 and suggests --force" {
	SETUP_FAIL=1 run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"omadora-setup --update --force"* ]]
}

@test "omadora-update: a unit skipped by an unmet start condition (on battery) is an error, not 'Up to date'" {
	CONDITION_RESULT=no run "${UPDATE_SRC}"
	[ "$status" -eq 1 ]
	[[ "$output" == *"on battery"* ]]
	[[ "$output" == *"sudo bootc upgrade"* ]]
	[[ "$output" != *"Up to date"* ]]
	run grep -c "bootc status" "${CALL_LOG}"
	[ "$output" = "0" ]
	run grep -c omadora-setup "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "omadora-update: --system on battery also stops with the battery error" {
	CONDITION_RESULT=no run "${UPDATE_SRC}" --system
	[ "$status" -eq 1 ]
	[[ "$output" == *"plug in"* ]]
}
