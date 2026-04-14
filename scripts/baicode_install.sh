#!/usr/bin/env sh
# BAI code cross-platform installer for macOS and Linux
# Requirements: curl or wget, Python 3.10+
#
# Usage:
#   sh install.sh            # interactive (prompts about venv)
#   sh install.sh --no-venv  # skip venv prompt, install to current environment
#   BAI_NO_VENV=1 sh install.sh  # same effect via environment variable

MANIFEST_URL="https://download.bankofai.io/download/baicode_release_whls.txt"
VENV_DIR=".venv"

# ── helpers ────────────────────────────────────────────────────────────────

die() {
    printf "Error: %s\n" "$1" >&2
    exit 1
}

info() {
    printf "==> %s\n" "$1"
}

# ── argument parsing ────────────────────────────────────────────────────────

NO_VENV=0
for _arg in "$@"; do
    case "$_arg" in --no-venv) NO_VENV=1 ;; esac
done
[ "${BAI_NO_VENV:-}" = "1" ] && NO_VENV=1

# ── fetch manifest ──────────────────────────────────────────────────────────
# Note: fetch_manifest writes content to stdout and returns exit code.
# Caller must use: MANIFEST=$(fetch_manifest) || die "..."
# (exit inside $() only exits the subshell, not the parent script)

fetch_manifest() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 30 "$MANIFEST_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=30 "$MANIFEST_URL"
    else
        printf "Error: Neither curl nor wget found. Please install curl or wget.\n" >&2
        return 1
    fi
}

# ── platform detection ──────────────────────────────────────────────────────

detect_platform() {
    _os=$(uname -s)
    _arch=$(uname -m)
    case "$_os" in
        Darwin)
            BAI_OS="macosx"
            case "$_arch" in
                x86_64) BAI_ARCH="x86_64" ;;
                arm64)  BAI_ARCH="arm64"  ;;
                *) die "Unsupported macOS architecture: $_arch" ;;
            esac ;;
        Linux)
            BAI_OS="linux"
            case "$_arch" in
                x86_64) BAI_ARCH="x86_64" ;;
                *) die "Unsupported Linux architecture: $_arch (only x86_64 is supported)" ;;
            esac ;;
        *) die "Unsupported operating system: $_os (supported: macOS, Linux)" ;;
    esac
}

# ── python detection ────────────────────────────────────────────────────────

detect_python() {
    PYTHON_CMD=""
    for _cmd in python3 python; do
        if ! command -v "$_cmd" >/dev/null 2>&1; then continue; fi
        _ver=$("$_cmd" -c \
            "import sys; v=sys.version_info; print(str(v.major)+'.'+str(v.minor))" \
            2>/dev/null) || continue
        _maj=$(printf "%s" "$_ver" | cut -d. -f1)
        _min=$(printf "%s" "$_ver" | cut -d. -f2)
        if [ "$_maj" -gt 3 ] || { [ "$_maj" -eq 3 ] && [ "$_min" -ge 10 ]; }; then
            PYTHON_CMD="$_cmd"
            PYTHON_VER="$_ver"
            PYTHON_TAG="cp${_maj}${_min}"
            return 0
        fi
    done
    die "Python 3.10+ is required but not found.
Please install from: https://www.python.org/downloads/"
}

# ── wheel matching ──────────────────────────────────────────────────────────
# Helper: run awk match for a given python tag against manifest content.
# Args: $1=content  $2=ptag
# Prints two lines (URL then HASH) on match; single line "NOMATCH" on no match.

_match_awk() {
    printf "%s\n" "$1" | awk \
        -v ptag="$2" \
        -v bai_os="$BAI_OS" \
        -v bai_arch="$BAI_ARCH" \
    'BEGIN { in_s=0; has_h=0; done=0; sc=0; nc=0; mc=0 }
     done  { next }
     /^\[v[^]]*\]/ {
         has_h=1
         if (in_s) { done=1 } else { in_s=1 }
         next
     }
     /^[[:space:]]*$/ { next }
     /^#/             { next }
     {
         n = split($0, parts, /[[:space:]]*\|[[:space:]]*/);
         url = parts[1]
         gsub(/[[:space:]]+$/, "", url)
         if (in_s)        { sa_url[++sc]=url }
         else if (!has_h) { na_url[++nc]=url }
     }
     END {
         n = (has_h ? sc : nc)
         for (i=1; i<=n; i++) {
             url = (has_h ? sa_url[i] : na_url[i])
             split(url, p, "/"); fname=p[length(p)]
             if (index(fname, "-" ptag "-") == 0) continue
             if (index(fname, bai_os)       == 0) continue
             if (index(fname, bai_arch)     == 0) continue
             mc++
             if (mc==1) { mu=url }
             if (mc==2) { print "Warning: multiple matching wheels found, using first." > "/dev/stderr" }
         }
         if (mc==0) { print "NOMATCH"; exit 0 }
         print mu
     }'
}

# Parses manifest content, finds the first [vX.Y.Z] segment (or whole file if
# no headers), and matches a wheel for the current platform + python tag.
# Sets WHEEL_URL on success; exits with error on no match.

match_wheel() {
    _content="$1"

    WHEEL_URL=$(_match_awk "$_content" "$PYTHON_TAG") || true

    if [ "$WHEEL_URL" = "NOMATCH" ] || [ -z "$WHEEL_URL" ]; then
        printf "Error: No matching wheel found.\n" >&2
        printf "  Python:   %s  (tag: %s)\n" "$PYTHON_VER" "$PYTHON_TAG" >&2
        printf "  Platform: %s/%s\n" "$BAI_OS" "$BAI_ARCH" >&2
        printf "  Available wheels in manifest:\n" >&2
        printf "%s\n" "$_content" | awk \
        'BEGIN { in_s=0; has_h=0; done=0 }
         done { next }
         /^\[v[^]]*\]/ { has_h=1; if (in_s){done=1}else{in_s=1}; next }
         /^[[:space:]]*$/ { next }
         /^#/ { next }
         (in_s || !has_h) {
             n=split($0, p, /[[:space:]]*\|[[:space:]]*/); url=p[1]
             split(url, q, "/"); print "    " q[length(q)]
         }
        ' >&2
        exit 1
    fi
}

# ── venv setup ──────────────────────────────────────────────────────────────

VENV_ACTIVE=0

setup_venv() {
    if [ "$NO_VENV" = "1" ]; then return; fi
    printf "Create a virtual environment at %s? [y/N] " "$VENV_DIR"
    read -r _ans
    case "${_ans:-n}" in
        y|Y|yes|YES|Yes)
            info "Creating virtual environment at $VENV_DIR ..."
            "$PYTHON_CMD" -m venv --upgrade-deps "$VENV_DIR" \
                || die "Failed to create virtual environment."
            VENV_ACTIVE=1
            info "Virtual environment created."
            ;;
    esac
}

# ── install ─────────────────────────────────────────────────────────────────

install_baicode() {
    _fname=$(basename "$WHEEL_URL")
    info "Installing: $_fname"
    if [ "$VENV_ACTIVE" = "1" ]; then
        "$VENV_DIR/bin/python" -m pip install "$WHEEL_URL" \
            || die "Installation failed."
        printf "\nBAI code installed into %s\n" "$VENV_DIR"
        printf "🚀 To activate in future sessions:\n"
        printf "     source %s/bin/activate\n" "$VENV_DIR"
    else
        "$PYTHON_CMD" -m pip install "$WHEEL_URL" \
            || die "Installation failed. Ensure pip is available:
  $PYTHON_CMD -m ensurepip --upgrade"
        printf "\nInstalled successfully.\n"
    fi
    printf "\n"
    printf "==============================================\n"
    printf "  Next steps:\n"
    printf "\n"
    printf "  🚀 Set your API key:\n"
    printf "       export BAI_API_KEY=sk-...\n"
    printf "\n"
    printf "  ✨ Try BAI code at once:\n"
    printf "       baicode\n"
    printf "==============================================\n"
}

# ── main ────────────────────────────────────────────────────────────────────

info "Fetching package manifest..."
MANIFEST=$(fetch_manifest) \
    || die "Failed to download manifest from: $MANIFEST_URL
Please check your network connection."

detect_platform
detect_python
info "Python $PYTHON_VER ($PYTHON_TAG) | $BAI_OS/$BAI_ARCH"

match_wheel "$MANIFEST"
info "Matched: $(basename "$WHEEL_URL")"

setup_venv
install_baicode
