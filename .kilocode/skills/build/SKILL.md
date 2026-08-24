---
name: build
description: Guide for building and packaging Wave Terminal. Use when compiling the project, building backend binaries (wavesrv, wsh), packaging the Electron app, diagnosing missing-binary startup failures, or running any build-related task.
---

# Building Wave Terminal

## Prerequisites

- **Go** (with CGO support — `CGO_ENABLED=1` is required for wavesrv)
- **Node.js** + **npm**
- **task** (Taskfile runner — `go install github.com/go-task/task/v3/cmd/task@latest`)
- **zig** (required for Linux/Windows cross-compilation via `CC="zig cc -target ..."`)

Verify all are installed:

```bash
go version && node --version && task --version
```

## Build Commands

### Using `build.sh` (Recommended)

A build script at the project root provides safeguards against missing binaries:

```bash
./build.sh full      # Full clean build + package (default)
./build.sh quick     # Build backend for current arch only, then package
./build.sh package   # Skip backend, just frontend build + electron-builder
./build.sh verify    # Only check that required binaries exist
./build.sh dev       # Quick dev mode (wavesrv arm64 only)
```

The script **automatically verifies** that `dist/bin/wavesrv.{arch}` and `dist/bin/wsh-*` exist and are executable before packaging. This prevents the most common build failure: a packaged app that won't start because wavesrv is missing.

### Using `task` Directly

| Task | Description |
|------|-------------|
| `task package` | Full clean build + electron-builder packaging |
| `task build:backend` | Build wavesrv + wsh for all targets |
| `task build:server:macos` | Build wavesrv for arm64+amd64 on Darwin |
| `task build:server:quickdev` | Build wavesrv arm64 only (no generate, no wsh) |
| `task build:wsh` | Build wsh for all OS/arch targets |
| `task build:tsunamiscaffold` | Build tsunami scaffold to dist |
| `task electron:dev` | Run dev server with hot reload |
| `task electron:quickdev` | Quick dev (arm64 only, no wsh) |
| `task generate` | Regenerate TypeScript/Go bindings from wshrpctypes.go |
| `task clean` | Remove `make/` and `dist/` |

## Build Output

Packaged applications are written to `make/`:

- macOS: `Wave-darwin-arm64-{version}.dmg`, `Wave-darwin-x64-{version}.dmg`
- Linux: `.deb`, `.rpm`, `.AppImage`, `.snap`, `.zip`
- Windows: `.exe` (NSIS), `.msi`, `.zip`

## Binary Naming Convention

The wavesrv binary is named with the architecture suffix:

| Architecture | Binary Name |
|-------------|-------------|
| arm64 | `dist/bin/wavesrv.arm64` |
| amd64 | `dist/bin/wavesrv.x64` |
| arm64 (Windows) | `dist/bin/wavesrv.arm64.exe` |
| amd64 (Windows) | `dist/bin/wavesrv.x64.exe` |

The Electron app (`emain/emain-platform.ts:168`) resolves the binary at runtime via:

```typescript
wavesrvBinName = `wavesrv.${unameArch}`
```

Where `unameArch` maps: `arm64` → `arm64`, `x64` → `x64`.

The wsh binaries follow the pattern: `wsh-{version}-{os}.{arch}` (e.g., `wsh-0.14.5-darwin.arm64`).

## Critical Path: What Must Exist Before Packaging

electron-builder (`electron-builder.config.cjs`) only includes files matching these filters from `dist/bin/`:

```
"bin/wavesrv.${arch}*", "bin/wsh*"
```

If **wavesrv.{arch}** is missing from `dist/bin/` before packaging, the app will build successfully but **crash on launch** with:

```
spawn .../wavesrv.arm64 ENOENT
```

The `build.sh verify` command catches this. Always run verify or use `build.sh quick` instead of raw `task package`.

## Common Build Failures and Fixes

### 1. App Won't Start (ENOENT on wavesrv)

**Symptom**: Installed Wave app shows no window. `waveapp.log` shows `spawn .../wavesrv.arm64 ENOENT`.

**Cause**: `dist/bin/wavesrv.arm64` was missing when `task package` was run.

**Fix**: Build the server first, then repackage:

```bash
task build:server:quickdev   # or task build:server:macos
task package
```

Or use the safe script:

```bash
./build.sh quick
```

### 2. CGO Compilation Errors

**Symptom**: `CGO_ENABLED=1` build fails with C compiler errors.

**Cause**: Missing C toolchain (Xcode Command Line Tools on macOS, build-essential on Linux).

**Fix (macOS)**:

```bash
xcode-select --install
```

**Fix (Linux)**:

```bash
sudo apt install build-essential
```

### 3. Zig Not Found (Cross-Compilation)

**Symptom**: Linux/Windows server build fails with `CC="zig cc -target ..."` error.

**Cause**: `zig` is not installed or not in PATH.

**Fix**: Install zig from https://ziglang.org/ or skip cross-compilation by building only for your platform:

```bash
task build:server:quickdev   # macOS arm64 only, no zig needed
```

### 4. Task Not Found

**Symptom**: `task: command not found`

**Fix**:

```bash
go install github.com/go-task/task/v3/cmd/task@latest
```

### 5. npm install Failures

**Symptom**: `npm install` errors during `task package`.

**Fix**: Clean and retry:

```bash
rm -rf node_modules package-lock.json
npm install
```

### 6. Generated Code Out of Sync

**Symptom**: TypeScript type errors or Go compilation errors after modifying `pkg/wshrpc/wshrpctypes.go`.

**Fix**:

```bash
task generate
```

This regenerates:
- `frontend/types/gotypes.d.ts` — TypeScript type definitions
- `frontend/app/store/wshclientapi.ts` — RPC client bindings
- `pkg/wshrpc/wshroutes.go` — Go routing code

## Build Flow Diagram

```
task package
├── clean              → rm -rf make/ dist/
├── npm:install        → npm install
├── build:backend
│   ├── go:mod:tidy    → go mod tidy
│   ├── generate       → generate TS/Go bindings
│   ├── build:server   → wavesrv.{arch} (all platforms)
│   │   ├── build:server:macos    → arm64 + amd64
│   │   ├── build:server:linux    → current arch
│   │   └── build:server:windows  → current arch
│   └── build:wsh      → wsh-{ver}-{os}.{arch} (all targets)
├── build:tsunamiscaffold
└── electron-builder   → make/Wave-{platform}-{arch}-{version}.dmg/zip/...
```

## Quick Reference: Dev Workflow

For day-to-day development, you typically only need:

```bash
# Start coding with hot reload
./build.sh dev

# After changing Go backend code, rebuild wavesrv and restart
task build:server:quickdev

# After changing wshrpctypes.go, regenerate bindings
task generate

# Ready to test a packaged build
./build.sh quick
```

## App Data Locations (for debugging installed builds)

| Platform | Path |
|----------|------|
| macOS data | `~/Library/Application Support/waveterm/` |
| macOS logs | `~/Library/Application Support/waveterm/waveapp.log` |
| macOS config | `~/.config/waveterm/` |
| Linux data | `~/.local/share/waveterm/` |
| Windows data | `%LOCALAPPDATA%\waveterm\Data\` |
