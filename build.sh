#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

detect_arch() {
    local uname_arch
    uname_arch="$(uname -m)"
    case "$uname_arch" in
        arm64|aarch64) echo "arm64" ;;
        x86_64|amd64)  echo "amd64" ;;
        *)             echo "unknown" ;;
    esac
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux)  echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)      echo "unknown" ;;
    esac
}

check_prereqs() {
    local missing=0
    for cmd in go node npm task; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done
    if [[ "$missing" -eq 1 ]]; then
        log_error "Please install missing dependencies before continuing."
        exit 1
    fi
}

verify_binaries() {
    local os="$1"
    local arch="$2"
    local errors=0

    local wavesrv_name
    case "$os" in
        darwin|linux)
            if [[ "$arch" == "amd64" ]]; then
                wavesrv_name="dist/bin/wavesrv.x64"
            else
                wavesrv_name="dist/bin/wavesrv.${arch}"
            fi
            ;;
        windows)
            if [[ "$arch" == "amd64" ]]; then
                wavesrv_name="dist/bin/wavesrv.x64.exe"
            else
                wavesrv_name="dist/bin/wavesrv.${arch}.exe"
            fi
            ;;
    esac

    if [[ ! -f "$wavesrv_name" ]]; then
        log_error "Missing wavesrv binary: $wavesrv_name"
        errors=1
    else
        if [[ "$os" != "windows" ]]; then
            if [[ ! -x "$wavesrv_name" ]]; then
                log_warn "wavesrv binary exists but is not executable: $wavesrv_name (fixing)"
                chmod +x "$wavesrv_name"
            fi
        fi
        log_info "Found wavesrv: $wavesrv_name"
    fi

    local wsh_count
    wsh_count=$(find dist/bin -name 'wsh-*' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$wsh_count" -eq 0 ]]; then
        log_error "No wsh binaries found in dist/bin/"
        errors=1
    else
        log_info "Found $wsh_count wsh binaries in dist/bin/"
    fi

    if [[ ! -d "dist/tsunamiscaffold" ]]; then
        log_error "Missing dist/tsunamiscaffold/"
        errors=1
    else
        log_info "Found dist/tsunamiscaffold/"
    fi

    if [[ "$errors" -eq 1 ]]; then
        log_error "Binary verification failed. Rebuilding backend..."
        return 1
    fi

    return 0
}

do_full_build() {
    log_info "Starting full build (task package)..."
    task package
}

do_backend_build() {
    local os="$1"
    local arch="$2"

    log_info "Building backend for $os/$arch..."

    case "$os" in
        darwin)
            if [[ "$arch" == "arm64" ]]; then
                task build:server:quickdev
            else
                task build:server:macos
            fi
            ;;
        linux)
            task build:server:linux
            ;;
        windows)
            task build:server:windows
            ;;
    esac

    task build:wsh
    task build:tsunamiscaffold
}

do_package_only() {
    log_info "Packaging (without rebuilding backend)..."
    npm run build:prod && npm exec electron-builder -- -c electron-builder.config.cjs -p never
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND]

Build script for Wave Terminal. Ensures all required binaries are present
before packaging to prevent the missing-wavesrv startup failure.

Commands:
  full        Full clean build + package (default)
  quick       Build backend for current arch only, then package
  package     Skip backend build, just run frontend build + electron-builder
  verify      Only verify that required binaries exist
  dev         Quick dev build (wavesrv arm64 only, no wsh, no generate)

Environment:
  WAVETERM_SKIP_VERIFY=1   Skip binary verification before packaging
EOF
}

COMMAND="${1:-full}"
OS="$(detect_os)"
ARCH="$(detect_arch)"

log_info "Detected OS: $OS, Arch: $ARCH"

case "$COMMAND" in
    full)
        check_prereqs
        do_full_build
        ;;
    quick)
        check_prereqs
        do_backend_build "$OS" "$ARCH"
        if [[ "${WAVETERM_SKIP_VERIFY:-}" != "1" ]]; then
            if ! verify_binaries "$OS" "$ARCH"; then
                log_error "Backend build did not produce expected binaries."
                exit 1
            fi
        fi
        do_package_only
        ;;
    package)
        check_prereqs
        if [[ "${WAVETERM_SKIP_VERIFY:-}" != "1" ]]; then
            if ! verify_binaries "$OS" "$ARCH"; then
                log_error "Missing binaries. Run '$(basename "$0") quick' or '$(basename "$0") full' first."
                exit 1
            fi
        fi
        do_package_only
        ;;
    verify)
        check_prereqs
        if verify_binaries "$OS" "$ARCH"; then
            log_info "All required binaries are present and valid."
        else
            log_error "Binary verification failed."
            exit 1
        fi
        ;;
    dev)
        check_prereqs
        log_info "Starting quick dev build..."
        task electron:quickdev
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
