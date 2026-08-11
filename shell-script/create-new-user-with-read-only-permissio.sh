#!/usr/bin/env bash
#==============================================================================
# provision-readonly-user.sh
#
# Creates and maintains a read-only "auditor" account on Ubuntu 22.04 LTS
# (tested against the AWS EC2 cloud image).
#
#   * Can read files/directories anywhere the DAC permissions allow
#   * Cannot create, modify or delete files
#   * Cannot create directories (including in /tmp and other 1777 dirs)
#   * Has no sudo/root privileges (and an explicit sudo deny rule)
#   * Lands in /home/ubuntu on SSH login
#
# The script is idempotent: re-running it converges the configuration and
# never resets a password that has already been set (unless you pass one).
#
# Usage:
#   sudo ./provision-readonly-user.sh                 # provision + prompt for password
#   sudo ./provision-readonly-user.sh --skip-password # provision, leave password as-is
#   sudo ./provision-readonly-user.sh --password-stdin < pw.txt
#   sudo ./provision-readonly-user.sh --allow-from 203.0.113.4/32
#   sudo ./provision-readonly-user.sh --acls-only     # re-apply ACLs only (boot hook)
#   sudo ./provision-readonly-user.sh --verify        # run the acceptance tests
#   sudo ./provision-readonly-user.sh --revert        # undo everything but the account
#   sudo ./provision-readonly-user.sh --revert --delete-user
#   sudo ./provision-readonly-user.sh --dry-run       # show what would change
#
# Exit codes: 0 ok, 1 error, 2 usage error, 3 one or more --verify checks failed
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# Configuration (override via environment)
#------------------------------------------------------------------------------
USERNAME="${USERNAME:-securify-user}"
AUDIT_GROUP="${AUDIT_GROUP:-readonly-audit}"
LOGIN_DIR="${LOGIN_DIR:-/home/ubuntu}"
LOGIN_SHELL="${LOGIN_SHELL:-/bin/bash}"

# Supplementary groups that GRANT extra read access. Keep this list read-only:
#   adm             -> /var/log/*
#   systemd-journal -> journalctl
# NEVER add: sudo, admin, docker, lxd, disk, shadow, kvm, libvirt, root.
# Those are equivalent to root on this box.
READ_GROUPS=("adm" "systemd-journal")

# Memberships actively removed if found. These would defeat requirement #4.
FORBIDDEN_GROUPS=("sudo" "admin" "root" "docker" "lxd" "disk" "shadow" "kvm" \
                  "libvirt" "libvirt-qemu" "wheel" "staff" "sudoers")

SSHD_DROPIN="/etc/ssh/sshd_config.d/99-${USERNAME}.conf"
SUDO_DENY_FILE="/etc/sudoers.d/99-deny-${USERNAME}"
PROFILE_SNIPPET="/etc/profile.d/99-${AUDIT_GROUP}.sh"
INSTALL_PATH="/usr/local/sbin/provision-readonly-user.sh"
BOOT_UNIT="/etc/systemd/system/${AUDIT_GROUP}-acls.service"
LOG_FILE="/var/log/provision-readonly-user.log"

# Filesystems that support POSIX ACLs and are worth sweeping.
ACL_FSTYPES='^(ext2|ext3|ext4|xfs|btrfs|jfs|reiserfs|tmpfs)$'

#------------------------------------------------------------------------------
# Runtime flags
#------------------------------------------------------------------------------
MODE="provision"
PASSWORD_SOURCE="prompt"
PASSWORD_VALUE=""
ALLOW_FROM=""
CONFIGURE_SSH=1
INSTALL_BOOT_UNIT=1
DELETE_USER=0
DRY_RUN=0

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------
C_RED=''; C_GRN=''; C_YLW=''; C_OFF=''
if [[ -t 1 ]]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_OFF=$'\033[0m'
fi

log()  { printf '%s  %s\n' "$(date -Is)" "$*"; }
info() { log "[ .. ] $*"; }
ok()   { log "${C_GRN}[ ok ]${C_OFF} $*"; }
warn() { log "${C_YLW}[warn]${C_OFF} $*" >&2; }
die()  { log "${C_RED}[fail]${C_OFF} $*" >&2; exit 1; }

# Wrap every mutating command so --dry-run is honoured consistently.
run() {
    if (( DRY_RUN )); then
        log "[dry ] would run: $*"
        return 0
    fi
    "$@"
}

usage() { sed -n '3,32p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }

require_root() {
    (( EUID == 0 )) || die "must be run as root (try: sudo $0 $*)"
}

#------------------------------------------------------------------------------
# Argument parsing
#------------------------------------------------------------------------------
parse_args() {
    while (( $# )); do
        case "$1" in
            --verify)          MODE="verify" ;;
            --revert)          MODE="revert" ;;
            --acls-only)       MODE="acls" ;;
            --delete-user)     DELETE_USER=1 ;;
            --skip-password)   PASSWORD_SOURCE="skip" ;;
            --password-stdin)  PASSWORD_SOURCE="stdin" ;;
            --allow-from)      [[ ${2:-} ]] || usage; ALLOW_FROM="$2"; shift ;;
            --no-ssh-config)   CONFIGURE_SSH=0 ;;
            --no-boot-unit)    INSTALL_BOOT_UNIT=0 ;;
            --dry-run)         DRY_RUN=1 ;;
            -h|--help)         usage 0 ;;
            *)                 warn "unknown argument: $1"; usage ;;
        esac
        shift
    done
}

#------------------------------------------------------------------------------
# Pre-flight checks
#------------------------------------------------------------------------------
preflight() {
    local id_like="" ver=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        ver="$(. /etc/os-release && printf '%s %s' "${ID:-?}" "${VERSION_ID:-?}")"
        id_like="$(. /etc/os-release && printf '%s' "${ID:-}")"
    fi
    info "detected OS: ${ver:-unknown}"
    [[ $id_like == "ubuntu" ]] || warn "not Ubuntu; group names and paths may differ"

    # POSIX ACLs are the mechanism that makes "read all / write nothing" work.
    if ! command -v setfacl >/dev/null 2>&1; then
        info "acl package missing; installing"
        if (( DRY_RUN )); then
            log "[dry ] would run: apt-get install -y acl"
        else
            DEBIAN_FRONTEND=noninteractive apt-get update -qq \
              && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq acl \
              || die "could not install 'acl'. Install it manually and re-run."
        fi
    fi

    # Verify the root filesystem actually honours ACLs before relying on them.
    if ! (( DRY_RUN )); then
        local probe
        probe="$(mktemp -d)"
        if ! setfacl -m "u:nobody:r-x" "$probe" >/dev/null 2>&1; then
            rmdir "$probe"
            die "filesystem does not support POSIX ACLs (mount with 'acl' option).
       Fallback without ACLs: add ${USERNAME} to the 'ubuntu' group for
       ${LOGIN_DIR} access and set /tmp,/var/tmp,/dev/shm to 1777 -> 0755,
       but be aware that breaks other software."
        fi
        rmdir "$probe"
    fi

    [[ -d $LOGIN_DIR ]] || warn "login directory $LOGIN_DIR does not exist yet"
    [[ -x $LOGIN_SHELL ]] || die "login shell $LOGIN_SHELL not found"
    ok "pre-flight checks passed"
}

#------------------------------------------------------------------------------
# 1. Group and account
#------------------------------------------------------------------------------
ensure_group() {
    if getent group "$AUDIT_GROUP" >/dev/null; then
        ok "group $AUDIT_GROUP already exists"
    else
        run groupadd --system "$AUDIT_GROUP"
        ok "created system group $AUDIT_GROUP"
    fi
}

ensure_user() {
    if id -u "$USERNAME" >/dev/null 2>&1; then
        ok "user $USERNAME already exists; converging settings"
        # Converge without touching any files: no -m, so nothing is moved.
        run usermod --home "$LOGIN_DIR" --shell "$LOGIN_SHELL" \
                    --gid "$AUDIT_GROUP" "$USERNAME"
    else
        # --no-create-home: the account deliberately owns no writable directory.
        run useradd \
            --no-create-home \
            --home-dir "$LOGIN_DIR" \
            --shell "$LOGIN_SHELL" \
            --gid "$AUDIT_GROUP" \
            --comment "read-only audit account (managed by $(basename "$0"))" \
            "$USERNAME"
        ok "created user $USERNAME (primary group $AUDIT_GROUP, no home of its own)"
    fi

    # Grant read-only supplementary groups that exist on this host.
    local g add=()
    for g in "${READ_GROUPS[@]}"; do
        if getent group "$g" >/dev/null; then
            add+=("$g")
        else
            warn "read group '$g' not present on this system; skipping"
        fi
    done
    if (( ${#add[@]} )); then
        local joined
        joined="$(IFS=,; printf '%s' "${add[*]}")"
        run usermod --append --groups "$joined" "$USERNAME"
        ok "supplementary read groups: $joined"
    fi

    # Strip anything that would grant privilege escalation.
    for g in "${FORBIDDEN_GROUPS[@]}"; do
        if getent group "$g" >/dev/null && id -nG "$USERNAME" | tr ' ' '\n' | grep -qx "$g"; then
            run gpasswd --delete "$USERNAME" "$g"
            warn "removed $USERNAME from privileged group '$g'"
        fi
    done

    # Never expire the account, but do not silently unlock a locked password.
    run chage -E -1 -I -1 "$USERNAME"
}

#------------------------------------------------------------------------------
# 2. Password
#------------------------------------------------------------------------------
set_password() {
    case "$PASSWORD_SOURCE" in
        skip)
            info "leaving password unchanged (--skip-password)"
            return 0 ;;
        stdin)
            IFS= read -r PASSWORD_VALUE || die "no password on stdin" ;;
        prompt)
            # On a re-run with an existing usable password, do not clobber it.
            local hash
            hash="$(getent shadow "$USERNAME" | cut -d: -f2 || true)"
            if [[ -n $hash && $hash != '!' && $hash != '*' && $hash != '!!' ]]; then
                ok "password already set; not changing it (use --password-stdin to rotate)"
                return 0
            fi
            if [[ ! -t 0 ]]; then
                warn "no TTY and no --password-stdin: password left unset (account cannot log in)"
                return 0
            fi
            local p1 p2
            read -rsp "Password for ${USERNAME}: " p1; echo
            read -rsp "Confirm: "                p2; echo
            [[ $p1 == "$p2" ]] || die "passwords did not match"
            [[ -n $p1 ]]        || die "empty password refused"
            PASSWORD_VALUE="$p1" ;;
    esac

    if (( DRY_RUN )); then
        log "[dry ] would set password for $USERNAME via chpasswd"
        return 0
    fi
    # printf is a shell builtin, so the secret never appears in `ps` output.
    printf '%s:%s\n' "$USERNAME" "$PASSWORD_VALUE" | chpasswd
    unset PASSWORD_VALUE
    ok "password set for $USERNAME"
}

#------------------------------------------------------------------------------
# 3. Explicit sudo denial + scheduler denial
#------------------------------------------------------------------------------
deny_sudo() {
    local tmp content
    content="# Managed by $(basename "$0") - do not edit.
# Belt and braces: even if ${USERNAME} is somehow added to a sudo group,
# this explicit rule refuses every command.
${USERNAME} ALL=(ALL:ALL) !ALL
"
    if [[ -f $SUDO_DENY_FILE ]] && [[ "$(cat "$SUDO_DENY_FILE")" == "$content" ]]; then
        ok "sudo deny rule already in place"
    else
        if (( DRY_RUN )); then
            log "[dry ] would install $SUDO_DENY_FILE"
        else
            tmp="$(mktemp)"; chmod 0440 "$tmp"; printf '%s' "$content" > "$tmp"
            # Validate BEFORE installing: a broken sudoers file locks everyone out.
            visudo -cqf "$tmp" || { rm -f "$tmp"; die "generated sudoers file failed validation"; }
            install -o root -g root -m 0440 "$tmp" "$SUDO_DENY_FILE"
            rm -f "$tmp"
            ok "installed explicit sudo deny rule: $SUDO_DENY_FILE"
        fi
    fi

    # Warn loudly if some other file grants this account sudo.
    if grep -RIl --exclude="$(basename "$SUDO_DENY_FILE")" -e "^[[:space:]]*${USERNAME}[[:space:]]" \
        /etc/sudoers /etc/sudoers.d 2>/dev/null | grep -q .; then
        warn "another sudoers file mentions $USERNAME - review /etc/sudoers.d manually"
    fi

    # cron/at write into spool directories via setgid helpers, which would let
    # the account create files. Deny-lists preserve the default "all others
    # allowed" behaviour as long as no *.allow file exists.
    local f
    for f in /etc/cron.deny /etc/at.deny; do
        if [[ -f ${f%.deny}.allow ]]; then
            warn "${f%.deny}.allow exists; ensure $USERNAME is not listed there"
            continue
        fi
        if [[ -f $f ]] && grep -qx "$USERNAME" "$f"; then
            ok "$USERNAME already denied in $f"
        else
            run bash -c "printf '%s\n' '$USERNAME' >> '$f'"
            ok "denied $USERNAME in $f"
        fi
    done
}

#------------------------------------------------------------------------------
# 4. The core of the model: ACL-based write denial
#------------------------------------------------------------------------------
# Every ordinary user can write to world-writable directories (/tmp, /var/tmp,
# /dev/shm, /var/crash, /run/lock ...). A named POSIX ACL entry for our group
# takes precedence over the "other" permission bits, so we can revoke write for
# this one group without altering the mode bits that everybody else relies on.
acl_mountpoints() {
    findmnt -rn -o TARGET,FSTYPE 2>/dev/null \
      | awk -v re="$ACL_FSTYPES" '$2 ~ re { print $1 }' \
      | sort -u
}

# Build the find(1) expression: world-writable, plus group-writable by any
# supplementary group this account belongs to (group entries are unioned during
# ACL evaluation, so those could otherwise re-grant write access).
build_find_expr() {
    local -n out=$1
    out=( '(' -perm -0002 )
    local g
    for g in $(id -nG "$USERNAME" 2>/dev/null || true); do
        [[ $g == "$AUDIT_GROUP" ]] && continue
        out+=( -o '(' -group "$g" -perm -0020 ')' )
    done
    out+=( ')' )
}

apply_write_denial_acls() {
    id -u "$USERNAME" >/dev/null 2>&1 || die "user $USERNAME does not exist"

    local -a expr=() mps=()
    build_find_expr expr
    mapfile -t mps < <(acl_mountpoints)
    (( ${#mps[@]} )) || die "could not enumerate ACL-capable mountpoints"

    info "scanning ${#mps[@]} filesystem(s) for writable paths (this takes a moment)"

    local mp p applied=0 failed=0 kind perm
    for mp in "${mps[@]}"; do
        while IFS= read -r -d '' p; do
            if [[ -d $p ]]; then
                kind="dir";  perm="r-x"   # read + traverse, no create/delete
            else
                kind="file"; perm="r--"   # read only, no modify
            fi
            if (( DRY_RUN )); then
                log "[dry ] would set g:${AUDIT_GROUP}:${perm} on ${kind} $p"
                applied=$(( applied + 1 ))
                continue
            fi
            if setfacl -m "g:${AUDIT_GROUP}:${perm}" "$p" 2>/dev/null; then
                applied=$(( applied + 1 ))
            else
                failed=$(( failed + 1 ))
            fi
        done < <(find "$mp" -xdev \( -type d -o -type f \) "${expr[@]}" -print0 2>/dev/null)
    done

    ok "write access revoked for group $AUDIT_GROUP on $applied path(s)"
    (( failed == 0 )) || warn "$failed path(s) rejected the ACL (read-only or unsupported fs)"

    # Report permissive sockets/devices: ACLs on directories do not cover these,
    # and a writable service socket can be a full privilege escalation.
    local sock risky=()
    while IFS= read -r -d '' sock; do risky+=("$sock"); done \
        < <(find /run /var/run /tmp -xdev \( -type s -o -type c \) -perm -0002 -print0 2>/dev/null)
    if (( ${#risky[@]} )); then
        warn "world-writable sockets/devices found; review these separately:"
        printf '         %s\n' "${risky[@]}" >&2
    fi
}

grant_login_dir_access() {
    [[ -d $LOGIN_DIR ]] || { warn "skipping ACL on missing $LOGIN_DIR"; return 0; }
    # /home/ubuntu is 0750 ubuntu:ubuntu on the EC2 image, so an explicit grant
    # is required. r-x = enter + list, never write. Applied AFTER the sweep.
    run setfacl -m "g:${AUDIT_GROUP}:r-x" "$LOGIN_DIR"
    ok "granted read+traverse on $LOGIN_DIR (mode bits unchanged)"

    # Parent directories must be traversable too.
    local parent="$LOGIN_DIR"
    while parent="$(dirname "$parent")"; [[ $parent != "/" ]]; do
        if ! runuser -u "$USERNAME" -- test -x "$parent" 2>/dev/null; then
            run setfacl -m "g:${AUDIT_GROUP}:--x" "$parent"
            ok "granted traverse on $parent"
        fi
    done
}

#------------------------------------------------------------------------------
# 5. Shell environment for the account
#------------------------------------------------------------------------------
install_profile_snippet() {
    local content
    content='# Managed by provision-readonly-user.sh - do not edit.
# Members of the read-only audit group have no writable HOME, so point history
# and temp files at harmless locations to avoid noisy "Permission denied".
case " $(id -nG 2>/dev/null) " in
    *" '"$AUDIT_GROUP"' "*)
        HISTFILE=/dev/null
        export HISTFILE
        PS1="[read-only] \u@\h:\w\$ "
        ;;
esac
'
    if [[ -f $PROFILE_SNIPPET ]] && [[ "$(cat "$PROFILE_SNIPPET")" == "$content" ]]; then
        ok "profile snippet already current"
        return 0
    fi
    if (( DRY_RUN )); then
        log "[dry ] would install $PROFILE_SNIPPET"; return 0
    fi
    printf '%s' "$content" > "$PROFILE_SNIPPET"
    chmod 0644 "$PROFILE_SNIPPET"
    ok "installed $PROFILE_SNIPPET"
}

#------------------------------------------------------------------------------
# 6. SSH: per-user password auth without weakening the global policy
#------------------------------------------------------------------------------
configure_ssh() {
    (( CONFIGURE_SSH )) || { info "skipping sshd configuration (--no-ssh-config)"; return 0; }

    local main=/etc/ssh/sshd_config
    if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$main"; then
        warn "sshd_config has no Include for /etc/ssh/sshd_config.d/*.conf."
        warn "Add this as the FIRST line of $main or the drop-in will be ignored:"
        warn "    Include /etc/ssh/sshd_config.d/*.conf"
    fi

    local match_line="Match User ${USERNAME}"
    [[ -n $ALLOW_FROM ]] && match_line="Match User ${USERNAME} Address ${ALLOW_FROM}"

    local content
    content="# Managed by $(basename "$0") - do not edit.
# The EC2 Ubuntu image ships PasswordAuthentication=no (60-cloudimg-settings.conf).
# A Match block re-enables it for THIS ACCOUNT ONLY; the global policy is
# untouched. Keep this the highest-numbered drop-in: directives in files that
# sort after it would fall inside this Match block.
${match_line}
    PasswordAuthentication yes
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes
    PermitTTY yes
    AllowAgentForwarding no
    AllowTcpForwarding no
    PermitTunnel no
    X11Forwarding no
    PermitOpen none
"
    if [[ -f $SSHD_DROPIN ]] && [[ "$(cat "$SSHD_DROPIN")" == "$content" ]]; then
        ok "sshd drop-in already current; no reload needed"
        return 0
    fi
    if (( DRY_RUN )); then
        log "[dry ] would install $SSHD_DROPIN and reload sshd"; return 0
    fi

    install -d -m 0755 /etc/ssh/sshd_config.d
    local tmp; tmp="$(mktemp)"
    printf '%s' "$content" > "$tmp"

    # Validate the whole resulting configuration before touching the live one.
    local backup=""
    [[ -f $SSHD_DROPIN ]] && { backup="${SSHD_DROPIN}.bak.$(date +%s)"; cp -a "$SSHD_DROPIN" "$backup"; }
    install -o root -g root -m 0644 "$tmp" "$SSHD_DROPIN"
    rm -f "$tmp"

    if ! sshd -t 2>/tmp/sshd_test.$$; then
        warn "sshd rejected the new configuration:"; cat /tmp/sshd_test.$$ >&2
        rm -f /tmp/sshd_test.$$
        if [[ -n $backup ]]; then mv -f "$backup" "$SSHD_DROPIN"; else rm -f "$SSHD_DROPIN"; fi
        die "sshd configuration reverted; nothing was reloaded"
    fi
    rm -f /tmp/sshd_test.$$ "${backup:-/nonexistent}" 2>/dev/null || true

    # reload, not restart: existing sessions stay alive.
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null \
        || warn "could not reload sshd; run 'systemctl reload ssh' manually"
    ok "installed $SSHD_DROPIN and reloaded sshd"
}

#------------------------------------------------------------------------------
# 7. Re-apply ACLs at boot (tmpfs mounts lose them)
#------------------------------------------------------------------------------
install_boot_unit() {
    (( INSTALL_BOOT_UNIT )) || { info "skipping boot unit (--no-boot-unit)"; return 0; }

    if (( DRY_RUN )); then
        log "[dry ] would install $INSTALL_PATH and $BOOT_UNIT"; return 0
    fi

    local self; self="$(readlink -f "$0")"
    if [[ $self != "$INSTALL_PATH" ]]; then
        install -o root -g root -m 0700 "$self" "$INSTALL_PATH"
    fi

    local content="[Unit]
Description=Re-apply read-only ACLs for ${AUDIT_GROUP}
Documentation=man:acl(5)
After=local-fs.target tmp.mount
Wants=local-fs.target

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH} --acls-only
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"
    if [[ -f $BOOT_UNIT ]] && [[ "$(cat "$BOOT_UNIT")" == "$content" ]]; then
        ok "boot unit already current"
    else
        printf '%s' "$content" > "$BOOT_UNIT"
        chmod 0644 "$BOOT_UNIT"
        systemctl daemon-reload
        ok "installed $BOOT_UNIT"
    fi
    systemctl enable "$(basename "$BOOT_UNIT")" >/dev/null 2>&1 \
        && ok "enabled $(basename "$BOOT_UNIT")" \
        || warn "could not enable boot unit"
}

#------------------------------------------------------------------------------
# 8. Acceptance tests
#------------------------------------------------------------------------------
PASS_N=0; FAIL_N=0
as_user() { runuser -u "$USERNAME" -- "$@" >/dev/null 2>&1; }

check() {  # check <description> <expect: pass|fail> <cmd...>
    local desc="$1" expect="$2"; shift 2
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if { [[ $expect == pass ]] && (( rc == 0 )); } \
    || { [[ $expect == fail ]] && (( rc != 0 )); }; then
        printf '  %s[PASS]%s %s\n' "$C_GRN" "$C_OFF" "$desc"; PASS_N=$(( PASS_N + 1 ))
    else
        printf '  %s[FAIL]%s %s (rc=%s, expected to %s)\n' \
               "$C_RED" "$C_OFF" "$desc" "$rc" "$expect"; FAIL_N=$(( FAIL_N + 1 ))
    fi
}

verify() {
    id -u "$USERNAME" >/dev/null 2>&1 || die "user $USERNAME does not exist"
    command -v runuser >/dev/null || die "runuser not available"

    echo; echo "=== Acceptance tests for $USERNAME ==="

    echo "-- reading --"
    check "read /etc/passwd"                pass as_user cat /etc/passwd
    check "read /etc/ssh/sshd_config"       pass as_user cat /etc/ssh/sshd_config
    check "list /etc"                       pass as_user ls /etc
    check "enter and list $LOGIN_DIR"       pass as_user bash -c "cd '$LOGIN_DIR' && ls -a"
    check "read logs via adm group"         pass as_user bash -c 'ls /var/log/syslog /var/log/*.log'

    echo "-- writing (all of these must fail) --"
    check "create file in $LOGIN_DIR"       fail as_user touch "$LOGIN_DIR/.rw_probe"
    check "create file in /tmp"             fail as_user touch /tmp/.rw_probe
    check "create file in /var/tmp"         fail as_user touch /var/tmp/.rw_probe
    check "create file in /dev/shm"         fail as_user touch /dev/shm/.rw_probe
    check "mkdir in /tmp"                   fail as_user mkdir /tmp/.rw_probe_dir
    check "mkdir in $LOGIN_DIR"             fail as_user mkdir "$LOGIN_DIR/.rw_probe_dir"
    check "shell redirection into /tmp"     fail as_user bash -c 'echo x > /tmp/.rw_probe2'

    # Modify + delete tests against a genuinely world-writable file.
    local probe=/tmp/.readonly_probe_file
    printf 'original\n' > "$probe"; chmod 0666 "$probe"
    check "append to world-writable file"   fail as_user bash -c "echo tampered >> '$probe'"
    check "truncate world-writable file"    fail as_user bash -c ": > '$probe'"
    check "delete file owned by root"       fail as_user rm -f "$probe"
    check "chmod file owned by root"        fail as_user chmod 0777 "$probe"
    if [[ "$(cat "$probe")" == "original" ]]; then
        printf '  %s[PASS]%s probe file contents unchanged\n' "$C_GRN" "$C_OFF"; PASS_N=$(( PASS_N + 1 ))
    else
        printf '  %s[FAIL]%s probe file was modified!\n' "$C_RED" "$C_OFF"; FAIL_N=$(( FAIL_N + 1 ))
    fi
    rm -f "$probe"

    echo "-- privileges --"
    check "sudo -n true refused"            fail as_user sudo -n true
    check "sudo -ln lists nothing"          fail as_user sudo -ln
    check "cannot read /etc/shadow"         fail as_user cat /etc/shadow
    check "not in any privileged group"     fail bash -c \
        "id -nG '$USERNAME' | tr ' ' '\n' | grep -qxE '$(IFS='|'; printf '%s' "${FORBIDDEN_GROUPS[*]}")'"
    check "crontab denied"                  fail as_user crontab -l

    echo "-- ssh --"
    if command -v sshd >/dev/null; then
        check "password auth enabled for user" pass bash -c \
            "sshd -T -C user='$USERNAME',host=localhost,addr=127.0.0.1 2>/dev/null \
             | grep -qx 'passwordauthentication yes'"
        check "sshd config valid"              pass sshd -t
    fi

    echo
    printf 'Result: %s%d passed%s, %s%d failed%s\n' \
        "$C_GRN" "$PASS_N" "$C_OFF" "$([[ $FAIL_N -gt 0 ]] && echo "$C_RED" || echo "$C_GRN")" \
        "$FAIL_N" "$C_OFF"
    (( FAIL_N == 0 )) || return 3
}

#------------------------------------------------------------------------------
# 9. Revert
#------------------------------------------------------------------------------
revert() {
    info "removing ACL entries for group $AUDIT_GROUP"
    local mp p removed=0
    local -a expr=() acl_pred=()
    build_find_expr expr
    # Prefer find's -acl predicate (catches every entry we ever set); fall back
    # to the same expression used when applying if this findutils lacks it.
    if find / -maxdepth 0 -acl >/dev/null 2>&1; then acl_pred=( -acl ); fi
    while IFS= read -r mp; do
        while IFS= read -r -d '' p; do
            setfacl -x "g:${AUDIT_GROUP}" "$p" 2>/dev/null && removed=$(( removed + 1 )) || true
        done < <(find "$mp" -xdev \( -type d -o -type f \) \
                      "${acl_pred[@]:-${expr[@]}}" -print0 2>/dev/null)
    done < <(acl_mountpoints)
    [[ -d $LOGIN_DIR ]] && setfacl -x "g:${AUDIT_GROUP}" "$LOGIN_DIR" 2>/dev/null \
        && removed=$(( removed + 1 ))
    ok "removed $removed ACL entries"

    local f
    for f in "$SSHD_DROPIN" "$SUDO_DENY_FILE" "$PROFILE_SNIPPET"; do
        [[ -f $f ]] && { rm -f "$f"; ok "removed $f"; }
    done
    if [[ -f $BOOT_UNIT ]]; then
        systemctl disable "$(basename "$BOOT_UNIT")" >/dev/null 2>&1 || true
        rm -f "$BOOT_UNIT"; systemctl daemon-reload; ok "removed $BOOT_UNIT"
    fi
    for f in /etc/cron.deny /etc/at.deny; do
        [[ -f $f ]] && sed -i "/^${USERNAME}$/d" "$f" && ok "un-denied $USERNAME in $f"
    done
    sshd -t && { systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true; }

    if (( DELETE_USER )); then
        # No -r: the account never owned /home/ubuntu and must not delete it.
        userdel "$USERNAME" && ok "deleted user $USERNAME (login dir left intact)"
        getent group "$AUDIT_GROUP" >/dev/null && groupdel "$AUDIT_GROUP" && ok "deleted group $AUDIT_GROUP"
    else
        info "account $USERNAME left in place (pass --delete-user to remove it)"
    fi
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
main() {
    parse_args "$@"
    require_root "$@"

    # Append a copy of all output to the log without hiding it from the console.
    if [[ ! -t 1 || -w $(dirname "$LOG_FILE") ]] && (( ! DRY_RUN )); then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    case "$MODE" in
        verify) verify; return $? ;;
        revert) revert; return 0 ;;
        acls)   apply_write_denial_acls; grant_login_dir_access; return 0 ;;
    esac

    log "=== provisioning read-only account '$USERNAME' ==="
    (( DRY_RUN )) && warn "DRY RUN: no changes will be made"

    preflight
    ensure_group
    ensure_user
    set_password
    deny_sudo
    apply_write_denial_acls
    grant_login_dir_access
    install_profile_snippet
    configure_ssh
    install_boot_unit

    echo
    ok "done. Account summary:"
    id "$USERNAME" 2>/dev/null || true
    getent passwd "$USERNAME" 2>/dev/null || true
    echo
    log "Test the login:   ssh ${USERNAME}@<server-ip>"
    log "Run the tests:    sudo $0 --verify"
    log "Undo everything:  sudo $0 --revert [--delete-user]"
}

main "$@"
