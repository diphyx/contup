#!/usr/bin/env bash
#
# Generate showcase GIFs with macOS window frame
#
# Dependencies: asciinema, agg, imagemagick
#
# Usage: ./mockup.sh
#
# Output:
#   setup.gif     — install contup CLI
#   install.gif   — install docker runtime
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Shared ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

S_OK="✔"

PROMPT="${GREEN}root@ubuntu${NC}:${CYAN}~${NC}# "

type_cmd() { for ((i=0;i<${#1};i++)); do printf '%s' "${1:$i:1}"; sleep 0.04; done; }
type_input() { for ((i=0;i<${#1};i++)); do printf '%s' "${1:$i:1}"; sleep 0.05; done; }
enter() { sleep 0.3; printf '\n'; }
prompt_default() { sleep 0.6; printf '\n'; }
prompt_type() { sleep 0.5; type_input "$1"; sleep 0.3; printf '\n'; }

# --- Window wrapper ---
wrap_window() {
    local INPUT="$1" OUTPUT="$2" BG_COLOR="$3" BAR_COLOR="$4"
    local TITLE_HEIGHT=36
    local DOT_Y=$((TITLE_HEIGHT / 2))

    local WIDTH=$(magick identify -format "%w" "$INPUT[0]")
    local HEIGHT=$(magick identify -format "%h" "$INPUT[0]")

    local TOTAL_W=$((WIDTH + 20))
    local TOTAL_H=$((HEIGHT + TITLE_HEIGHT + 20))

    magick -size "${TOTAL_W}x${TOTAL_H}" "xc:${BG_COLOR}" \
        -fill "$BAR_COLOR" \
        -draw "rectangle 0,0 $((TOTAL_W-1)),$TITLE_HEIGHT" \
        -fill "#ff5f57" -draw "circle 20,$DOT_Y 26,$DOT_Y" \
        -fill "#febc2e" -draw "circle 40,$DOT_Y 46,$DOT_Y" \
        -fill "#28c840" -draw "circle 60,$DOT_Y 66,$DOT_Y" \
        /tmp/window-frame.png

    local TMPDIR=$(mktemp -d)
    magick identify -format "%T\n" "$INPUT" > "$TMPDIR/delays.txt"
    magick "$INPUT" -coalesce "$TMPDIR/frame-%04d.png"

    local i=0
    for frame in "$TMPDIR"/frame-*.png; do
        magick /tmp/window-frame.png "$frame" \
            -geometry "+10+$((TITLE_HEIGHT + 10))" \
            -composite \
            "$TMPDIR/out-$(printf '%04d' $i).png"
        ((i++))
    done

    local DELAY_ARGS="" i=0
    while read -r delay; do
        [[ -z "$delay" ]] && delay=10
        DELAY_ARGS="$DELAY_ARGS -delay $delay $TMPDIR/out-$(printf '%04d' $i).png"
        ((i++))
    done < "$TMPDIR/delays.txt"

    eval magick $DELAY_ARGS -loop 0 "$OUTPUT"
    rm -rf "$TMPDIR" /tmp/window-frame.png
}

# --- Record + wrap a single demo ---
record_demo() {
    local NAME="$1" ROWS="$2"
    local CAST="$SCRIPT_DIR/$NAME.cast"

    local GIF_DIR="$SCRIPT_DIR/gif"
    local PNG_DIR="$SCRIPT_DIR/png"
    mkdir -p "$GIF_DIR" "$PNG_DIR"

    echo "Recording $NAME..."
    asciinema rec --window-size "80x${ROWS}" --overwrite -c "$0 __run_${NAME}" "$CAST"

    local GIF_RAW="$GIF_DIR/$NAME-raw.gif"
    local GIF_FINAL="$GIF_DIR/$NAME.gif"
    agg --theme github-dark --font-size 16 "$CAST" "$GIF_RAW"
    rm -f "$CAST"

    echo "Wrapping $NAME..."
    wrap_window "$GIF_RAW" "$GIF_FINAL" "#171B21" "#1F2329"
    rm -f "$GIF_RAW"

    # Extract last frame as PNG
    local PNG_FINAL="$PNG_DIR/$NAME.png"
    local LAST_FRAME=$(magick identify "$GIF_FINAL" | tail -1 | sed 's/.*\[\([0-9]*\)\].*/\1/')
    magick "${GIF_FINAL}[${LAST_FRAME}]" "$PNG_FINAL"

    echo "Saved: $GIF_FINAL"
    echo "Saved: $PNG_FINAL"
    echo ""
}

# =====================
# Demo scenes
# =====================

run_setup() {
    echo -ne "$PROMPT"
    sleep 0.5
    type_cmd "curl -fsSL diphyx.github.io/contup/setup.sh | bash"; enter
    sleep 0.3

    echo -e "\n${BOLD}  contup — container up${NC}"
    echo ""
    sleep 0.3

    echo -e "  ${GREEN}${S_OK}${NC}  Installed contup to /home/user/.local/bin"
    sleep 0.2
    echo -e "  ${GREEN}${S_OK}${NC}  Added /home/user/.local/bin to PATH"
    sleep 0.2
    echo -e "  ${GREEN}${S_OK}${NC}  Installed contup shell wrapper"
    sleep 0.3

    echo ""
    echo -e "  ${BOLD}${S_OK} contup CLI installed${NC}"
    echo ""
    echo -e "  Next: ${BOLD}contup install${NC} <docker|podman>"
    echo ""
    sleep 0.1
}

run_install() {
    echo -ne "$PROMPT"
    sleep 0.5
    type_cmd "contup install docker -y"; enter
    sleep 0.3

    # Step 1 — System Check
    echo -e "\n${BOLD}Step 1 — System Check${NC}"
    sleep 0.3
    echo -e "  ${GREEN}${S_OK}${NC}  System compatible"
    sleep 0.3

    # Step 2 — Download / Extract
    echo -e "\n${BOLD}Step 2 — Download / Extract${NC}"
    sleep 0.3
    echo -e "  ${GREEN}${S_OK}${NC}  Downloaded and extracted"
    sleep 0.3

    # Step 3 — Install Binaries
    echo -e "\n${BOLD}Step 3 — Install Binaries${NC}"
    sleep 0.3
    echo -e "  ${GREEN}${S_OK}${NC}  Installed to /home/user/.local/bin"
    sleep 0.3

    # Step 4 — Configure
    echo -e "\n${BOLD}Step 4 — Configure${NC}"
    sleep 0.3
    echo -e "  ${GREEN}${S_OK}${NC}  Docker configured"
    sleep 0.3

    # Step 5 — Start Services
    echo -e "\n${BOLD}Step 5 — Start Services${NC}"
    sleep 0.3
    echo -e "  ${GREEN}${S_OK}${NC}  Docker started"
    sleep 0.3

    # Step 6 — Verify
    echo -e "\n${BOLD}Step 6 — Verify${NC}"
    sleep 0.3
    echo -e "  ${GREEN}${S_OK}${NC}  Docker running"
    sleep 0.15
    echo -e "  ${GREEN}${S_OK}${NC}  Compose ready"
    sleep 0.3

    echo ""
    echo -e "  ${BOLD}${S_OK} contup — install complete${NC}"
    echo ""
    sleep 0.1
}

# --- Main ---
case "${1:-}" in
    __run_setup)   run_setup ;;
    __run_install) run_install ;;
    *)
        record_demo "setup" 13
        record_demo "install" 24
        echo ""
        echo "All done!"
        ;;
esac
