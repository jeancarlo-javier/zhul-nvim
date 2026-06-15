#!/usr/bin/env bash
# Restore zhul-nvim onto this machine.
# - Copies nvim/ -> ~/.config/nvim (backing up any existing config first)
# - Installs the Karabiner Ctrl+[ -> F13 rule (macOS, optional)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_DST="$HOME/.config/nvim"
KB_DST="$HOME/.config/karabiner/assets/complex_modifications"

echo "==> Restoring Neovim config to $NVIM_DST"
if [ -e "$NVIM_DST" ]; then
  BK="$NVIM_DST.backup.$(date +%Y%m%d-%H%M%S)"
  echo "    existing config found -> backing up to $BK"
  mv "$NVIM_DST" "$BK"
fi
mkdir -p "$NVIM_DST"
cp -R "$HERE/nvim/." "$NVIM_DST/"
echo "    done."

if [ "$(uname)" = "Darwin" ]; then
  echo "==> Installing Karabiner Ctrl+[ rule to $KB_DST"
  mkdir -p "$KB_DST"
  cp "$HERE/karabiner/ctrl-bracket-f13.json" "$KB_DST/"
  echo "    done (enable it in Karabiner-Elements > Settings > Complex Modifications)."
fi

cat <<'EOF'

==> All set. Next steps:
  1. Launch  nvim  -> lazy.nvim installs plugins; Mason installs LSPs/formatters.
     (run :Lazy restore to pin the exact versions from lazy-lock.json)
  2. macOS only: install Karabiner-Elements, grant it Input Monitoring,
     and enable the "Terminal: Ctrl+[ -> F13" rule.
EOF
