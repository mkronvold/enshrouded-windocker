#!/bin/bash
# ============================================================
# Enshrouded Dedicated Server - Linux/Wine Container Entrypoint
# ============================================================
set -euo pipefail

export SERVER_DIR="/home/steam/enshrouded"
STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
APP_ID=2278520
CONFIG_FILE="$SERVER_DIR/enshrouded_server.json"
SERVER_EXE="$SERVER_DIR/enshrouded_server.exe"

export WINEPREFIX="${WINEPREFIX:-/home/steam/.wine}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:-warn+all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=d;mshtml=d;msvcp140=n,b;vcruntime140=n,b;vcruntime140_1=n,b}"
export DISPLAY="${DISPLAY:-:99}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-steam}"

WINE="$(command -v wine || echo /opt/wine-staging/bin/wine)"

# ── Helpers ──────────────────────────────────────────────────────────────────

get_env() { local val="${!1:-}"; echo "${val:-${2:-}}"; }

send_webhook() {
    local msg="$1"
    [[ -z "${WEBHOOK_URL:-}" ]] && return 0
    local escaped
    escaped=$(printf '%s' "$msg" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")
    curl -sf -X POST "$WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "{\"content\":$escaped}" >/dev/null 2>&1 || true
}

# ── Config generation ─────────────────────────────────────────────────────────

write_config() {
    python3 - <<'PYEOF'
import json, os

def genv(name, default=""): return os.environ.get(name, default)
def getf(name, default):    return float(os.environ.get(name, default))
def getb(name, default):    return os.environ.get(name, str(default).lower()) == "true"
def geti(name, default):    return int(os.environ.get(name, default))
def getl(name, default):    return int(os.environ.get(name, default))

groups = [{
    "name":                 "Default",
    "password":             genv("SET_GROUP_DEFAULT_PASSWORD", ""),
    "canKickBan":           False,
    "canAccessInventories": True,
    "canEditWorld":         True,
    "canEditBase":          True,
    "canExtendBase":        True,
    "reservedSlots":        0,
}]

for gname in ("VISITOR", "HELPER", "FRIEND", "ADMIN"):
    pw = genv(f"SET_GROUP_{gname}_PASSWORD", "")
    if pw:
        groups.append({
            "name":                 gname.capitalize(),
            "password":             pw,
            "canKickBan":           getb(f"SET_GROUP_{gname}_CAN_KICK_BAN", False),
            "canAccessInventories": getb(f"SET_GROUP_{gname}_CAN_ACCESS_INVENTORIES", True),
            "canEditWorld":         True,
            "canEditBase":          True,
            "canExtendBase":        True,
            "reservedSlots":        0,
        })

config = {
    "name":               genv("NAME", "Enshrouded Server"),
    "saveDirectory":      "./savegame",
    "logDirectory":       "./logs",
    "ip":                 "0.0.0.0",
    "queryPort":          geti("QUERY_PORT", 15637),
    "slotCount":          geti("SLOT_COUNT", 16),
    "tags":               [],
    "voiceChatMode":      genv("VOICE_CHAT_MODE", "Proximity"),
    "enableVoiceChat":    getb("ENABLE_VOICE_CHAT", False),
    "enableTextChat":     getb("ENABLE_TEXT_CHAT", False),
    "gameSettingsPreset": "Custom",
    "gameSettings": {
        "playerHealthFactor":                getf("PLAYER_HEALTH_FACTOR", 1.0),
        "playerManaFactor":                  getf("PLAYER_MANA_FACTOR", 1.0),
        "playerStaminaFactor":               getf("PLAYER_STAMINA_FACTOR", 1.0),
        "playerBodyHeatFactor":              getf("PLAYER_BODY_HEAT_FACTOR", 1.0),
        "playerDivingTimeFactor":            getf("PLAYER_DIVING_TIME_FACTOR", 1.0),
        "enableDurability":                  getb("ENABLE_DURABILITY", True),
        "enableStarvingDebuff":              getb("ENABLE_STARVING_DEBUFF", False),
        "foodBuffDurationFactor":            getf("FOOD_BUFF_DURATION_FACTOR", 1.0),
        "fromHungerToStarving":              getl("FROM_HUNGER_TO_STARVING", 600000000000),
        "shroudTimeFactor":                  getf("SHROUD_TIME_FACTOR", 1.0),
        "tombstoneMode":                     genv("TOMBSTONE_MODE", "AddBackpackMaterials"),
        "enableGliderTurbulences":           getb("ENABLE_GLIDER_TURBULENCES", True),
        "weatherFrequency":                  genv("WEATHER_FREQUENCY", "Normal"),
        "fishingDifficulty":                 genv("FISHING_DIFFICULTY", "Normal"),
        "miningDamageFactor":                getf("MINING_DAMAGE_FACTOR", 1.0),
        "plantGrowthSpeedFactor":            getf("PLANT_GROWTH_SPEED_FACTOR", 1.0),
        "resourceDropStackAmountFactor":     getf("RESOURCE_DROP_STACK_AMOUNT_FACTOR", 1.0),
        "factoryProductionSpeedFactor":      getf("FACTORY_PRODUCTION_SPEED_FACTOR", 1.0),
        "perkUpgradeRecyclingFactor":        getf("PERK_UPGRADE_RECYCLING_FACTOR", 0.5),
        "perkCostFactor":                    getf("PERK_COST_FACTOR", 1.0),
        "experienceCombatFactor":            getf("EXPERIENCE_COMBAT_FACTOR", 1.0),
        "experienceMiningFactor":            getf("EXPERIENCE_MINING_FACTOR", 1.0),
        "experienceExplorationQuestsFactor": getf("EXPERIENCE_EXPLORATION_QUESTS_FACTOR", 1.0),
        "randomSpawnerAmount":               genv("RANDOM_SPAWNER_AMOUNT", "Normal"),
        "aggroPoolAmount":                   genv("AGGRO_POOL_AMOUNT", "Normal"),
        "enemyDamageFactor":                 getf("ENEMY_DAMAGE_FACTOR", 1.0),
        "enemyHealthFactor":                 getf("ENEMY_HEALTH_FACTOR", 1.0),
        "enemyStaminaFactor":                getf("ENEMY_STAMINA_FACTOR", 1.0),
        "enemyPerceptionRangeFactor":        getf("ENEMY_PERCEPTION_RANGE_FACTOR", 1.0),
        "bossDamageFactor":                  getf("BOSS_DAMAGE_FACTOR", 1.0),
        "bossHealthFactor":                  getf("BOSS_HEALTH_FACTOR", 1.0),
        "threatBonus":                       getf("THREAT_BONUS", 1.0),
        "pacifyAllEnemies":                  getb("PACIFY_ALL_ENEMIES", False),
        "tamingStartleRepercussion":         genv("TAMING_STARTLE_REPERUSSION", "LoseSomeProgress"),
        "dayTimeDuration":                   getl("DAY_TIME_DURATION", 1800000000000),
        "nightTimeDuration":                 getl("NIGHT_TIME_DURATION", 720000000000),
        "curseModifier":                     genv("CURSE_MODIFIER", "Normal"),
    },
    "userGroups":    groups,
    "gamePort":      geti("GAME_PORT", 15636),
    "bannedAccounts": [],
}

cfg_path = os.environ["SERVER_DIR"] + "/enshrouded_server.json"
with open(cfg_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)
print(f"[OK] Config written to {cfg_path}")
PYEOF
}

# ── SteamCMD install/update ───────────────────────────────────────────────────

install_server() {
    echo "[DL]  Installing/Updating Enshrouded server (App $APP_ID)..."
    "$STEAMCMD" \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir "$SERVER_DIR" \
        +login anonymous \
        +app_update "$APP_ID" validate \
        +quit
    echo "[OK] Server installed/updated."
}

# ── Cron-style schedule check ─────────────────────────────────────────────────
# Returns 0 (true) if the schedule is due and hasn't run today yet.
# Supports "MIN HOUR * * *" format only (daily schedules).

is_schedule_due() {
    local schedule="$1" last_run_day="$2"
    local min hour
    min=$(echo  "$schedule" | awk '{print $1}')
    hour=$(echo "$schedule" | awk '{print $2}')
    local now_hour now_min today
    now_hour=$(date +%-H)
    now_min=$(date +%-M)
    today=$(date +%Y%m%d)
    [[ "$now_hour" -eq "$hour" && "$now_min" -ge "$min" && "$last_run_day" != "$today" ]]
}

# ── Cleanup trap ──────────────────────────────────────────────────────────────

XVFB_PID=""
SERVER_PID=""

cleanup() {
    echo "[WARN] Shutdown signal received..."
    send_webhook "[DOWN] **$(get_env NAME 'Enshrouded Server')** is shutting down..."
    if [[ -n "$SERVER_PID" ]]; then
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        # Wait up to 30 s for graceful exit
        for _ in $(seq 1 30); do
            kill -0 "$SERVER_PID" 2>/dev/null || break
            sleep 1
        done
        kill -KILL "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    [[ -n "$XVFB_PID" ]] && kill "$XVFB_PID" 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# ── Main ──────────────────────────────────────────────────────────────────────

echo "=========================================================="
echo ">> Enshrouded Dedicated Server (Linux/Wine) - $(date -u)"
echo "=========================================================="

mkdir -p "$SERVER_DIR/logs" "$SERVER_DIR/savegame"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

# Kill any stale Xvfb and remove its lock so restarts don't get "already active"
DISPLAY_NUM="${DISPLAY:1}"
pkill -f "Xvfb $DISPLAY" 2>/dev/null || true
sleep 0.3
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true

# Start virtual display
Xvfb "$DISPLAY" -screen 0 1024x768x16 -nolisten tcp -ac &
XVFB_PID=$!
echo "[OK] Xvfb started on $DISPLAY (PID $XVFB_PID)"
sleep 1

# Initialize Wine prefix if not already present (first run of a fresh volume)
if [[ ! -d "$WINEPREFIX/drive_c" ]]; then
    echo "[WINE] Initializing Wine prefix (WINEARCH=$WINEARCH)..."
    xvfb-run --auto-servernum wineboot --init 2>/dev/null || true
    echo "[OK] Wine prefix ready."
fi
# Install/update server binary
if [[ "$(get_env UPDATE_ON_START true)" == "true" || ! -f "$SERVER_EXE" ]]; then
    install_server
fi

# Generate server config
echo "[CFG]  Generating server config..."
write_config

# Launch server under Wine
echo "[START] Starting Enshrouded server via Wine..."
send_webhook "[UP] **$(get_env NAME 'Enshrouded Server')** is starting..."

# SteamAPI needs steam_appid.txt in the working directory for headless launch
echo "2278520" > "$SERVER_DIR/steam_appid.txt"

# List installed server files (useful for diagnosing missing binaries)
echo "[INFO] Server directory contents:"
ls -la "$SERVER_DIR/" 2>/dev/null | head -30

# Check for a native Linux binary (in case Steam added Linux depot support)
LINUX_EXE="$SERVER_DIR/enshrouded_server"
if [[ -f "$LINUX_EXE" && ! "$LINUX_EXE" == *.exe ]]; then
    echo "[INFO] Found potential native Linux binary: $LINUX_EXE"
fi

# PE section page-alignment fix:
# Wine (7.x+ wow64 mode) cannot use mmap for sections with non-page-aligned file offsets
# (FileAlignment=0x200 means rp=0x400, 0xad8800, etc. — none are multiples of 0x1000).
# Its pread/read fallback has a bug writing section data to 64-bit virtual addresses >4GB,
# leaving zeros at the mapped location. Fix: create a page-aligned copy of the exe so that
# Wine can use mmap directly for every section.
PE_OUT=$(python3 - <<'PYEOF'
import struct, os, sys

PAGE = 0x1000
exe      = os.environ.get('SERVER_EXE', '/home/steam/enshrouded/enshrouded_server.exe')
realigned = exe + '.page_aligned'

try:
    sz = os.path.getsize(exe)
    with open(exe, 'rb') as f:
        data = bytearray(f.read())

    pe_off  = struct.unpack_from('<I', data, 0x3c)[0]
    machine = struct.unpack_from('<H', data, pe_off + 4)[0]
    nsec    = struct.unpack_from('<H', data, pe_off + 6)[0]
    opt_sz  = struct.unpack_from('<H', data, pe_off + 20)[0]
    magic   = struct.unpack_from('<H', data, pe_off + 24)[0]
    aep     = struct.unpack_from('<I', data, pe_off + 40)[0]
    mach    = {0x8664: 'x86_64', 0x14c: 'i386'}.get(machine, hex(machine))
    print(f"[PE]  {sz//1024//1024}MB  machine={mach}  {'PE32+' if magic==0x020b else 'PE32'}  entry_rva=0x{aep:x}  nsec={nsec}")

    # Read all section headers
    shdrs_base = pe_off + 24 + opt_sz
    sections = []
    for i in range(nsec):
        off = shdrs_base + i * 40
        nm = data[off:off+8].decode('ascii', errors='replace').rstrip('\x00')
        vs, va, rs, rp = struct.unpack_from('<IIII', data, off + 8)
        sections.append({'i': i, 'nm': nm, 'vs': vs, 'va': va, 'rs': rs, 'rp': rp, 'off': off})
        aligned = 'page-aligned' if rp % PAGE == 0 else f'NOT page-aligned (rp%{PAGE}=0x{rp%PAGE:x})'
        print(f"[PE]  sec[{i}]={nm!r}  va=0x{va:x}  vs=0x{vs:x}  rs=0x{rs:x}  rp=0x{rp:x}  [{aligned}]")

    # Show entry point bytes from the file
    es = next((s for s in sections if s['va'] <= aep < s['va'] + max(s['vs'], s['rs'], 1)), None)
    if es:
        foff = es['rp'] + (aep - es['va'])
        print(f"[PE]  entry file_off=0x{foff:x}  bytes={data[foff:foff+16].hex()}")

    # Check if realignment is needed
    unaligned = [s for s in sections if s['rp'] % PAGE != 0]
    if not unaligned:
        print(f"[PE]  All sections page-aligned — Wine mmap path should work fine")
        sys.exit(0)

    # Skip if already realigned and newer than the original
    if (os.path.exists(realigned) and
            os.path.getmtime(realigned) >= os.path.getmtime(exe)):
        print(f"[PE]  Page-aligned copy already exists: {realigned}")
        print(f"[PE_REALIGNED_EXE] {realigned}")
        sys.exit(0)

    print(f"[PE]  {len(unaligned)}/{nsec} sections need page-alignment — building realigned copy...")

    # Compute new page-aligned PointerToRawData for each section
    headers_end = shdrs_base + nsec * 40
    cur_pos = (headers_end + PAGE - 1) & ~(PAGE - 1)   # round headers up to page
    for s in sections:
        s['new_rp'] = cur_pos
        s['new_rs'] = (s['rs'] + PAGE - 1) & ~(PAGE - 1)
        cur_pos += s['new_rs']

    # Build new file: original headers + padding + page-aligned section data
    new_data = bytearray(data[:headers_end])
    new_data += b'\x00' * (sections[0]['new_rp'] - headers_end)
    for s in sections:
        assert len(new_data) == s['new_rp'], f"offset mismatch for {s['nm']}"
        raw = data[s['rp']:s['rp'] + s['rs']]
        new_data += raw
        new_data += b'\x00' * (s['new_rs'] - s['rs'])   # pad to page boundary

    # Patch section headers in the new file
    for s in sections:
        struct.pack_into('<I', new_data, s['off'] + 16, s['new_rs'])  # SizeOfRawData
        struct.pack_into('<I', new_data, s['off'] + 20, s['new_rp'])  # PointerToRawData

    # Update optional header fields (optional header starts at pe_off+24)
    struct.pack_into('<I', new_data, pe_off + 24 + 36, PAGE)                      # FileAlignment
    struct.pack_into('<I', new_data, pe_off + 24 + 60, sections[0]['new_rp'])     # SizeOfHeaders

    with open(realigned, 'wb') as f:
        f.write(new_data)
    os.chmod(realigned, 0o755)

    # Verify entry point bytes are preserved
    new_foff = es['new_rp'] + (aep - es['va'])
    print(f"[PE]  Realigned: {sz}B → {len(new_data)}B  entry_file_off: 0x{foff:x} → 0x{new_foff:x}")
    print(f"[PE]  Entry bytes in new file: {new_data[new_foff:new_foff+16].hex()}")
    print(f"[PE_REALIGNED_EXE] {realigned}")

except Exception as e:
    import traceback; print(f"[PE]  error: {e}"); traceback.print_exc()
PYEOF
)
echo "$PE_OUT"

# If the script produced a page-aligned exe, use it — Wine can mmap it correctly
REALIGNED_EXE=$(echo "$PE_OUT" | grep '^\[PE_REALIGNED_EXE\]' | awk '{print $2}')
if [[ -n "$REALIGNED_EXE" && -f "$REALIGNED_EXE" ]]; then
    echo "[INFO] Using page-aligned exe (Wine mmap fix): $REALIGNED_EXE"
    SERVER_EXE="$REALIGNED_EXE"
fi

cd "$SERVER_DIR"

# ── Cleanup any Goldberg artifacts left on the shared volume ─────────────────
# Previous versions placed Goldberg's steam_api64.dll (3207680 bytes) and
# steam_settings/ on the shared volume — remove them so the real DLL (from
# the server depot or user-provided) is used instead.
GOLDBERG_SIZE=3207680
EXISTING_SZ=$(stat -c%s "$SERVER_DIR/steam_api64.dll" 2>/dev/null || echo "0")
if [[ "$EXISTING_SZ" -eq "$GOLDBERG_SIZE" ]]; then
    echo "[DLL] Removing Goldberg stub (${EXISTING_SZ}B) — will be replaced by depot copy"
    rm -f "$SERVER_DIR/steam_api64.dll"
fi
rm -rf "$SERVER_DIR/steam_settings"
rm -f  "$SERVER_DIR/steam_appid.txt"

# Report DLL status
if [[ -f "$SERVER_DIR/steam_api64.dll" ]]; then
    echo "[DLL] steam_api64.dll present ($(stat -c%s "$SERVER_DIR/steam_api64.dll")B)"
else
    echo "[WARN] steam_api64.dll not present — validate should have provided it"
fi

WINEDEBUG="-all" "$WINE" "$SERVER_EXE" &
SERVER_PID=$!
echo "[OK] Server started (PID $SERVER_PID)"
send_webhook "[UP] **$(get_env NAME 'Enshrouded Server')** is starting..."

# ── Monitor loop ──────────────────────────────────────────────────────────────

LAST_AUTO_UPDATE_DAY=""
LAST_RESTART_DAY=""

while kill -0 "$SERVER_PID" 2>/dev/null; do
    sleep 30

    # Auto-update
    if [[ "$(get_env AUTO_UPDATE true)" == "true" ]]; then
        schedule="$(get_env AUTO_UPDATE_SCHEDULE '0 3 * * *')"
        if is_schedule_due "$schedule" "$LAST_AUTO_UPDATE_DAY"; then
            echo "[UPDATE] Auto-update triggered at $(date -u)..."
            send_webhook "[UPDATE] **$(get_env NAME 'Enshrouded Server')** updating, restarting shortly..."
            kill -TERM "$SERVER_PID" 2>/dev/null || true
            wait "$SERVER_PID" 2>/dev/null || true
            install_server
            write_config
            cd "$SERVER_DIR"
            "$WINE" "$SERVER_EXE" &
            SERVER_PID=$!
            LAST_AUTO_UPDATE_DAY="$(date +%Y%m%d)"
            send_webhook "[OK] **$(get_env NAME 'Enshrouded Server')** restarted after update."
        fi
    fi

    # Scheduled restart
    if [[ "$(get_env SCHEDULED_RESTART true)" == "true" ]]; then
        schedule="$(get_env SCHEDULED_RESTART_SCHEDULE '0 4 * * *')"
        if is_schedule_due "$schedule" "$LAST_RESTART_DAY"; then
            echo "[RESTART] Scheduled restart triggered at $(date -u)..."
            send_webhook "[RESTART] **$(get_env NAME 'Enshrouded Server')** performing scheduled restart..."
            kill -TERM "$SERVER_PID" 2>/dev/null || true
            wait "$SERVER_PID" 2>/dev/null || true
            cd "$SERVER_DIR"
            "$WINE" "$SERVER_EXE" &
            SERVER_PID=$!
            LAST_RESTART_DAY="$(date +%Y%m%d)"
            send_webhook "[OK] **$(get_env NAME 'Enshrouded Server')** restarted."
        fi
    fi
done

EXIT_CODE=0
wait "$SERVER_PID" 2>/dev/null || EXIT_CODE=$?
echo "[WARN] Server process exited with code $EXIT_CODE"
# Show all log files — find any new ones and tail the largest
echo "[LOG] Searching for server logs in $SERVER_DIR ..."
find "$SERVER_DIR" -name "*.log" -not -path "*/Steam/logs/*" 2>/dev/null | while read -r logf; do
    sz=$(wc -l < "$logf" 2>/dev/null || echo 0)
    echo "[LOG] $logf ($sz lines) — last 60 lines:"
    tail -60 "$logf"
    echo "---"
done
send_webhook "[DOWN] **$(get_env NAME 'Enshrouded Server')** has stopped (exit code: $EXIT_CODE)"
[[ -n "$XVFB_PID" ]] && kill "$XVFB_PID" 2>/dev/null || true
exit "$EXIT_CODE"
