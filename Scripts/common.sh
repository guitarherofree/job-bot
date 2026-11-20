# Shared names and helpers for the build and install scripts (sourced; bash 3.2-safe).
APP_NAME="Job Bot.app"
BUNDLE_ID="com.guitarherofree.jobbot"
PROCESS_NAME="JobBot"

# Convert a 1024×1024 PNG into an .icns file (uses macOS's sips and iconutil).
make_icns() {
  local src="$1" out="$2" dir s
  command -v iconutil >/dev/null 2>&1 && command -v sips >/dev/null 2>&1 && [ -f "$src" ] || return 1
  dir="$(mktemp -d "${TMPDIR:-/tmp}/jobbot-icon.XXXXXX")/icon.iconset"
  mkdir -p "$dir"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$src" --out "$dir/icon_${s}x${s}.png" >/dev/null 2>&1 || return 1
    sips -z "$((s * 2))" "$((s * 2))" "$src" --out "$dir/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || return 1
  done
  iconutil -c icns "$dir" -o "$out" >/dev/null 2>&1
}
