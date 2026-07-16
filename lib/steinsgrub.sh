#!/usr/bin/env bash

steinsgrub_sha256_matches() {
    local file="$1"
    local expected_sha256="$2"

    [[ -f "${file}" && ! -L "${file}" && "${expected_sha256}" =~ ^[0-9a-f]{64}$ ]] \
        || return 1
    printf '%s  %s\n' "${expected_sha256}" "${file}" \
        | sha256sum --check --status
}

fetch_steinsgrub_archive() {
    local destination="$1"
    local url="$2"
    local expected_sha256="$3"
    local partial="${destination}.part.$$"

    if steinsgrub_sha256_matches "${destination}" "${expected_sha256}"; then
        return 0
    fi

    mkdir -p -- "${destination%/*}" || return 1
    rm -f -- "${partial}"
    if ! curl \
        --fail \
        --location \
        --retry 3 \
        --proto '=https' \
        --tlsv1.2 \
        --header "User-Agent: ${STEINSGRUB_USER_AGENT}" \
        --header "Accept: ${STEINSGRUB_ACCEPT}" \
        --header "Accept-Language: ${STEINSGRUB_ACCEPT_LANGUAGE}" \
        --header "Referer: ${STEINSGRUB_REFERER}" \
        --output "${partial}" \
        "${url}"; then
        rm -f -- "${partial}"
        return 1
    fi

    if ! steinsgrub_sha256_matches "${partial}" "${expected_sha256}"; then
        rm -f -- "${partial}" "${destination}"
        return 1
    fi

    mv -f -- "${partial}" "${destination}"
}

validate_steinsgrub_theme_tree() {
    local theme_dir="$1"
    local manifest="$2"
    local manifest_path
    local expected_files actual_files
    local digest relative_path extra expected_file
    local file_count=0
    local -a expected_paths=()

    [[ -d "${theme_dir}" && ! -L "${theme_dir}" ]] || return 1
    [[ -f "${manifest}" && ! -L "${manifest}" ]] || return 1
    manifest_path="$(realpath -- "${manifest}")" || return 1

    while read -r digest relative_path extra; do
        [[ -n "${digest}" && -n "${relative_path}" && -z "${extra:-}" ]] || return 1
        [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "${relative_path}" != /* && "${relative_path}" != *..* && "${relative_path}" != */* ]] \
            || return 1
        expected_paths+=("${relative_path}")
        ((file_count += 1))
    done < "${manifest_path}"
    (( file_count > 0 )) || return 1

    for expected_file in "${expected_paths[@]}"; do
        [[ -f "${theme_dir}/${expected_file}" && ! -L "${theme_dir}/${expected_file}" ]] || return 1
    done

    if find "${theme_dir}" -mindepth 1 \( ! -type f -o -type f -links +1 \) -print -quit \
        | grep -q .; then
        return 1
    fi

    expected_files="$(awk '{ print $2 }' "${manifest_path}" | LC_ALL=C sort)" || return 1
    actual_files="$(
        find "${theme_dir}" -mindepth 1 -maxdepth 1 -printf '%f\n' \
            | LC_ALL=C sort
    )" || return 1
    [[ "${actual_files}" == "${expected_files}" ]] || return 1

    (
        cd "${theme_dir}"
        sha256sum --check --strict --status "${manifest_path}"
    )
}

prepare_steinsgrub_source() {
    local archive="$1"
    local output_dir="$2"
    local manifest="$3"
    local archive_root="${4:-steinsgrub-theme-${STEINSGRUB_COMMIT}}"
    local runtime_prefix="${archive_root}/steinsgrub"
    local member member_type relative_path
    local index
    local -a members=() member_types=() runtime_members=()
    local -A expected_runtime=() seen_runtime=()

    [[ -f "${archive}" && ! -L "${archive}" ]] || return 1
    [[ ! -e "${output_dir}" && ! -L "${output_dir}" ]] || return 1
    [[ -f "${manifest}" && ! -L "${manifest}" ]] || return 1

    while read -r _ relative_path _; do
        [[ -n "${relative_path}" ]] || return 1
        expected_runtime["${relative_path}"]=1
    done < "${manifest}"

    mapfile -t members < <(tar -tzf "${archive}") || return 1
    mapfile -t member_types < <(tar -tvzf "${archive}" | cut -c1) || return 1
    [[ "${#members[@]}" -eq "${#member_types[@]}" ]] || return 1

    for index in "${!members[@]}"; do
        member="${members[index]}"
        member_type="${member_types[index]}"
        [[ -n "${member}" && "${member}" != /* ]] || return 1
        case "/${member}/" in
            */../*|*/./*) return 1 ;;
        esac
        case "${member}" in
            "${archive_root}"|"${archive_root}/"|"${archive_root}/"*) ;;
            *) return 1 ;;
        esac

        case "${member}" in
            "${runtime_prefix}"|"${runtime_prefix}/")
                [[ "${member_type}" == d ]] || return 1
                ;;
            "${runtime_prefix}/"*)
                relative_path="${member#"${runtime_prefix}/"}"
                [[ "${relative_path}" != */* ]] || return 1
                [[ "${member_type}" == - ]] || return 1
                [[ -n "${expected_runtime[${relative_path}]:-}" ]] || return 1
                [[ -z "${seen_runtime[${relative_path}]:-}" ]] || return 1
                seen_runtime["${relative_path}"]=1
                runtime_members+=("${member}")
                ;;
        esac
    done

    [[ "${#runtime_members[@]}" -eq "${#expected_runtime[@]}" ]] || return 1

    mkdir -p -- "${output_dir}" || return 1
    if ! tar \
        --extract \
        --gzip \
        --file "${archive}" \
        --directory "${output_dir}" \
        --strip-components=2 \
        --no-wildcards \
        --no-recursion \
        --no-same-owner \
        --no-same-permissions \
        --no-xattrs \
        --no-acls \
        --no-selinux \
        --keep-old-files \
        "${runtime_members[@]}"; then
        rm -rf -- "${output_dir}"
        return 1
    fi

    if ! validate_steinsgrub_theme_tree "${output_dir}" "${manifest}"; then
        rm -rf -- "${output_dir}"
        return 1
    fi
}

write_grub_theme_config() {
    local source_config="$1"
    local output_config="$2"
    local theme_path="$3"
    local assignment
    local temporary_output="${output_config}.tmp.$$"

    [[ -f "${source_config}" && ! -L "${source_config}" ]] || return 1
    [[ "${theme_path}" == /* && "${theme_path}" != *"'"* && "${theme_path}" != *$'\n'* ]] \
        || return 1
    assignment="GRUB_THEME='${theme_path}'"

    rm -f -- "${temporary_output}"
    if ! awk -v assignment="${assignment}" '
        /^[[:space:]]*(export[[:space:]]+)?GRUB_THEME[[:space:]]*=/ {
            count++
            if (count == 1) print assignment
            next
        }
        { print }
        END {
            if (count == 0) print assignment
            if (count > 1) exit 42
        }
    ' "${source_config}" > "${temporary_output}"; then
        rm -f -- "${temporary_output}"
        return 1
    fi

    if ! bash -n "${temporary_output}" \
        || [[ "$(grep -Ec '^[[:space:]]*(export[[:space:]]+)?GRUB_THEME[[:space:]]*=' "${temporary_output}")" -ne 1 ]] \
        || ! cmp -s \
            <(grep -Ev '^[[:space:]]*(export[[:space:]]+)?GRUB_THEME[[:space:]]*=' "${source_config}") \
            <(grep -Ev '^[[:space:]]*(export[[:space:]]+)?GRUB_THEME[[:space:]]*=' "${temporary_output}"); then
        rm -f -- "${temporary_output}"
        return 1
    fi

    mv -f -- "${temporary_output}" "${output_config}"
}

steinsgrub_source_path_is_trusted() {
    local source_path="${1:-}"
    local expected_owner="${2:-0}"
    local actual_owner mode numeric_mode

    [[ "${expected_owner}" =~ ^[0-9]+$ ]] || return 1
    [[ ! -L "${source_path}" \
        && ( -f "${source_path}" || -d "${source_path}" ) ]] || return 1
    actual_owner="$(stat -c '%u' -- "${source_path}")" || return 1
    [[ "${actual_owner}" == "${expected_owner}" ]] || return 1
    mode="$(stat -c '%a' -- "${source_path}")" || return 1
    [[ "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
    numeric_mode=$((8#${mode}))
    (( (numeric_mode & 022) == 0 ))
}

_steinsgrub_arguments_are_unambiguous() {
    local arguments="$1"

    [[ "${arguments}" != *$'\n'* \
        && "${arguments}" != *$'\r'* \
        && "${arguments}" != *$'\t'* \
        && "${arguments}" != *"'"* \
        && "${arguments}" != *'"'* \
        && "${arguments}" != *\\* ]]
}

_steinsgrub_arguments_contain_ordered_subsequence() {
    local actual_name="$1"
    local expected_name="$2"
    local -n actual_arguments="${actual_name}"
    local -n expected_arguments="${expected_name}"
    local expected_index=0
    local argument

    [[ "${#expected_arguments[@]}" -gt 0 ]] || return 0
    for argument in "${actual_arguments[@]}"; do
        if [[ "${argument}" == "${expected_arguments[${expected_index}]}" ]]; then
            expected_index=$((expected_index + 1))
            [[ "${expected_index}" -lt "${#expected_arguments[@]}" ]] || return 0
        fi
    done
    return 1
}

validate_steinsgrub_kernel_arguments() {
    local defaults_config="${1:-}"
    local generated_config="${2:-}"
    local loaded_values default_command_line global_command_line config_line
    local menuentry_header
    local line_count=0
    local menuentry_context=0
    local menuentry_is_recovery=0
    local IFS=$' \t\n'
    local -a values=()
    local -a default_arguments=()
    local -a global_arguments=()
    local -a combined_arguments=()
    local -a generated_line=()
    local -a generated_arguments=()

    [[ -f "${defaults_config}" && ! -L "${defaults_config}" ]] || return 1
    [[ -f "${generated_config}" && ! -L "${generated_config}" ]] || return 1
    loaded_values="$(
        bash --noprofile --norc -c '
            set -e
            unset GRUB_CMDLINE_LINUX_DEFAULT GRUB_CMDLINE_LINUX
            source "$1" >/dev/null
            printf "%s\n%s\n__DOTFILES_GRUB_VALUES_END__\n" \
                "${GRUB_CMDLINE_LINUX_DEFAULT:-}" \
                "${GRUB_CMDLINE_LINUX:-}"
        ' bash "${defaults_config}"
    )" || return 1
    mapfile -t values <<< "${loaded_values}"
    [[ "${#values[@]}" -eq 3 \
        && "${values[2]}" == __DOTFILES_GRUB_VALUES_END__ ]] || return 1
    default_command_line="${values[0]}"
    global_command_line="${values[1]}"
    _steinsgrub_arguments_are_unambiguous "${default_command_line}" || return 1
    _steinsgrub_arguments_are_unambiguous "${global_command_line}" || return 1
    read -r -a default_arguments <<< "${default_command_line}"
    read -r -a global_arguments <<< "${global_command_line}"
    combined_arguments=("${global_arguments[@]}" "${default_arguments[@]}")

    while IFS= read -r config_line || [[ -n "${config_line}" ]]; do
        if [[ "${config_line}" =~ ^[[:space:]]*menuentry[[:space:]] ]]; then
            [[ "${menuentry_context}" -eq 0 \
                && "${config_line}" == *'{'* \
                && "${config_line}" != *'}'* ]] || return 1
            menuentry_context=1
            menuentry_header="${config_line,,}"
            menuentry_is_recovery=0
            if [[ "${menuentry_header}" =~ --class[[:space:]]+recovery \
                || "${menuentry_header}" == *recovery* ]]; then
                menuentry_is_recovery=1
            fi
            continue
        fi

        if [[ "${menuentry_context}" -eq 0 ]]; then
            if [[ "${config_line}" =~ ^[[:space:]]*(linux|linuxefi)[[:space:]] ]]; then
                return 1
            fi
            continue
        fi

        if [[ "${config_line}" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
            menuentry_context=0
            menuentry_is_recovery=0
            continue
        fi
        if [[ "${config_line}" == *'{'* || "${config_line}" == *'}'* ]]; then
            return 1
        fi

        if [[ "${config_line}" =~ ^[[:space:]]*(linux|linuxefi)[[:space:]] ]]; then
            line_count=$((line_count + 1))
            generated_line=()
            generated_arguments=()
            read -r -a generated_line <<< "${config_line}"
            [[ "${#generated_line[@]}" -ge 2 ]] || return 1
            generated_arguments=("${generated_line[@]:2}")
            if [[ "${menuentry_is_recovery}" -eq 1 ]]; then
                _steinsgrub_arguments_contain_ordered_subsequence \
                    generated_arguments global_arguments || return 1
            else
                _steinsgrub_arguments_contain_ordered_subsequence \
                    generated_arguments combined_arguments || return 1
            fi
        fi
    done < "${generated_config}"

    [[ "${menuentry_context}" -eq 0 \
        && "${line_count}" -gt 0 ]]
}
