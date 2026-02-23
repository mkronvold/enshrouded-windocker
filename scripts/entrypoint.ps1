#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ===================================================================
# Enshrouded Dedicated Server - Windows Container Entrypoint
# ===================================================================

$ServerDir   = "C:\enshrouded"
$SteamCmdExe = "C:\steamcmd\steamcmd.exe"
$AppId       = 2278520
$ConfigFile  = "$ServerDir\enshrouded_server.json"
$ServerExe   = "$ServerDir\enshrouded_server.exe"

# ??? Helpers ????????????????????????????????????????????????????????

function Get-Env([string]$name, $default) {
    $val = [System.Environment]::GetEnvironmentVariable($name)
    if ($null -ne $val -and $val -ne '') { return $val } else { return $default }
}
function Get-FloatEnv([string]$name, [double]$default) {
    $val = [System.Environment]::GetEnvironmentVariable($name)
    if ($val) { return [double]$val } else { return $default }
}
function Get-BoolEnv([string]$name, [bool]$default) {
    $val = [System.Environment]::GetEnvironmentVariable($name)
    if ($val) { return ($val -eq 'true') } else { return $default }
}
function Get-LongEnv([string]$name, [long]$default) {
    $val = [System.Environment]::GetEnvironmentVariable($name)
    if ($val) { return [long]$val } else { return $default }
}

# ??? Discord Webhook ????????????????????????????????????????????????

function Send-Webhook([string]$message) {
    if (-not $env:WEBHOOK_URL) { return }
    try {
        $body = @{ content = $message } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $env:WEBHOOK_URL -Method Post -Body $body -ContentType 'application/json' | Out-Null
    } catch {
        Write-Warning "Webhook failed: $_"
    }
}

# ??? User Groups ????????????????????????????????????????????????????

function Build-UserGroups {
    $groups = @(
        [ordered]@{
            name                 = "Default"
            password             = (Get-Env "SET_GROUP_DEFAULT_PASSWORD" "")
            canKickBan           = $false
            canAccessInventories = $true
            canEditWorld         = $true
            canEditBase          = $true
            canExtendBase        = $true
            reservedSlots        = 0
        }
    )
    foreach ($gname in @("VISITOR", "HELPER", "FRIEND", "ADMIN")) {
        $pw = [System.Environment]::GetEnvironmentVariable("SET_GROUP_${gname}_PASSWORD")
        if ($pw) {
            $displayName = $gname.Substring(0,1) + $gname.Substring(1).ToLower()
            $groups += [ordered]@{
                name                 = $displayName
                password             = $pw
                canKickBan           = (Get-BoolEnv "SET_GROUP_${gname}_CAN_KICK_BAN" $false)
                canAccessInventories = (Get-BoolEnv "SET_GROUP_${gname}_CAN_ACCESS_INVENTORIES" $true)
                canEditWorld         = $true
                canEditBase          = $true
                canExtendBase        = $true
                reservedSlots        = 0
            }
        }
    }
    return $groups
}

# --- Config Generation -------------------------------------------------------

function Fix-JsonFloats([string]$json) {
    # PowerShell ConvertTo-Json serializes 1.0 as 1; Enshrouded expects floats
    $floatFields = 'playerHealthFactor|playerManaFactor|playerStaminaFactor|playerBodyHeatFactor|' +
                   'playerDivingTimeFactor|' +
                   'foodBuffDurationFactor|shroudTimeFactor|miningDamageFactor|plantGrowthSpeedFactor|' +
                   'resourceDropStackAmountFactor|factoryProductionSpeedFactor|perkUpgradeRecyclingFactor|' +
                   'perkCostFactor|experienceCombatFactor|experienceMiningFactor|experienceExplorationQuestsFactor|' +
                   'enemyDamageFactor|enemyHealthFactor|enemyStaminaFactor|enemyPerceptionRangeFactor|' +
                   'bossDamageFactor|bossHealthFactor|threatBonus'
    return [System.Text.RegularExpressions.Regex]::Replace(
        $json,
        "(""(?:$floatFields)"": )(\d+)(?![.\d])",
        '$1$2.0'
    )
}

function Write-ServerConfig {
    $config = [ordered]@{
        name                = Get-Env 'NAME' 'Enshrouded Server'
        saveDirectory       = "./savegame"
        logDirectory        = "./logs"
        ip                  = "0.0.0.0"
        queryPort           = [int](Get-Env 'QUERY_PORT' '15637')
        slotCount           = [int](Get-Env 'SLOT_COUNT' '16')
        tags                = @()
        voiceChatMode       = "Proximity"
        enableVoiceChat     = $false
        enableTextChat      = $false
        gameSettingsPreset  = "Custom"
        gameSettings     = [ordered]@{
            playerHealthFactor                = Get-FloatEnv 'PLAYER_HEALTH_FACTOR' 1.0
            playerManaFactor                  = Get-FloatEnv 'PLAYER_MANA_FACTOR' 1.0
            playerStaminaFactor               = Get-FloatEnv 'PLAYER_STAMINA_FACTOR' 1.0
            playerBodyHeatFactor              = Get-FloatEnv 'PLAYER_BODY_HEAT_FACTOR' 1.0
            playerDivingTimeFactor            = Get-FloatEnv 'PLAYER_DIVING_TIME_FACTOR' 1.0
            enableDurability                  = Get-BoolEnv  'ENABLE_DURABILITY' $true
            enableStarvingDebuff              = Get-BoolEnv  'ENABLE_STARVING_DEBUFF' $false
            foodBuffDurationFactor            = Get-FloatEnv 'FOOD_BUFF_DURATION_FACTOR' 1.0
            fromHungerToStarving              = Get-LongEnv  'FROM_HUNGER_TO_STARVING' 600000000000
            shroudTimeFactor                  = Get-FloatEnv 'SHROUD_TIME_FACTOR' 1.0
            tombstoneMode                     = Get-Env      'TOMBSTONE_MODE' 'AddBackpackMaterials'
            enableGliderTurbulences           = Get-BoolEnv  'ENABLE_GLIDER_TURBULENCES' $true
            weatherFrequency                  = Get-Env      'WEATHER_FREQUENCY' 'Normal'
            fishingDifficulty                 = Get-Env      'FISHING_DIFFICULTY' 'Normal'
            miningDamageFactor                = Get-FloatEnv 'MINING_DAMAGE_FACTOR' 1.0
            plantGrowthSpeedFactor            = Get-FloatEnv 'PLANT_GROWTH_SPEED_FACTOR' 1.0
            resourceDropStackAmountFactor     = Get-FloatEnv 'RESOURCE_DROP_STACK_AMOUNT_FACTOR' 1.0
            factoryProductionSpeedFactor      = Get-FloatEnv 'FACTORY_PRODUCTION_SPEED_FACTOR' 1.0
            perkUpgradeRecyclingFactor        = Get-FloatEnv 'PERK_UPGRADE_RECYCLING_FACTOR' 0.5
            perkCostFactor                    = Get-FloatEnv 'PERK_COST_FACTOR' 1.0
            experienceCombatFactor            = Get-FloatEnv 'EXPERIENCE_COMBAT_FACTOR' 1.0
            experienceMiningFactor            = Get-FloatEnv 'EXPERIENCE_MINING_FACTOR' 1.0
            experienceExplorationQuestsFactor = Get-FloatEnv 'EXPERIENCE_EXPLORATION_QUESTS_FACTOR' 1.0
            randomSpawnerAmount               = Get-Env      'RANDOM_SPAWNER_AMOUNT' 'Normal'
            aggroPoolAmount                   = Get-Env      'AGGRO_POOL_AMOUNT' 'Normal'
            enemyDamageFactor                 = Get-FloatEnv 'ENEMY_DAMAGE_FACTOR' 1.0
            enemyHealthFactor                 = Get-FloatEnv 'ENEMY_HEALTH_FACTOR' 1.0
            enemyStaminaFactor                = Get-FloatEnv 'ENEMY_STAMINA_FACTOR' 1.0
            enemyPerceptionRangeFactor        = Get-FloatEnv 'ENEMY_PERCEPTION_RANGE_FACTOR' 1.0
            bossDamageFactor                  = Get-FloatEnv 'BOSS_DAMAGE_FACTOR' 1.0
            bossHealthFactor                  = Get-FloatEnv 'BOSS_HEALTH_FACTOR' 1.0
            threatBonus                       = Get-FloatEnv 'THREAT_BONUS' 1.0
            pacifyAllEnemies                  = Get-BoolEnv  'PACIFY_ALL_ENEMIES' $false
            tamingStartleRepercussion         = Get-Env      'TAMING_STARTLE_REPERUSSION' 'LoseSomeProgress'
            dayTimeDuration                   = Get-LongEnv  'DAY_TIME_DURATION' 1800000000000
            nightTimeDuration                 = Get-LongEnv  'NIGHT_TIME_DURATION' 720000000000
            curseModifier                     = Get-Env      'CURSE_MODIFIER' 'Normal'
        }
        userGroups     = @(Build-UserGroups)
        gamePort       = [int](Get-Env 'GAME_PORT' '15636')
        bannedAccounts = @()
    }

    $json = $config | ConvertTo-Json -Depth 10
    $json = Fix-JsonFloats $json
    [System.IO.File]::WriteAllText($ConfigFile, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[OK] Config written to $ConfigFile"
}

# ??? SteamCMD Install/Update ????????????????????????????????????????

function Invoke-ServerInstall {
    Write-Host "[DL]  Installing/Updating Enshrouded server (App $AppId)..."
    & $SteamCmdExe +login anonymous +force_install_dir $ServerDir +app_update $AppId +quit
    if ($LASTEXITCODE -ne 0) { throw "SteamCMD failed with exit code $LASTEXITCODE" }
    Write-Host "[OK] Server installed/updated."
}

# ??? Cron-style Schedule Check ??????????????????????????????????????

function Test-ScheduleDue([string]$schedule, [datetime]$lastRun) {
    # Supports "MIN HOUR * * *" format
    $parts  = $schedule -split '\s+'
    $minute = [int]$parts[0]
    $hour   = [int]$parts[1]
    $now    = Get-Date
    $target = $now.Date.AddHours($hour).AddMinutes($minute)
    return ($now -ge $target -and $lastRun.Date -lt $now.Date)
}

# ===================================================================
# Main
# ===================================================================

Write-Host "=========================================================="
Write-Host ">> Enshrouded Dedicated Server - $(Get-Date -Format 'u')"
Write-Host "=========================================================="

# Ensure directories exist
New-Item -ItemType Directory -Path "$ServerDir\logs"    -Force | Out-Null
New-Item -ItemType Directory -Path "$ServerDir\savegame" -Force | Out-Null

# Install/update server if binary missing or UPDATE_ON_START is true
if ((Get-Env 'UPDATE_ON_START' 'true') -eq 'true' -or -not (Test-Path $ServerExe)) {
    Invoke-ServerInstall
}

# Generate server config from environment variables
Write-Host "[CFG]  Generating server config..."
Write-ServerConfig

# Start server process
Write-Host "[START] Starting Enshrouded server..."
Send-Webhook "[UP] **$(Get-Env 'NAME' 'Enshrouded Server')** is starting..."

$proc = Start-Process -FilePath $ServerExe -WorkingDirectory $ServerDir -PassThru -NoNewWindow
Write-Host "[OK] Server started (PID $($proc.Id))"
Send-Webhook "[OK] **$(Get-Env 'NAME' 'Enshrouded Server')** is online on port $(Get-Env 'GAME_PORT' '15636')!"

# ??? Monitor Loop ???????????????????????????????????????????????????

$lastAutoUpdate       = Get-Date
$lastScheduledRestart = Get-Date

while (-not $proc.HasExited) {
    Start-Sleep -Seconds 30

    # Auto-update
    if ((Get-Env 'AUTO_UPDATE' 'true') -eq 'true') {
        $schedule = Get-Env 'AUTO_UPDATE_SCHEDULE' '0 3 * * *'
        if (Test-ScheduleDue $schedule $lastAutoUpdate) {
            Write-Host "[UPDATE] Auto-update triggered at $(Get-Date -Format 'u')..."
            Send-Webhook "[UPDATE] **$(Get-Env 'NAME' 'Enshrouded Server')** checking for updates, restarting shortly..."
            $proc.Kill(); $proc.WaitForExit(10000) | Out-Null
            Invoke-ServerInstall
            Write-ServerConfig
            $proc = Start-Process -FilePath $ServerExe -WorkingDirectory $ServerDir -PassThru -NoNewWindow
            $lastAutoUpdate = Get-Date
            Send-Webhook "[OK] **$(Get-Env 'NAME' 'Enshrouded Server')** restarted after update."
        }
    }

    # Scheduled restart
    if ((Get-Env 'SCHEDULED_RESTART' 'true') -eq 'true') {
        $schedule = Get-Env 'SCHEDULED_RESTART_SCHEDULE' '0 4 * * *'
        if (Test-ScheduleDue $schedule $lastScheduledRestart) {
            Write-Host "[RESTART] Scheduled restart triggered at $(Get-Date -Format 'u')..."
            Send-Webhook "[RESTART] **$(Get-Env 'NAME' 'Enshrouded Server')** performing scheduled restart..."
            $proc.Kill(); $proc.WaitForExit(10000) | Out-Null
            $proc = Start-Process -FilePath $ServerExe -WorkingDirectory $ServerDir -PassThru -NoNewWindow
            $lastScheduledRestart = Get-Date
            Send-Webhook "[OK] **$(Get-Env 'NAME' 'Enshrouded Server')** restarted."
        }
    }
}

$exitCode = $proc.ExitCode
Write-Host "[WARN]  Server process exited with code $exitCode"
Send-Webhook "[DOWN] **$(Get-Env 'NAME' 'Enshrouded Server')** has stopped (exit code: $exitCode)"
exit $exitCode
