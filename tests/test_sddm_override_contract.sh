#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/install.sh"
OVERRIDE="$ROOT/config/sddm/dotfiles-override.conf"
test_tmp="$(mktemp -d)"

cleanup() {
    rm -rf -- "$test_tmp"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

installer_function_body() {
    local function_name="$1"

    awk -v function_name="$function_name" '
        $0 ~ ("^[[:space:]]*" function_name "[[:space:]]*\\(\\)[[:space:]]*\\{") {
            capture = 1
        }
        capture {
            print
            opens = gsub(/\{/, "{")
            closes = gsub(/\}/, "}")
            depth += opens - closes
            if (depth == 0) {
                exit
            }
        }
    ' "$INSTALLER"
}

fixture_conf="$test_tmp/sddm.conf"
fixture_stage="$test_tmp/.sddm.conf.dotfiles-new"
fixture_backup="$test_tmp/sddm.conf.dotfiles-backup"
critical_settings_body="$(installer_function_body validate_sddm_critical_settings)"
managed_override_body="$(installer_function_body validate_sddm_managed_override_source)"
backup_validator_body="$(installer_function_body validate_root_file_backup)"
backup_helper_body="$(installer_function_body create_root_file_backup_once)"
backup_locked_body="$(installer_function_body create_root_file_backup_once_locked)"
override_body="$(installer_function_body install_sddm_final_override)"
[[ -n "$critical_settings_body" ]] || fail 'validate_sddm_critical_settings is missing'
[[ -n "$managed_override_body" ]] || fail 'validate_sddm_managed_override_source is missing'
[[ -n "$backup_validator_body" ]] || fail 'validate_root_file_backup is missing'
[[ -n "$backup_helper_body" ]] || fail 'create_root_file_backup_once is missing'
[[ -n "$backup_locked_body" ]] || fail 'create_root_file_backup_once_locked is missing'
[[ -n "$override_body" ]] || fail 'install_sddm_final_override is missing'

override_body="$(printf '%s\n' "$override_body" | sed \
    -e "s|/etc/.sddm.conf.dotfiles-new|$fixture_stage|g" \
    -e "s|/etc/sddm.conf.dotfiles-backup|$fixture_backup|g" \
    -e "s|/etc/sddm.conf|$fixture_conf|g")"

print_error() {
    :
}

print_warning() {
    :
}

FAIL_BACKUP_COPY_ONCE=0
FAIL_BACKUP_PROMOTE_ONCE=0
FAKE_BACKUP_PATH=''
INJECT_CONFIG_CHANGE_ON_EXCHANGE=0
INJECT_SECOND_CONFIG_CHANGE_ON_ROLLBACK=0

sudo() {
    local command_name="$1"
    shift

    case "$command_name" in
        install)
            while [[ "$1" == -* ]]; do
                case "$1" in
                    -o|-g|-m) shift 2 ;;
                    *) shift ;;
                esac
            done
            install -m 0644 "$1" "$2"
            ;;
        chown)
            :
            ;;
        cp)
            if (( FAIL_BACKUP_COPY_ONCE )) && [[ "${@: -1}" == "${FAKE_BACKUP_PATH}.dotfiles-new" ]]; then
                printf 'partial\n' > "${FAKE_BACKUP_PATH}.dotfiles-new"
                FAIL_BACKUP_COPY_ONCE=0
                return 74
            fi
            command cp "$@"
            ;;
        mv)
            if (( INJECT_CONFIG_CHANGE_ON_EXCHANGE )) \
                && [[ " $* " == *" --exchange "* && "${@: -1}" == "$fixture_conf" ]]; then
                printf '%s\n' '[General]' 'Numlock=off' '# concurrent admin change' > "$fixture_conf"
                INJECT_CONFIG_CHANGE_ON_EXCHANGE=0
            elif (( INJECT_SECOND_CONFIG_CHANGE_ON_ROLLBACK )) \
                && [[ " $* " == *" --exchange "* && "${@: -1}" == "$fixture_conf" ]]; then
                printf '%s\n' '[General]' 'Numlock=off' '# second concurrent admin change' > "$fixture_conf"
                INJECT_SECOND_CONFIG_CHANGE_ON_ROLLBACK=0
            fi
            if (( FAIL_BACKUP_PROMOTE_ONCE )) && [[ "${@: -1}" == "${FAKE_BACKUP_PATH}" ]]; then
                FAIL_BACKUP_PROMOTE_ONCE=0
                return 75
            fi
            command mv "$@"
            ;;
        *)
            command "$command_name" "$@"
            ;;
    esac
}

eval "$critical_settings_body"
eval "$managed_override_body"
eval "$backup_validator_body"
eval "$backup_helper_body"
eval "$backup_locked_body"
eval "$override_body"

helper_source="$test_tmp/helper-source"
helper_backup="$test_tmp/helper-backup"
helper_stage="${helper_backup}.dotfiles-new"
helper_checksum="${helper_backup}.sha256"
helper_checksum_stage="${helper_checksum}.dotfiles-new"
FAKE_BACKUP_PATH="$helper_backup"

printf 'first backup\n' > "$helper_source"
create_root_file_backup_once "$helper_source" "$helper_backup"
cmp -s "$helper_source" "$helper_backup" \
    || fail 'first backup must exactly match its source'
[[ ! -e "$helper_stage" ]] || fail 'successful backup must remove its staging path'
validate_root_file_backup "$helper_backup" \
    || fail 'first backup must include a valid SHA-256 sidecar'

backup_stat="$(stat -c '%i:%Y:%s' "$helper_backup")"
printf 'later source\n' > "$helper_source"
printf 'stale\n' > "$helper_stage"
printf 'stale\n' > "$helper_checksum_stage"
create_root_file_backup_once "$helper_source" "$helper_backup"
[[ "$(< "$helper_backup")" == 'first backup' ]] \
    || fail 'an existing first backup must never be overwritten'
[[ "$(stat -c '%i:%Y:%s' "$helper_backup")" == "$backup_stat" ]] \
    || fail 'an existing first backup must remain untouched'
[[ ! -e "$helper_stage" && ! -e "$helper_checksum_stage" ]] \
    || fail 'an existing valid backup must clean stale staging files'

poison_source="$test_tmp/poison-source"
poison_backup="$test_tmp/poison-backup"
printf 'complete\n' > "$poison_source"
printf 'partial\n' > "$poison_backup"
if create_root_file_backup_once "$poison_source" "$poison_backup"; then
    fail 'a pre-existing backup without a valid checksum must be rejected'
fi
[[ "$(< "$poison_backup")" == 'partial' ]] \
    || fail 'an invalid pre-existing backup must be left for manual recovery'
rm -f -- "$poison_source"
if create_root_file_backup_once "$poison_source" "$poison_backup"; then
    fail 'a poisoned existing backup must be rejected even when its source is absent'
fi


symlink_target="$test_tmp/symlink-target"
symlink_source="$test_tmp/symlink-source"
symlink_backup="$test_tmp/symlink-backup"
printf 'linked\n' > "$symlink_target"
ln -s "$symlink_target" "$symlink_source"
if create_root_file_backup_once "$symlink_source" "$symlink_backup"; then
    fail 'a source symlink must be rejected instead of dereferenced'
fi
[[ -L "$symlink_source" && ! -e "$symlink_backup" ]] \
    || fail 'rejecting a source symlink must preserve its topology'


rm -f -- "$helper_backup"
FAIL_BACKUP_COPY_ONCE=1
if create_root_file_backup_once "$helper_source" "$helper_backup"; then
    fail 'a failed backup copy must fail closed'
fi
[[ ! -e "$helper_backup" ]] || fail 'a failed copy must not publish a partial backup'
[[ ! -e "$helper_stage" ]] || fail 'a failed copy must clean its staging path'
[[ ! -e "$helper_checksum" && ! -e "$helper_checksum_stage" ]] \
    || fail 'a failed copy must not publish or retain checksum files'
create_root_file_backup_once "$helper_source" "$helper_backup"
cmp -s "$helper_source" "$helper_backup" \
    || fail 'backup retry after a failed copy must preserve exact bytes'

rm -f -- "$helper_backup"
FAIL_BACKUP_PROMOTE_ONCE=1
if create_root_file_backup_once "$helper_source" "$helper_backup"; then
    fail 'a failed backup promotion must fail closed'
fi
[[ ! -e "$helper_backup" ]] || fail 'a failed promotion must not publish a backup'
[[ ! -e "$helper_stage" ]] || fail 'a failed promotion must clean its staging path'
[[ ! -e "$helper_checksum" && ! -e "$helper_checksum_stage" ]] \
    || fail 'a failed promotion must clean its published and staged checksums'
create_root_file_backup_once "$helper_source" "$helper_backup"
cmp -s "$helper_source" "$helper_backup" \
    || fail 'backup retry after a failed promotion must preserve exact bytes'

rm -f -- "$helper_backup"
mkdir "$helper_backup"
if create_root_file_backup_once "$helper_source" "$helper_backup"; then
    fail 'a non-file backup path must be rejected'
fi
rmdir "$helper_backup"
rm -f -- "$helper_source"
create_root_file_backup_once "$helper_source" "$helper_backup"
[[ ! -e "$helper_backup" && ! -e "$helper_stage" ]] \
    || fail 'a missing source must be a clean backup no-op'
[[ ! -e "$helper_checksum" && ! -e "$helper_checksum_stage" ]] \
    || fail 'a missing source with no backup must clean orphaned checksums'

printf '%s\n' \
    '[Autologin]' 'Session=hyprland' '' \
    '[General]' 'Numlock=on' 'DisplayServer=wayland' '' \
    '[Theme]' 'ThemeDir=/custom/sddm/themes' > "$fixture_conf"
cp "$fixture_conf" "$test_tmp/original.conf"

install_sddm_final_override "$OVERRIDE"
cp "$fixture_conf" "$test_tmp/first-run.conf"
install_sddm_final_override "$OVERRIDE"

cmp -s "$fixture_conf" "$test_tmp/first-run.conf" \
    || fail 'clean reruns must be byte-idempotent'
cmp -s "$fixture_backup" "$test_tmp/original.conf" \
    || fail 'the first existing config must be preserved as the rollback backup'
validate_root_file_backup "$fixture_backup" \
    || fail 'the rollback config backup must have a valid SHA-256 sidecar'
[[ ! -e "$fixture_stage" ]] \
    || fail 'the staging config must be atomically promoted or removed'
grep -Fxq 'Session=hyprland' "$fixture_conf" \
    || fail 'existing SDDM settings must be preserved'
[[ "$(grep -Fc '# BEGIN DOTFILES SDDM OVERRIDE' "$fixture_conf")" == 1 ]] \
    || fail 'exactly one managed override block must remain'
[[ "$(awk -F= '/^Current=/{value=$0} END {print value}' "$fixture_conf")" == 'Current=amadeus' ]] \
    || fail 'the final Current value must select Amadeus'
[[ "$(awk -F= '/^DisplayServer=/{value=$0} END {print value}' "$fixture_conf")" == 'DisplayServer=x11' ]] \
    || fail 'the final DisplayServer value must force X11 for monitor selection'
[[ "$(awk -F= '/^ThemeDir=/{value=$0} END {print value}' "$fixture_conf")" == 'ThemeDir=/usr/share/sddm/themes' ]] \
    || fail 'the final ThemeDir value must use the system theme directory'
INJECT_CONFIG_CHANGE_ON_EXCHANGE=1
INJECT_SECOND_CONFIG_CHANGE_ON_ROLLBACK=1
fixture_recovery="${fixture_conf}.dotfiles-recovery.$$"
printf '%s\n' '[General]' 'Numlock=on' '# before concurrent write' > "$fixture_conf"
if install_sddm_final_override "$OVERRIDE"; then
    fail 'a concurrent SDDM config write during exchange must abort activation'
fi
grep -Fxq '# concurrent admin change' "$fixture_conf" \
    || fail 'a concurrent admin config must be restored after exchange detection'
grep -Fxq '# second concurrent admin change' "$fixture_recovery" \
    || fail 'a second concurrent admin config must be preserved separately'
if grep -Fq '# BEGIN DOTFILES SDDM OVERRIDE' "$fixture_conf"; then
    fail 'the candidate override must not replace a concurrent admin config'
fi
[[ ! -e "$fixture_stage" ]] \
    || fail 'concurrent-write rollback must clean the exchanged staging file'

bad_override="$test_tmp/bad-override.conf"
cp "$OVERRIDE" "$bad_override"
printf '%s\n' '' '[Theme]' 'Current=silent' >> "$bad_override"
cp "$fixture_conf" "$test_tmp/bad-override-before.conf"
if install_sddm_final_override "$bad_override"; then
    fail 'an override source with trailing conflicting settings must be rejected'
fi
cmp -s "$fixture_conf" "$test_tmp/bad-override-before.conf" \
    || fail 'an invalid override source must leave the active config unchanged'

printf '%s\n' \
    '[General]' \
    'Numlock=on' \
    '# BEGIN DOTFILES SDDM OVERRIDE' \
    '[Theme]' \
    'Current=old' \
    '[General]' \
    'Numlock=off' > "$fixture_conf"
cp "$fixture_conf" "$test_tmp/unclosed-before.conf"
if install_sddm_final_override "$OVERRIDE"; then
    fail 'an unclosed managed block must be rejected'
fi
cmp -s "$fixture_conf" "$test_tmp/unclosed-before.conf" \
    || fail 'an unclosed marker must leave the active config unchanged'

printf '%s\n' \
    '[General]' \
    'Numlock=on' \
    '# BEGIN DOTFILES SDDM OVERRIDE' \
    '[Theme]' \
    'Current=old' \
    '# END DOTFILES SDDM OVERRIDE' \
    '[X11]' \
    'ServerArguments=-nolisten tcp' > "$fixture_conf"
cp "$fixture_conf" "$test_tmp/not-eof-before.conf"
if install_sddm_final_override "$OVERRIDE"; then
    fail 'a managed block before later admin settings must be rejected'
fi
cmp -s "$fixture_conf" "$test_tmp/not-eof-before.conf" \
    || fail 'a non-EOF managed block must leave the active config unchanged'

printf 'sddm override contract: ok\n'
