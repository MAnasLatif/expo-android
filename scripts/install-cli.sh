#!/usr/bin/env bash
# =============================================================================
# Install the `expoemu` command globally, so `expoemu up` works without npx.
#
#   scripts/install-cli.sh             install this version (skipped if present)
#   scripts/install-cli.sh --latest    install/upgrade to the latest release
#   scripts/install-cli.sh --remove    uninstall the command (data is kept)
#
# Uses the package manager that launched expoemu: npm (npx) by default, Bun
# when run through bunx. Never uses sudo. EXPOEMU_INSTALL_SPEC overrides what
# is installed (e.g. a local tarball, for testing).
# =============================================================================
source "$(dirname "$0")/lib/common.sh"

MODE=install
case "${1:-}" in
  --latest) MODE=latest ;;
  --remove) MODE=remove ;;
  "") ;;
  -h|--help) sed -n '2,/^# =====*$/p' "$0"; exit 0 ;;
  *) die "Unknown option: $1" ;;
esac

VERSION="$(node -p "require('$REPO_ROOT/package.json').version")"

# --- Which package manager? (bunx sets npm_config_user_agent to "bun/…") -----
if [[ "${npm_config_user_agent:-}" == bun/* ]] && command -v bun >/dev/null; then
  PM=bun
  BIN_DIR="${BUN_INSTALL:-$HOME/.bun}/bin"
else
  command -v npm >/dev/null || die "npm not found — install Node.js 18+ first"
  PM=npm
  BIN_DIR="$(npm prefix -g)/bin"
fi
GLOBAL_BIN="$BIN_DIR/expoemu"

# The real global command, not npx's temporary copy that is on PATH right now.
installed_version() { [ -x "$GLOBAL_BIN" ] && "$GLOBAL_BIN" --version 2>/dev/null || true; }

# --- Remove ----------------------------------------------------------------------
if [ "$MODE" = remove ]; then
  if [ ! -e "$GLOBAL_BIN" ]; then ok "The expoemu command is not installed globally"; exit 0; fi
  if [ "$PM" = bun ]; then bun remove -g expoemu >/dev/null; else npm uninstall -g expoemu --no-audit --no-fund >/dev/null; fi
  ok "Removed the global expoemu command (SDK, devices and settings in ~/.expoemu are kept)"
  exit 0
fi

# --- Install / update -----------------------------------------------------------------
# A git clone is a development checkout: link it instead of installing a release.
if [ -d "$REPO_ROOT/.git" ] && [ -z "${EXPOEMU_INSTALL_SPEC:-}" ]; then
  warn "Running from a git clone — to use this checkout as 'expoemu', run: (cd $REPO_ROOT && npm link)"
  exit 0
fi

current="$(installed_version)"
if [ "$MODE" = install ] && [ -n "$current" ]; then
  ok "expoemu $current is already installed globally — use 'expoemu …' directly"
  exit 0
fi

if [ "$MODE" = latest ]; then spec="expoemu@latest"; else spec="expoemu@$VERSION"; fi
spec="${EXPOEMU_INSTALL_SPEC:-$spec}"
info "Installing the expoemu command globally with $PM ($spec)"
if [ "$PM" = bun ]; then
  out="$(bun add -g "$spec" 2>&1)" || failed=1
else
  out="$(npm install -g "$spec" --no-audit --no-fund 2>&1)" || failed=1
fi
if [ -n "${failed:-}" ]; then
  printf '%s\n' "$out" | tail -5 >&2
  if [[ "$out" == *EACCES* ]]; then
    die "npm's global folder ($(npm prefix -g)) is not writable. Don't use sudo — either use a Node version manager (nvm, fnm, volta), or run once: npm config set prefix ~/.npm-global && echo 'export PATH=\"\$HOME/.npm-global/bin:\$PATH\"' >> ~/.zshrc"
  fi
  die "Global install failed — npx expoemu … keeps working"
fi

new="$(installed_version)"
[ -n "$new" ] || die "Installed, but $GLOBAL_BIN was not created"
ok "expoemu $new installed — from now on just type: expoemu up"

# The bin folder must be on the user's PATH (outside this npx process).
case ":${EXPOEMU_ORIG_PATH:-$PATH}:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH. Add it: echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc  (then open a new terminal)" ;;
esac
