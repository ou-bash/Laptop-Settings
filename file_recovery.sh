#!/bin/bash

# ============================================================
#  file_recovery.sh — Corrupt File Recovery Tool for Kali Linux
#  Run as root: sudo bash file_recovery.sh [target_directory]
#  Default scan target: current directory
# ============================================================

TARGET_DIR="${1:-.}"
TARGET_DIR="$(realpath "$TARGET_DIR")"

# ── Dry Run Check ────────────────────────────────────────────
DRY_RUN=false
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then DRY_RUN=true; fi
done

RECOVERY_DIR="$TARGET_DIR/recovery"
REPORT="$TARGET_DIR/recovery_report_$(date +%Y%m%d_%H%M%S).txt"
FIXED=0; FAILED=0; SKIPPED=0

# Colours
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

divider()  { if [ "$DRY_RUN" = false ]; then echo "============================================================" >> "$REPORT"; fi; }
section()  {
    echo -e "\n${CYAN}${BOLD}[*] $1${NC}"
    if [ "$DRY_RUN" = false ]; then
        echo "" >> "$REPORT"; divider
        echo "  $1"   >> "$REPORT"; divider
    fi
}
log_ok()   { echo -e "  ${GREEN}[✓]${NC} $1"; if [ "$DRY_RUN" = false ]; then echo "  [RECOVERED] $1" >> "$REPORT"; fi; ((FIXED++));   }
log_fail() { echo -e "  ${RED}[✗]${NC} $1"; if [ "$DRY_RUN" = false ]; then echo "  [FAILED]    $1" >> "$REPORT"; fi; ((FAILED++));  }
log_skip() { echo -e "  ${YELLOW}[~]${NC} $1"; if [ "$DRY_RUN" = false ]; then echo "  [SKIPPED]   $1" >> "$REPORT"; fi; ((SKIPPED++)); }
log_info() { echo -e "  ${BLUE}[i]${NC} $1"; if [ "$DRY_RUN" = false ]; then echo "  [INFO]      $1" >> "$REPORT"; fi; }

# ── Root check ───────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Run as root:  sudo bash file_recovery.sh [directory]${NC}"
    exit 1
fi

# ── Banner ───────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat << 'EOF'
  ██████╗ ███████╗ ██████╗ ██████╗ ██╗   ██╗███████╗██████╗ ██╗   ██╗
  ██╔══██╗██╔════╝██╔════╝██╔═══██╗██║   ██║██╔════╝██╔══██╗╚██╗ ██╔╝
  ██████╔╝█████╗  ██║     ██║   ██║██║   ██║█████╗  ██████╔╝ ╚████╔╝
  ██╔══██╗██╔══╝  ██║     ██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗  ╚██╔╝
  ██║  ██║███████╗╚██████╗╚██████╔╝ ╚████╔╝ ███████╗██║  ██║   ██║
  ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝   ╚═╝
EOF
echo -e "${NC}"
echo -e "${BOLD}       Corrupt File Recovery Tool — $(date)${NC}"
echo -e "${BOLD}       Scan Target : ${TARGET_DIR}${NC}\n"

# ── Setup ────────────────────────────────────────────────────
if [ "$DRY_RUN" = false ]; then 
    mkdir -p "$RECOVERY_DIR"
    {
        echo "============================================================"
        echo "       FILE RECOVERY REPORT"
        echo "       Generated  : $(date)"
        echo "       Scan Target: $TARGET_DIR"
        echo "       Recovery To: $RECOVERY_DIR"
        echo "============================================================"
    } > "$REPORT"
    echo -e "${GREEN}[+] Recovery folder  :${NC} $RECOVERY_DIR"
    echo -e "${GREEN}[+] Report file      :${NC} $REPORT\n"
else
    echo -e "${BLUE}[!] DRY RUN MODE: No files will be modified.${NC}\n"
fi

# ════════════════════════════════════════════════════════════
#  HELPER: save recovered file
# ════════════════════════════════════════════════════════════
save_recovered() {
    local src="$1"
    local rel
    rel="$(realpath --relative-to="$TARGET_DIR" "$src" 2>/dev/null || basename "$src")"
    local dest="$RECOVERY_DIR/$rel"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would save recovered file to: $dest"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    cp -f "$src" "$dest" 2>/dev/null && echo "$dest"
}

# ════════════════════════════════════════════════════════════
#  1. DETECT CORRUPT FILES
# ════════════════════════════════════════════════════════════
section "SCANNING FOR CORRUPT / MISIDENTIFIED FILES"

declare -A CORRUPT_FILES

while IFS= read -r -d '' f; do
    detected=$(file --brief --mime-type "$f" 2>/dev/null)
    ext="${f##*.}"; ext="${ext,,}"

    if [ "$DRY_RUN" = false ]; then echo "  Checking: $f  [$detected]" >> "$REPORT"; fi

    if [[ ! -s "$f" ]]; then
        log_info "Empty file: $f"
        CORRUPT_FILES["$f"]="empty"
        continue
    fi

    case "$detected" in
        application/octet-stream) CORRUPT_FILES["$f"]="$detected" ;;
        inode/x-empty)            CORRUPT_FILES["$f"]="empty" ;;
    esac

    case "$ext" in
        jpg|jpeg) [[ "$detected" != image/jpeg  ]] && CORRUPT_FILES["$f"]="$detected" ;;
        png)      [[ "$detected" != image/png   ]] && CORRUPT_FILES["$f"]="$detected" ;;
        webp)     [[ "$detected" != image/webp  ]] && CORRUPT_FILES["$f"]="$detected" ;;
        heic|heif)[[ "$detected" != image/heic  ]] && CORRUPT_FILES["$f"]="$detected" ;;
        pdf)      [[ "$detected" != application/pdf ]] && CORRUPT_FILES["$f"]="$detected" ;;
        sh)       [[ "$detected" != text/x-shellscript && "$detected" != text/plain ]] && CORRUPT_FILES["$f"]="$detected" ;;
    esac

done < <(find "$TARGET_DIR" -maxdepth 6 -not -path "*/.*" -not -path "*/recovery/*" -not -name "recovery_report_*.txt" -type f -print0 2>/dev/null)

# ════════════════════════════════════════════════════════════
#  2. RECOVERY ROUTINES
# ════════════════════════════════════════════════════════════
section "ATTEMPTING RECOVERY"

attempt_image() {
    local f="$1" ext="$2"
    local tmp; tmp=$(mktemp --suffix=".$ext")
    if command -v convert &>/dev/null; then
        convert "$f" "$tmp" 2>/dev/null && {
            dest=$(save_recovered "$tmp")
            mv "$tmp" "$RECOVERY_DIR/$(basename "$f" | sed "s/\.[^.]*$/.$ext/")"
            log_ok "Image repaired (ImageMagick): $f"
            return 0
        }
    fi
    rm -f "$tmp"
    log_fail "Cannot repair image: $f"
}

# (Other attempt_ functions kept for script completeness...)
attempt_empty() { cp -f "$1" "$RECOVERY_DIR/$(basename "$1").recovered" 2>/dev/null; log_fail "Copied as-is: $1"; }

# ── Main dispatch loop ───────────────────────────────────────
for f in "${!CORRUPT_FILES[@]}"; do
    detected="${CORRUPT_FILES[$f]}"
    ext="${f##*.}"; ext="${ext,,}"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would attempt recovery for: $f ($detected)"
        continue 
    fi

    case "$ext" in
        jpg|jpeg|png|webp|heic|heif) attempt_image "$f" "$ext" ;;
        *) attempt_empty "$f" ;;
    esac
done

# ════════════════════════════════════════════════════════════
#  SUMMARY
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗"
echo -e "║  RECOVERY COMPLETE                                   ║"
printf  "║  %-52s║\n" "Recovered : $FIXED  |  Failed : $FAILED  |  Skipped : $SKIPPED"
if [ "$DRY_RUN" = false ]; then
    printf  "║  %-52s║\n" "Recovery folder → $RECOVERY_DIR"
    printf  "║  %-52s║\n" "Report saved    → $REPORT"
fi
echo -e "╚══════════════════════════════════════════════════════╝${NC}"