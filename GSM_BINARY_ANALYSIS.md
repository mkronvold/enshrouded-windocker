# GSM Binary Analysis Report
## Understanding the Enshrouded Game Server Management Binary

**Binary**: `mbround18/gsm-reference:venshrouded-0.1.6`  
**Location**: `/usr/local/bin/enshrouded`  
**Source Code Location**: Built from `https://github.com/mbround18/game-server-management`

---

## Overview

The GSM binary is a Rust-based game server management tool that orchestrates the Enshrouded server lifecycle. It handles:
- Server installation via SteamCMD
- Configuration management (JSON-based config with environment variable overrides)
- Server startup and process management
- Log monitoring and Discord webhook notifications
- Scheduled tasks (auto-updates and server restarts)

---

## 1. COMMAND STRUCTURE

### Help Output
```
Manage Enshrouded Server

Usage: enshrouded <COMMAND>

Commands:
  install   - Install the Enshrouded server
  start     - Start the server only (without monitoring jobs)
  monitor   - Monitor the server: start the server and then run scheduled jobs and watch logs
  stop      - Stop the server
  restart   - Restart the server
  update    - Update the server
  help      - Print this message or the help of the given subcommand(s)

Options:
  -h, --help     Print help
  -V, --version  Print version
```

### Subcommand Details

#### `enshrouded install [OPTIONS]`
```
Options:
  --path <PATH>  Installation path [default: /home/steam/enshrouded]
  -h, --help     Print help
```

#### `enshrouded start`
- Starts the server only, no monitoring or scheduled jobs
- No additional options

#### `enshrouded monitor [OPTIONS]`
```
Options:
  --update-job   Enable auto-update scheduled job
  --restart-job  Enable scheduled restart job
  -h, --help     Print help
```

#### `enshrouded stop`
- Stops the server
- No additional options

---

## 2. CONFIGURATION GENERATION & ENV VAR HANDLING

### Configuration File Location
**File**: `/home/steam/enshrouded/enshrouded_server.json`

### Configuration Loading Flow
1. Binary attempts to load config from `/home/steam/enshrouded/enshrouded_server.json`
2. If file doesn't exist, creates default config
3. **Applies environment variable overrides** (this is key!)
4. Writes config back to file

### Log Messages (from strings):
- "Loading config from path: "
- "Config loaded: "
- "Config loaded, applying environment overrides"
- "Config changed after env overrides: "
- "Creating backup at: "
- "Saving config to: "
- "Config loading completed."

### Backup Files
- Format: `enshrouded_server.bak.[YYYY-MM-DD-HH.MM.SS].json`
- Example: `enshrouded_server.bak.2026-02-22-11.27.05.json`
- Backups are created before writing new config

---

## 3. ENVIRONMENT VARIABLES FOR GAME SETTINGS

The binary reads the following environment variables and maps them to the JSON config:

### Supported Environment Variables (All Optional)

#### Player Settings
- `PLAYER_HEALTH_FACTOR` → `gameSettings.playerHealthFactor`
- `PLAYER_MANA_FACTOR` → `gameSettings.playerManaFactor`
- `PLAYER_STAMINA_FACTOR` → `gameSettings.playerStaminaFactor`
- `PLAYER_BODY_HEAT_FACTOR` → `gameSettings.playerBodyHeatFactor`

#### Durability & Hunger
- `ENABLE_DURABILITY` → `gameSettings.enableDurability` (boolean: true/false)
- `ENABLE_STARVING_DEBUFF` → `gameSettings.enableStarvingDebuff` (boolean)
- `FOOD_BUFF_DURATION_FACTOR` → `gameSettings.foodBuffDurationFactor`
- `FROM_HUNGER_TO_STARVING` → `gameSettings.fromHungerToStarving`

#### Game World
- `SHROUD_TIME_FACTOR` → `gameSettings.shroudTimeFactor`
- `TOMBSTONE_MODE` → `gameSettings.tombstoneMode` (values: "AddBackpackMaterials", etc.)
- `ENABLE_GLIDER_TURBULENCES` → `gameSettings.enableGliderTurbulences` (boolean)
- `WEATHER_FREQUENCY` → `gameSettings.weatherFrequency` (values: "Normal", etc.)

#### Resource & Production
- `MINING_DAMAGE_FACTOR` → `gameSettings.miningDamageFactor`
- `PLANT_GROWTH_SPEED_FACTOR` → `gameSettings.plantGrowthSpeedFactor`
- `RESOURCE_DROP_STACK_AMOUNT_FACTOR` → `gameSettings.resourceDropStackAmountFactor`
- `FACTORY_PRODUCTION_SPEED_FACTOR` → `gameSettings.factoryProductionSpeedFactor`

#### Perks & Experience
- `PERK_UPGRADE_RECYCLING_FACTOR` → `gameSettings.perkUpgradeRecyclingFactor`
- `PERK_COST_FACTOR` → `gameSettings.perkCostFactor`
- `EXPERIENCE_COMBAT_FACTOR` → `gameSettings.experienceCombatFactor`
- `EXPERIENCE_MINING_FACTOR` → `gameSettings.experienceMiningFactor`
- `EXPERIENCE_EXPLORATION_QUESTS_FACTOR` → `gameSettings.experienceExplorationQuestsFactor`

#### Spawning & Difficulty
- `RANDOM_SPAWNER_AMOUNT` → `gameSettings.randomSpawnerAmount` (values: "Low", "Normal", "High", "Many")
- `AGGRO_POOL_AMOUNT` → `gameSettings.aggroPoolAmount` (values: "Low", "Normal", "High", "Many")

#### Enemy Settings
- `ENEMY_DAMAGE_FACTOR` → `gameSettings.enemyDamageFactor`
- `ENEMY_HEALTH_FACTOR` → `gameSettings.enemyHealthFactor`
- `ENEMY_STAMINA_FACTOR` → `gameSettings.enemyStaminaFactor`
- `ENEMY_PERCEPTION_RANGE_FACTOR` → `gameSettings.enemyPerceptionRangeFactor`

#### Boss Settings
- `BOSS_DAMAGE_FACTOR` → `gameSettings.bossDamageFactor`
- `BOSS_HEALTH_FACTOR` → `gameSettings.bossHealthFactor`

#### Threat & Taming
- `THREAT_BONUS` → `gameSettings.threatBonus`
- `PACIFY_ALL_ENEMIES` → `gameSettings.pacifyAllEnemies` (boolean)
- `TAMING_STARTLE_REPERCUSSION` → `gameSettings.tamingStartleRepercussion` (values: "LoseSomeProgress", etc.)

#### Time Durations
- `DAY_TIME_DURATION` → `gameSettings.dayTimeDuration`
- `NIGHT_TIME_DURATION` → `gameSettings.nightTimeDuration`

### Server Config Variables
- `NAME` → `name` (server name)
- `PLAYER_HEALTH_FACTOR` etc. go into `gameSettings` section

### User Group Variables (SET_GROUP_*)
Format: `SET_GROUP_<GROUP_NAME>_<PERMISSION>`

Examples from docker-compose.yml:
```bash
SET_GROUP_VISITOR_PASSWORD: "ginesh123"
SET_GROUP_VISITOR_CAN_KICK_BAN: "true"
SET_GROUP_VISITOR_CAN_ACCESS_INVENTORIES: "true"

SET_GROUP_HELPER_PASSWORD: "ginesh1234"
SET_GROUP_HELPER_CAN_KICK_BAN: "true"
SET_GROUP_HELPER_CAN_ACCESS_INVENTORIES: "true"

SET_GROUP_FRIEND_PASSWORD: "ginesh12345"
SET_GROUP_FRIEND_CAN_KICK_BAN: "true"
SET_GROUP_FRIEND_CAN_ACCESS_INVENTORIES: "true"

SET_GROUP_ADMIN_PASSWORD: "ginesh"
SET_GROUP_ADMIN_CAN_KICK_BAN: "true"
SET_GROUP_ADMIN_CAN_ACCESS_INVENTORIES: "true"
```

Supported group permissions:
- `<GROUP_NAME>_PASSWORD` → `userGroups[].password`
- `<GROUP_NAME>_CAN_KICK_BAN` → `userGroups[].canKickBan`
- `<GROUP_NAME>_CAN_ACCESS_INVENTORIES` → `userGroups[].canAccessInventories`
- `<GROUP_NAME>_CAN_EDIT_BASE` → `userGroups[].canEditBase`
- `<GROUP_NAME>_CAN_EXTEND_BASE` → `userGroups[].canExtendBase`
- `<GROUP_NAME>_RESERVED_SLOTS` → `userGroups[].reservedSlots`

---

## 4. GENERATED CONFIG JSON FORMAT

### Example Current Config
File: `/home/steam/enshrouded/enshrouded_server.json` (1731 bytes)

```json
{
  "name": "Enshrouded Server",
  "saveDirectory": "./savegame",
  "logDirectory": "./logs",
  "ip": "0.0.0.0",
  "queryPort": 15637,
  "slotCount": 16,
  "voiceChatMode": "Proximity",
  "enableVoiceChat": false,
  "enableTextChat": false,
  "gameSettingsPreset": "Default",
  "gameSettings": {
    "playerHealthFactor": 1.0,
    "playerManaFactor": 1.0,
    "playerStaminaFactor": 1.0,
    "playerBodyHeatFactor": 1.0,
    "enableDurability": true,
    "enableStarvingDebuff": false,
    "foodBuffDurationFactor": 1.0,
    "fromHungerToStarving": 600000000000,
    "shroudTimeFactor": 1.0,
    "tombstoneMode": "AddBackpackMaterials",
    "enableGliderTurbulences": true,
    "weatherFrequency": "Normal",
    "miningDamageFactor": 1.0,
    "plantGrowthSpeedFactor": 1.0,
    "resourceDropStackAmountFactor": 1.0,
    "factoryProductionSpeedFactor": 1.0,
    "perkUpgradeRecyclingFactor": 0.8,
    "perkCostFactor": 1.0,
    "experienceCombatFactor": 1.0,
    "experienceMiningFactor": 1.0,
    "experienceExplorationQuestsFactor": 1.0,
    "randomSpawnerAmount": "Many",
    "aggroPoolAmount": "Normal",
    "enemyDamageFactor": 1.0,
    "enemyHealthFactor": 1.5,
    "enemyStaminaFactor": 0.6,
    "enemyPerceptionRangeFactor": 1.0,
    "bossDamageFactor": 1.0,
    "bossHealthFactor": 2.0,
    "threatBonus": 1.0,
    "pacifyAllEnemies": false,
    "tamingStartleRepercussion": "LoseSomeProgress",
    "dayTimeDuration": 1800000000000,
    "nightTimeDuration": 720000000000
  },
  "userGroups": [
    {
      "name": "Default",
      "password": "",
      "canKickBan": false,
      "canAccessInventories": true,
      "canEditBase": true,
      "canExtendBase": true,
      "reservedSlots": 0
    }
  ],
  "gamePort": 15636
}
```

### Default Values (from strings analysis)
When config doesn't exist, defaults are:
- `name`: "My Enshrouded Server"
- `userGroups[0].name`: "Guest"
- `userGroups[0].password`: "XXXXXXXX"
- `saveDirectory`: "./savegame"
- `logDirectory`: "./logs"
- `ip`: "0.0.0.0"
- `queryPort`: 15637 (Unreal default)
- `voiceChatMode`: "Proximity"

---

## 5. SERVER STARTUP COMMAND

### The Binary Command
```bash
enshrouded_server.exe
```

### Launch Details
- **Location**: `/home/steam/enshrouded/enshrouded_server.exe`
- **Size**: ~22MB (22028800 bytes)
- **Binary Type**: Windows PE executable (run via Wine/Proton)
- **Startup Method**: `wine` or `proton` (from the docker container)

### Process Management
- Binary writes a **PID file** at: `/home/steam/enshrouded/instance.pid`
- The GSM binary wraps the server process with mutex locks for thread-safe management
- Log messages:
  - "Instance configuration set: "
  - "Instance created and wrapped in Arc<Mutex<>>"
  - "Starting server..."
  - "Acquiring lock for installation..."
  - "Server started successfully."
  - "Failed to start server: "

---

## 6. THE MONITOR JOB

### What Monitor Does
The `enshrouded monitor` command runs:
1. **Starts the server** (if not already running)
2. **Enters a cron loop** that watches for scheduled tasks and log events
3. **Sends Discord webhook notifications** on specific events
4. **Runs auto-update job** (if enabled)
5. **Runs scheduled restart job** (if enabled)
6. **Watches log files** in real-time

### Monitor Log Messages
```
Entering cron loop (monitoring logs and scheduled tasks)...
Starting watch on [log file path]
Processing rules for line: [log line]
```

### Discord Webhook Integration

#### Webhook Configuration
- **Env Var**: `WEBHOOK_URL`
- **Format**: Must be valid Discord webhook URL
- **Example**: `https://discord.com/api/webhooks/1475158831322370118/UdPD0CdTH_fTJSNaxN1lcsBJL83Key6ErZSK_5XYxs3xQsG828viuDv9lc_PXT_K90ec`

#### Webhook Events Sent
The binary sends Discord embeds for these events:

1. **Player Joined**
   - Message: "Player [NAME] has joined the adventure!"
   - Extracted from logs via regex: `Player\s+'([^']+)'`

2. **Player Left**
   - Message: "Player [NAME] has left the adventure."
   - Also extracted from server logs

3. **Server Started**
   - Message: "The server has started successfully."

4. **Server Stopping**
   - Message: "The server is shutting down gracefully."

5. **Server Stopped**
   - Message: "The server has been stopped."

#### Discord Embed Structure (from binary)
The binary constructs Discord embeds with:
- `notification_type` - Event type
- `title` - Human-readable title
- `description` - Event details
- `color` - Embed color (alert/info)
- `content` - Message content
- `embeds` - Array of embed objects

#### Error Handling
- "Failed to send webhook event! Invalid url?"
- "Skipping notification, WEBHOOK_URL is not present."
- If WEBHOOK_URL is not set, notifications are silently skipped

---

### Auto-Update Job

#### Configuration
- **Env Var**: `AUTO_UPDATE` (boolean: true/false)
- **Schedule Env Var**: `AUTO_UPDATE_SCHEDULE` (cron format)
- **Default Schedule**: `0 3 * * *` (3 AM daily)

#### Job Messages
```
Auto-update job not enabled.                    [if AUTO_UPDATE=false]
Auto-update job condition met.                  [when scheduled time triggers]
Auto-update schedule: auto-update
Checking for updates without enforcing check flag...
Server is up to date; no update needed.
Update available! Updating...
Update failed: [error]
Update applied successfully.
```

#### Update Process
1. Checks for updates via SteamCMD
2. If update available, stops server
3. Applies update
4. Restarts server
5. Sends Discord webhook notification

---

### Scheduled Restart Job

#### Configuration
- **Env Var**: `SCHEDULED_RESTART` (boolean: true/false)
- **Schedule Env Var**: `SCHEDULED_RESTART_SCHEDULE` (cron format)
- **Default Schedule**: `0 4 * * *` (4 AM daily)

#### Job Messages
```
Scheduled restart job not enabled.              [if SCHEDULED_RESTART=false]
Scheduled restart job condition met.            [when scheduled time triggers]
Scheduled restart schedule: scheduled-restart
Scheduled restart job triggered.
Restarting Enshrouded server...
Acquiring lock to restart the server...
Server restarted successfully.
Failed to restart server: [error]
```

#### Stop/Restart Behavior
- **Env Var**: `STOP_DELAY` (optional, in seconds)
- Default behavior: Graceful shutdown
- Error: "Invalid STOP_DELAY value: "

---

### Log Monitoring

#### Log Files Monitored
- `server.log` - Main server output
- `server.err` - Server errors

#### Log Monitoring Features
- Real-time file watching with inotify (Linux)
- Handles log rotation/truncation automatically
- Log messages:
  - "Starting instance log monitor for logs in: "
  - "Starting watch on [file]"
  - "Log file [path] was truncated/rotated. Re-opening."
  - "Successfully reopened log file"
  - "Failed to seek to end of [file]"
  - "Read line from file: [line]"

#### Log Rule Processing
- Computes default ranking for rules
- Applies rule actions (webhook notifications) to matching log lines
- Messages:
  - "Creating default LogRule"
  - "Creating new LogRule"
  - "Processing rules for line: "
  - "Sorted rules count: [N]"

---

## 7. ENTRYPOINT BEHAVIOR (docker-compose integration)

The container runs `/home/steam/scripts/entrypoint.sh` which:

```bash
# 1. Display system info
# 2. Create /home/steam/enshrouded if needed
# 3. Set up Wine environment
# 4. Start virtual display (Xvfb)
# 5. Initialize Wine prefix
# 6. Clean cache
# 7. Run SteamCMD

# 8. If UPDATE_ON_START=true OR enshrouded_server.exe doesn't exist:
if [ "${UPDATE_ON_START:-"false"}" = "true" ] || [ ! -f "/home/steam/enshrouded/enshrouded_server.exe" ]; then
  enshrouded install
fi

# 9. Start server (FOREGROUND - blocking)
enshrouded start

# 10. Start monitor in background
enshrouded monitor &

# 11. Wait for monitor to exit (gracefully handle SIGTERM/SIGINT)
```

---

## 8. ENVIRONMENT VARIABLES SUMMARY

### Core Variables
| Variable | Purpose | Default |
|----------|---------|---------|
| `WEBHOOK_URL` | Discord webhook for notifications | (optional) |
| `AUTO_UPDATE` | Enable auto-update job | false |
| `AUTO_UPDATE_SCHEDULE` | Cron schedule for updates | `0 3 * * *` |
| `SCHEDULED_RESTART` | Enable scheduled restarts | false |
| `SCHEDULED_RESTART_SCHEDULE` | Cron schedule for restarts | `0 4 * * *` |
| `STOP_DELAY` | Delay before stopping server (seconds) | (optional) |
| `UPDATE_ON_START` | Force update/install on startup | false |
| `TZ` | Timezone for logging | America/Los_Angeles |

### Cron Format
- Field 1: Second (0-59)
- Field 2: Minute (0-59)
- Field 3: Hour (0-23)
- Field 4: Day of month (1-31)
- Field 5: Month (1-12)
- Field 6: Day of week (0-7, 0=Sunday)

Example: `0 3 * * *` = Every day at 3:00 AM

---

## 9. SOURCE CODE LOCATIONS (from binary strings)

The binary was compiled from:
- `/home/runner/work/game-server-management/game-server-management/`

Key source modules:
- `libs/gsm-instance/src/install.rs` - Installation logic
- `libs/gsm-instance/src/startup.rs` - Server startup
- `libs/gsm-instance/src/process.rs` - Process management
- `libs/gsm-instance/src/shutdown.rs` - Graceful shutdown
- `libs/gsm-instance/src/update.rs` - Update logic via SteamCMD
- `apps/enshrouded/src/game_settings.rs` - Config & game settings
- `apps/enshrouded/src/utils/config_io.rs` - Config file I/O
- `apps/enshrouded/src/utils/extract_player_name.rs` - Player name parsing
- `libs/gsm-monitor/src/monitor.rs` - Monitoring & scheduling
- `libs/gsm-monitor/src/rules.rs` - Log rule processing
- `libs/gsm-notifications/src/notifications.rs` - Discord webhook sender
- `libs/gsm-cron/src/cron_loop.rs` - Cron scheduler

---

## 10. KEY IMPLEMENTATION NOTES

### Configuration Behavior
- On first run, binary creates default config if none exists
- On every run, **environment variables override** the JSON file values
- Before saving, creates timestamped backup
- If config parsing fails, uses hardcoded defaults instead

### Process Safety
- Uses `Arc<Mutex<>>` for thread-safe process wrapping
- Mutex locks prevent concurrent operations (install, restart, stop)
- Messages: "Acquiring lock for installation...", "Acquiring lock to restart..."

### Error Handling
- Detailed error messages for common issues:
  - "Invalid STOP_DELAY value: "
  - "Failed to send webhook event! Invalid url?"
  - "Failed to start server: "
  - "Failed to restart server: "
  - "Update failed: "

### Graceful Shutdown
- Responds to SIGTERM and SIGINT signals
- Calls `enshrouded stop` before exiting
- Cleans up child processes (monitor, Xvfb)

---

## 11. FULL WORKFLOW EXAMPLE

```
Container Start
    ↓
Entrypoint Script
    ↓
Wine Setup & SteamCMD Init
    ↓
Check: Does enshrouded_server.exe exist?
    ├─ NO: Run `enshrouded install` (downloads via SteamCMD)
    └─ YES: Continue
    ↓
Run `enshrouded start` (Starts server, FOREGROUND)
    ├─ Load/Create config at /home/steam/enshrouded/enshrouded_server.json
    ├─ Apply environment variable overrides
    ├─ Launch enshrouded_server.exe via wine
    └─ Write PID to instance.pid
    ↓
Run `enshrouded monitor` (BACKGROUND)
    ├─ Watch server.log and server.err
    ├─ Send Discord webhooks for player join/leave/server events
    ├─ If AUTO_UPDATE=true: Check for updates at 3 AM daily
    ├─ If SCHEDULED_RESTART=true: Restart server at 4 AM daily
    └─ Continue monitoring logs and running scheduled tasks
    ↓
On SIGTERM/SIGINT:
    ├─ Call `enshrouded stop`
    ├─ Kill monitor process
    ├─ Kill Xvfb process
    └─ Exit
```

---

## File Sizes & Checksums

| File | Size | Type |
|------|------|------|
| enshrouded_server.exe | 22,028,800 bytes | Windows PE binary |
| enshrouded_server.kfc | 2,396,160 bytes | KFC compressed (Unreal) |
| enshrouded_server.kfc_resources | 209,317,888 bytes | Game resources |
| enshrouded_server.json | 1,731 bytes | Configuration |
| enshrouded_server.bak.*.json | ~419 bytes | Backup config |
| instance.pid | 3 bytes | Process ID |

---

**Report Generated**: 2025-02-22  
**Binary Version**: venshrouded-0.1.6  
**Source Repository**: github.com/mbround18/game-server-management
