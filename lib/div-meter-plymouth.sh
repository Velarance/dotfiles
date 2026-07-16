#!/usr/bin/env bash

readonly DIV_METER_THEME_NAME="div-meter"
readonly DIV_METER_THEME_PATH="/usr/share/plymouth/themes/div-meter"
readonly DIV_METER_MANIFEST_SHA256="b7b455d7cd82cacf649fa9ff5072334bf767202fc159b56d2abb0a9f9d43d964"
readonly DIV_METER_UPSTREAM_COMMIT="7fe92523659811b0339ea60af4a92aff5fd4a256"

validate_div_meter_theme_tree() {
    local theme_dir="${1:-}"
    local manifest="${2:-}"
    local digest relative_path extra
    local -a actual_files=()
    local -a expected_files=(
        LICENSE
        div-meter.plymouth
        div-meter.script
    )
    local -A seen=()

    [[ -d "${theme_dir}" && ! -L "${theme_dir}" ]] || return 1
    [[ -f "${manifest}" && ! -L "${manifest}" ]] || return 1
    [[ -f "${theme_dir}/UPSTREAM" && ! -L "${theme_dir}/UPSTREAM" ]] || return 1
    [[ -f "${theme_dir}/SHA256SUMS" && ! -L "${theme_dir}/SHA256SUMS" ]] || return 1
    [[ "$(realpath -e -- "${manifest}")" == "$(realpath -e -- "${theme_dir}/SHA256SUMS")" ]] \
        || return 1
    [[ "$(sha256sum "${manifest}" | awk '{print $1}')" == "${DIV_METER_MANIFEST_SHA256}" ]] \
        || return 1

    for relative_path in {end{0..32},loop{0..8}}.png; do
        expected_files+=("${relative_path}")
    done

    while read -r digest relative_path extra; do
        [[ -z "${extra:-}" ]] || return 1
        [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "${relative_path}" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
        [[ -z "${seen[${relative_path}]:-}" ]] || return 1
        seen["${relative_path}"]=1
        [[ -f "${theme_dir}/${relative_path}" && ! -L "${theme_dir}/${relative_path}" ]] \
            || return 1
    done < "${manifest}"

    [[ "${#seen[@]}" -eq 45 ]] || return 1
    for relative_path in "${expected_files[@]}"; do
        [[ -n "${seen[${relative_path}]:-}" ]] || return 1
    done

    mapfile -t actual_files < <(
        find "${theme_dir}" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' \
            | LC_ALL=C sort
    )
    [[ "${#actual_files[@]}" -eq 47 ]] || return 1
    if find "${theme_dir}" -mindepth 1 \( -type l -o -type d -o ! -type f \) -print -quit \
        | grep -q .; then
        return 1
    fi
    for relative_path in "${actual_files[@]}"; do
        case "${relative_path}" in
            SHA256SUMS|UPSTREAM) ;;
            *) [[ -n "${seen[${relative_path}]:-}" ]] || return 1 ;;
        esac
    done

    grep -Fxq "Commit: ${DIV_METER_UPSTREAM_COMMIT}" "${theme_dir}/UPSTREAM" \
        || return 1
    grep -Fxq 'License: GPL-3.0' "${theme_dir}/UPSTREAM" || return 1
    grep -Fxq 'ModuleName=script' "${theme_dir}/div-meter.plymouth" || return 1
    grep -Fxq "ImageDir=${DIV_METER_THEME_PATH}" "${theme_dir}/div-meter.plymouth" \
        || return 1
    grep -Fxq "ScriptFile=${DIV_METER_THEME_PATH}/div-meter.script" \
        "${theme_dir}/div-meter.plymouth" || return 1
    grep -Fq 'end_imgs[NUM_END_FRAMES - 1]' "${theme_dir}/div-meter.script" \
        || return 1
    ! grep -Fq 'end_imags' "${theme_dir}/div-meter.script" || return 1

    (cd "${theme_dir}" && sha256sum --strict -c SHA256SUMS >/dev/null 2>&1)
}

write_mkinitcpio_plymouth_config() {
    local source_config="${1:-}"
    local destination="${2:-}"
    local assignment assignment_number prefix hook anchor
    local plymouth_count=0
    local anchor_count=0
    local -a assignments=()
    local -a hooks=()
    local -a updated_hooks=()

    [[ -f "${source_config}" && ! -L "${source_config}" ]] || return 1
    [[ -n "${destination}" ]] || return 1
    mapfile -t assignments < <(
        grep -nE '^[[:space:]]*HOOKS[[:space:]]*=' "${source_config}" || true
    )
    [[ "${#assignments[@]}" -eq 1 ]] || return 1
    assignment_number="${assignments[0]%%:*}"
    assignment="${assignments[0]#*:}"
    [[ "${assignment}" =~ ^([[:space:]]*)HOOKS[[:space:]]*=[[:space:]]*\(([^()]*)\)[[:space:]]*$ ]] \
        || return 1
    prefix="${BASH_REMATCH[1]}"
    read -r -a hooks <<< "${BASH_REMATCH[2]}"
    [[ "${#hooks[@]}" -gt 0 ]] || return 1

    for hook in "${hooks[@]}"; do
        [[ "${hook}" =~ ^[A-Za-z0-9_+-]+$ ]] || return 1
        [[ "${hook}" == plymouth ]] && ((plymouth_count += 1))
    done
    [[ "${plymouth_count}" -le 1 ]] || return 1
    if [[ "${plymouth_count}" -eq 1 ]]; then
        cp -- "${source_config}" "${destination}"
        return
    fi

    anchor=systemd
    for hook in "${hooks[@]}"; do
        [[ "${hook}" == systemd ]] && ((anchor_count += 1))
    done
    if [[ "${anchor_count}" -eq 0 ]]; then
        anchor=udev
        for hook in "${hooks[@]}"; do
            [[ "${hook}" == udev ]] && ((anchor_count += 1))
        done
    fi
    [[ "${anchor_count}" -eq 1 ]] || return 1

    for hook in "${hooks[@]}"; do
        updated_hooks+=("${hook}")
        [[ "${hook}" == "${anchor}" ]] && updated_hooks+=(plymouth)
    done
    local replacement="${prefix}HOOKS=(${updated_hooks[*]})"
    awk -v line="${assignment_number}" -v replacement="${replacement}" '
        NR == line { print replacement; next }
        { print }
    ' "${source_config}" > "${destination}" || return 1
    bash -n "${destination}"
}

write_grub_splash_config() {
    local source_config="${1:-}"
    local destination="${2:-}"
    local assignment assignment_number prefix command_line token replacement
    local splash_count=0
    local -a assignments=()
    local -a arguments=()

    [[ -f "${source_config}" && ! -L "${source_config}" ]] || return 1
    [[ -n "${destination}" ]] || return 1
    mapfile -t assignments < <(
        grep -nE '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT[[:space:]]*=' "${source_config}" \
            || true
    )
    [[ "${#assignments[@]}" -eq 1 ]] || return 1
    assignment_number="${assignments[0]%%:*}"
    assignment="${assignments[0]#*:}"
    [[ "${assignment}" =~ ^([[:space:]]*)GRUB_CMDLINE_LINUX_DEFAULT[[:space:]]*= ]] \
        || return 1
    prefix="${BASH_REMATCH[1]}"
    command_line="$(
        bash --noprofile --norc -c '
            source "$1"
            printf "%s" "${GRUB_CMDLINE_LINUX_DEFAULT:-}"
        ' bash "${source_config}"
    )" || return 1
    [[ "${command_line}" != *$'\n'* && "${command_line}" != *"'"* ]] || return 1
    read -r -a arguments <<< "${command_line}"
    for token in "${arguments[@]}"; do
        [[ "${token}" == splash ]] && ((splash_count += 1))
    done
    [[ "${splash_count}" -le 1 ]] || return 1
    if [[ "${splash_count}" -eq 1 ]]; then
        cp -- "${source_config}" "${destination}"
        return
    fi

    command_line="${command_line:+${command_line} }splash"
    replacement="${prefix}GRUB_CMDLINE_LINUX_DEFAULT='${command_line}'"
    awk -v line="${assignment_number}" -v replacement="${replacement}" '
        NR == line { print replacement; next }
        { print }
    ' "${source_config}" > "${destination}" || return 1
    bash -n "${destination}"
}

source_path_is_trusted() {
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

grub_defaults_file_is_trusted() {
    source_path_is_trusted "$@"
}

_grub_arguments_are_unambiguous() {
    local arguments="$1"

    [[ "${arguments}" != *$'\n'* \
        && "${arguments}" != *$'\r'* \
        && "${arguments}" != *$'\t'* \
        && "${arguments}" != *"'"* \
        && "${arguments}" != *'"'* \
        && "${arguments}" != *\\* ]]
}

_grub_arguments_contain_ordered_subsequence() {
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

validate_grub_kernel_arguments() {
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
    _grub_arguments_are_unambiguous "${default_command_line}" || return 1
    _grub_arguments_are_unambiguous "${global_command_line}" || return 1
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
                _grub_arguments_contain_ordered_subsequence \
                    generated_arguments global_arguments || return 1
            else
                _grub_arguments_contain_ordered_subsequence \
                    generated_arguments combined_arguments || return 1
            fi
        fi
    done < "${generated_config}"

    [[ "${menuentry_context}" -eq 0 \
        && "${line_count}" -gt 0 ]]
}

list_mkinitcpio_images() {
    local preset_dir="${1:-}"
    local expected_owner="${2-}"
    local preset output image
    local trust_sources=0
    local -a presets=()
    local -a images=()

    [[ "$#" -ge 1 && "$#" -le 2 ]] || return 1
    [[ -d "${preset_dir}" && ! -L "${preset_dir}" ]] || return 1
    if [[ "$#" -eq 2 ]]; then
        [[ "${expected_owner}" =~ ^[0-9]+$ ]] || return 1
        trust_sources=1
        source_path_is_trusted "${preset_dir}" "${expected_owner}" || return 1
    fi
    if find "${preset_dir}" -mindepth 1 -maxdepth 1 -name '*.preset' ! -type f \
        -print -quit | grep -q .; then
        return 1
    fi
    mapfile -d '' -t presets < <(
        find "${preset_dir}" -mindepth 1 -maxdepth 1 -type f -name '*.preset' \
            -print0 | LC_ALL=C sort -z
    )
    [[ "${#presets[@]}" -gt 0 ]] || return 1

    for preset in "${presets[@]}"; do
        [[ ! -L "${preset}" ]] || return 1
        if [[ "${trust_sources}" -eq 1 ]]; then
            source_path_is_trusted "${preset}" "${expected_owner}" || return 1
        fi
        output="$(
            bash --noprofile --norc -c '
                set -eu
                source "$1"
                declare -p PRESETS >/dev/null 2>&1
                (("${#PRESETS[@]}" > 0))
                for preset_name in "${PRESETS[@]}"; do
                    image_var="${preset_name}_image"
                    uki_var="${preset_name}_uki"
                    image="${!image_var-}"
                    uki="${!uki_var-}"
                    [[ -z "${uki}" ]]
                    [[ -n "${image}" && "${image}" == /* ]]
                    printf "%s\n" "${image}"
                done
            ' bash "${preset}"
        )" || return 1
        while IFS= read -r image; do
            [[ -n "${image}" ]] && images+=("${image}")
        done <<< "${output}"
    done
    [[ "${#images[@]}" -gt 0 ]] || return 1
    if printf '%s\n' "${images[@]}" | LC_ALL=C sort | uniq -d | grep -q .; then
        return 1
    fi
    printf '%s\n' "${images[@]}" | LC_ALL=C sort
}
