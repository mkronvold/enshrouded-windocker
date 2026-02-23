# enshrouded-windocker

A Windows container for running an [Enshrouded](https://store.steampowered.com/app/1203620/Enshrouded/) dedicated server natively — no Wine, no emulation. Built on Windows Server Core with SteamCMD for Windows. All game settings are driven by environment variables so no manual config editing is needed.

---

## Requirements

- **Windows 10/11** or **Windows Server 2019/2022** host
- **Docker Desktop** with **Windows containers** mode enabled
  - Right-click the Docker tray icon → *Switch to Windows containers...*
- **Git** (to clone this repo)
- ~15 GB free disk space (Windows base image ~5 GB, game files ~7 GB)
- Ports **15636** and **15637** open on your firewall (TCP + UDP)

---

## Quick Start

### 1. Clone the repo

```powershell
git clone https://github.com/mkronvold/enshrouded-windocker.git
cd enshrouded-windocker
```

### 2. Create your configuration file

```powershell
Copy-Item .env.example .env
```

Edit `.env` with your server name, passwords, Discord webhook URL, and any game settings you want to change (see [Configuration](#configuration)).

### 3. Directory structure

The project expects this layout. The `enshrouded` data folder sits **alongside** the repo so it is never accidentally committed.

```
C:\docker\
├── enshrouded-windocker\   ← this repo (code, config)
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── .env                ← your secrets (gitignored)
│   ├── .env.example
│   └── scripts\
│       └── entrypoint.ps1
└── enshrouded\             ← server data volume (auto-created on first run)
    ├── enshrouded_server.json
    ├── savegame\
    └── logs\
```

> The volume mount in `docker-compose.yml` is `../enshrouded:C:\enshrouded`, so the data folder is always one level up from the repo root.

### 4. Build and start

```powershell
docker compose build
docker compose up -d
```

On first run, SteamCMD will download the Enshrouded dedicated server (~7 GB). Subsequent starts skip the download unless `UPDATE_ON_START` is `true`.

### 5. Verify

```powershell
docker logs enshrouded-windocker-enshrouded-1 --tail 20
```

Look for `Session` output confirming the server is listening.

---

## Configuration

All configuration lives in `.env` — the `docker-compose.yml` is clean and requires no edits.  
Changes to `.env` take effect on the next container start without rebuilding the image:

```powershell
docker compose up -d --force-recreate
```

Copy `.env.example` to `.env` to get started. The example file documents every variable with its valid values.

### Secrets & Passwords

These must be kept out of source control. They live **only** in `.env` (gitignored).

| Variable | Description |
|---|---|
| `WEBHOOK_URL` | Discord webhook URL for server notifications. Leave blank to disable. |
| `SET_GROUP_DEFAULT_PASSWORD` | Password required to connect at all. Anyone who connects without a higher-role password lands here. Leave blank for open access. |
| `SET_GROUP_VISITOR_PASSWORD` | Password to join as Visitor. Leave blank to disable this role. |
| `SET_GROUP_HELPER_PASSWORD` | Password to join as Helper. Leave blank to disable this role. |
| `SET_GROUP_FRIEND_PASSWORD` | Password to join as Friend. Leave blank to disable this role. |
| `SET_GROUP_ADMIN_PASSWORD` | Password to join as Admin. Leave blank to disable this role. |

### General

| Variable | Default | Description |
|---|---|---|
| `TZ` | `America/Chicago` | Container timezone. Uses tz database names (e.g. `America/New_York`, `Europe/London`). |
| `NAME` | `Enshrouded Server` | Server name shown in the server browser. |
| `GAME_PORT` | `15636` | UDP/TCP port for game traffic. |
| `QUERY_PORT` | `15637` | UDP/TCP port for server queries. |
| `SLOT_COUNT` | `16` | Maximum number of players (1–16). |
| `UPDATE_ON_START` | `true` | Run SteamCMD update check every time the container starts. Set to `false` after initial install to speed up startup. |
| `AUTO_UPDATE` | `true` | Automatically update and restart the server on a schedule. |
| `AUTO_UPDATE_SCHEDULE` | `0 3 * * *` | Cron schedule for auto-update (default: 3:00 AM daily). |
| `SCHEDULED_RESTART` | `true` | Restart the server on a schedule. |
| `SCHEDULED_RESTART_SCHEDULE` | `0 4 * * *` | Cron schedule for scheduled restart (default: 4:00 AM daily). |

### Chat

| Variable | Default | Valid Values | Description |
|---|---|---|---|
| `ENABLE_TEXT_CHAT` | `true` | `true`, `false` | Enable in-game text chat. |
| `ENABLE_VOICE_CHAT` | `false` | `true`, `false` | Enable in-game proximity voice chat. |
| `VOICE_CHAT_MODE` | `Proximity` | `Proximity`, `Global` | Whether voice is proximity-based or server-wide. |

### Player

| Variable | Default | Valid Values | Description |
|---|---|---|---|
| `PLAYER_HEALTH_FACTOR` | `1.0` | float > 0 | Player health multiplier. |
| `PLAYER_MANA_FACTOR` | `1.0` | float > 0 | Player mana multiplier. |
| `PLAYER_STAMINA_FACTOR` | `1.0` | float > 0 | Player stamina multiplier. |
| `PLAYER_BODY_HEAT_FACTOR` | `1.0` | float > 0 | Player body heat loss multiplier. |
| `PLAYER_DIVING_TIME_FACTOR` | `1.0` | float > 0 | Underwater breath duration multiplier. |
| `ENABLE_DURABILITY` | `true` | `true`, `false` | Whether equipment takes durability damage. |
| `ENABLE_STARVING_DEBUFF` | `false` | `true`, `false` | Whether players receive a debuff when starving. |
| `FOOD_BUFF_DURATION_FACTOR` | `1.0` | float > 0 | Duration multiplier for food buffs. |
| `FROM_HUNGER_TO_STARVING` | `600000000000` | integer (nanoseconds) | Time before hunger becomes starvation. Default is ~10 minutes. |

### World

| Variable | Default | Valid Values | Description |
|---|---|---|---|
| `SHROUD_TIME_FACTOR` | `1.0` | float > 0 | How quickly the shroud debuff accumulates. |
| `TOMBSTONE_MODE` | `AddBackpackMaterials` | `AddBackpackMaterials`, `Everything`, `NoItems` | What is dropped on death. |
| `ENABLE_GLIDER_TURBULENCES` | `true` | `true`, `false` | Whether wind turbulence affects gliding. |
| `WEATHER_FREQUENCY` | `Normal` | `Rare`, `Normal`, `Often` | How frequently weather events occur. |
| `FISHING_DIFFICULTY` | `Normal` | `Easy`, `Normal`, `Hard` | Fishing minigame difficulty. |
| `CURSE_MODIFIER` | `Normal` | `None`, `Normal`, `Hard` | Intensity of shroud curse effects. |
| `DAY_TIME_DURATION` | `1800000000000` | integer (nanoseconds) | Length of daytime. Default is 30 minutes. |
| `NIGHT_TIME_DURATION` | `720000000000` | integer (nanoseconds) | Length of nighttime. Default is 12 minutes. |

### Economy & Progression

| Variable | Default | Valid Values | Description |
|---|---|---|---|
| `MINING_DAMAGE_FACTOR` | `1.0` | float > 0 | Resource yield from mining. |
| `PLANT_GROWTH_SPEED_FACTOR` | `1.0` | float > 0 | Speed of crop growth. |
| `RESOURCE_DROP_STACK_AMOUNT_FACTOR` | `1.0` | float > 0 | Stack size multiplier for dropped resources. |
| `FACTORY_PRODUCTION_SPEED_FACTOR` | `1.0` | float > 0 | Crafting station speed multiplier. |
| `PERK_UPGRADE_RECYCLING_FACTOR` | `0.5` | 0.0 – 1.0 | Fraction of skill points returned when respeccing. |
| `PERK_COST_FACTOR` | `1.0` | float > 0 | Multiplier for skill point costs. |
| `EXPERIENCE_COMBAT_FACTOR` | `1.0` | float > 0 | XP multiplier from combat. |
| `EXPERIENCE_MINING_FACTOR` | `1.0` | float > 0 | XP multiplier from mining. |
| `EXPERIENCE_EXPLORATION_QUESTS_FACTOR` | `1.0` | float > 0 | XP multiplier from exploration and quests. |

### Enemies

| Variable | Default | Valid Values | Description |
|---|---|---|---|
| `RANDOM_SPAWNER_AMOUNT` | `Normal` | `Few`, `Normal`, `Many`, `Extreme` | Overall enemy density. |
| `AGGRO_POOL_AMOUNT` | `Normal` | `Few`, `Normal`, `Many`, `Extreme` | How many enemies can be simultaneously aggro'd. |
| `ENEMY_DAMAGE_FACTOR` | `1.0` | float > 0 | Enemy outgoing damage multiplier. |
| `ENEMY_HEALTH_FACTOR` | `1.0` | float > 0 | Enemy health multiplier. |
| `ENEMY_STAMINA_FACTOR` | `1.0` | float > 0 | Enemy stamina multiplier. |
| `ENEMY_PERCEPTION_RANGE_FACTOR` | `1.0` | float > 0 | Enemy detection range multiplier. |
| `BOSS_DAMAGE_FACTOR` | `1.0` | float > 0 | Boss outgoing damage multiplier. |
| `BOSS_HEALTH_FACTOR` | `1.0` | float > 0 | Boss health multiplier. |
| `THREAT_BONUS` | `1.0` | float > 0 | Multiplier for threat/aggro generation. |
| `PACIFY_ALL_ENEMIES` | `false` | `true`, `false` | If `true`, all enemies are passive. |
| `TAMING_STARTLE_REPERUSSION` | `LoseSomeProgress` | `LoseSomeProgress`, `LoseAllProgress`, `Nothing` | Consequence when a taming attempt is interrupted. |

### User Group Permissions

Each role (Default, Visitor, Helper, Friend, Admin) can be independently configured. Passwords are in the Secrets section above.

| Variable | Default | Description |
|---|---|---|
| `SET_GROUP_<ROLE>_CAN_KICK_BAN` | `true` | Whether this role can kick/ban other players. |
| `SET_GROUP_<ROLE>_CAN_ACCESS_INVENTORIES` | `true` | Whether this role can open other players' inventories. |

Replace `<ROLE>` with `VISITOR`, `HELPER`, `FRIEND`, or `ADMIN`. The Default role always has `canKickBan: false`.

---

## Operations

### Start the server
```powershell
cd C:\docker\enshrouded-windocker
docker compose up -d
```

### Stop the server
```powershell
docker compose down
```

### Restart the server
```powershell
docker compose restart
```

### View live logs
```powershell
docker logs enshrouded-windocker-enshrouded-1 -f
```

### Rebuild the image (after Dockerfile or entrypoint changes)
```powershell
docker compose build
docker compose up -d --force-recreate
```

### Force a game server update immediately
```powershell
docker compose down
# Ensure UPDATE_ON_START=true in .env (it is true by default)
docker compose up -d
```
Or set `UPDATE_ON_START=false` in `.env` to skip the SteamCMD check on every start — the auto-update schedule will still apply.

### Apply config changes without rebuilding
All settings are in `.env`. Changes only require a container restart — no image rebuild needed:
```powershell
docker compose up -d --force-recreate
```

---

## Copying Save Files to the Server

The server's save data lives in `C:\docker\enshrouded\savegame\` on your host.

Your **local** Enshrouded save files are located at:
```
%LOCALAPPDATA%\Enshrouded\
```

### Copy your local save to the server

> Stop the server first to avoid save corruption.

```powershell
# Stop the server
docker compose down

# Copy save files (adjust the source path to your save folder)
Copy-Item "$env:LOCALAPPDATA\Enshrouded\*" "C:\docker\enshrouded\savegame\" -Recurse -Force

# Start the server
docker compose up -d
```

### Copy a server save back to your local game

```powershell
Copy-Item "C:\docker\enshrouded\savegame\*" "$env:LOCALAPPDATA\Enshrouded\" -Recurse -Force
```

> **Note:** Enshrouded save files use the Steam User ID in the folder path. Make sure the save folder you're copying matches the player(s) who will be loading it.
