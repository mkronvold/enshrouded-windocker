#Requires -Version 5.0
param(
    [ValidateSet("windows", "linux", "wsl", "auto")]
    [string]$Variant = "auto"
)

$ErrorActionPreference = "Stop"
$script:StatsCache = $null
$script:StatsCacheTime = 0
$script:CacheExpiry = 10  # Cache stats for 10 seconds

$ComposeFile = "C:\docker\enshrouded-docker\docker-compose.yml"

# Active variant config - populated by Initialize-Variant
$script:ServiceName    = ""
$script:ContainerName  = ""
$script:ComposeProfile = ""

function Initialize-Variant {
    param([string]$VariantName)
    $script:ActiveVariant = $VariantName
    if ($VariantName -eq "linux" -or $VariantName -eq "wsl") {
        $script:ServiceName    = "enshrouded-linux"
        $script:ContainerName  = "enshrouded-docker-enshrouded-linux-1"
        $script:ComposeProfile = "linux"
        $script:WslDistro      = if ($VariantName -eq "wsl") { Get-WslDistro } else { "" }
    } else {
        $script:ServiceName    = "enshrouded"
        $script:ContainerName  = "enshrouded-docker-enshrouded-1"
        $script:ComposeProfile = ""
        $script:WslDistro      = ""
    }
    $script:StatsCache = $null
}

function Get-WslDistro {
    try {
        # wsl --list --quiet can emit UTF-16 with embedded null chars; strip them
        $distros = (& wsl --list --quiet 2>$null) |
            ForEach-Object { ($_ -replace '\x00', '').Trim() } |
            Where-Object { $_ -ne '' }
        $ubuntu = $distros | Where-Object { $_ -match '^Ubuntu' } | Select-Object -First 1
        if ($ubuntu) { return $ubuntu }
    } catch {}
    return "Ubuntu"
}

function ConvertTo-WslPath {
    param([string]$WinPath)
    if ($WinPath -match '^([A-Za-z]):\\') {
        return "/mnt/$($Matches[1].ToLower())$($WinPath.Substring(2) -replace '\\', '/')"
    }
    return $WinPath -replace '\\', '/'
}

# Routes a bare 'docker ...' call through WSL when the wsl variant is active.
function Invoke-Docker {
    param([string[]]$DockerArgs)
    if ($script:WslDistro) {
        return & wsl -d $script:WslDistro -- docker @DockerArgs
    }
    return & docker @DockerArgs
}

function Invoke-Compose {
    param([string[]]$SubArgs)
    $profileArgs = if ($script:ComposeProfile) { @("--profile", $script:ComposeProfile) } else { @() }
    if ($script:WslDistro) {
        $wslPath = ConvertTo-WslPath $ComposeFile
        & wsl -d $script:WslDistro -- docker compose -f $wslPath @profileArgs @SubArgs
    } else {
        & docker compose -f $ComposeFile @profileArgs @SubArgs
    }
}

# Returns the YAML block belonging to the active service, applies a transform
# scriptblock, and splices the result back into the full document.
function Edit-ServiceBlock {
    param([string]$Yaml, [scriptblock]$Transform)
    $escaped = [regex]::Escape($script:ServiceName)
    $m = [regex]::Match($Yaml, "(?s)  ${escaped}:.*?(?=\n  [a-zA-Z_-]|\z)")
    if ($m.Success) {
        $newBlock = & $Transform $m.Value
        return $Yaml.Substring(0, $m.Index) + $newBlock + $Yaml.Substring($m.Index + $m.Length)
    }
    return & $Transform $Yaml  # fallback: transform full document
}

# Graceful exit on Ctrl+C
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Host "`n`nExiting..." -ForegroundColor Yellow
    exit 0
}

function Read-SingleKey {
    param([string]$Prompt = "")
    if ($Prompt) { Write-Host $Prompt -NoNewline }
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    return $key.Character
}

function Get-DockerMode {
    try {
        $osType = & docker info --format '{{.OSType}}' 2>$null
        if ($osType -match 'windows') { return "windows" }
        return "linux"
    }
    catch {
        return "windows"  # safe fallback
    }
}

# Warns the user if the selected variant doesn't match Docker Desktop's current
# container mode. Returns $true to proceed, $false to cancel.
function Confirm-VariantCompatible {
    # WSL variant uses its own Docker daemon — Docker Desktop mode is irrelevant
    if ($script:ActiveVariant -eq "wsl") { return $true }

    $dockerMode = Get-DockerMode
    if ($script:ActiveVariant -eq $dockerMode) { return $true }

    $modeLabel    = if ($dockerMode -eq "linux") { "Linux" } else { "Windows" }
    $variantLabel = if ($script:ActiveVariant -eq "linux") { "Linux/Wine" } else { "Windows" }
    Write-Host ""
    Write-Host "⚠  WARNING: Docker Desktop is in $modeLabel container mode," -ForegroundColor Red
    Write-Host "   but the active variant is $variantLabel." -ForegroundColor Red
    Write-Host "   This operation will likely fail." -ForegroundColor Red
    Write-Host ""
    Write-Host "Continue anyway? (y/n)" -ForegroundColor Yellow
    $confirm = Read-SingleKey " "
    Write-Host $confirm
    return ($confirm -eq "y" -or $confirm -eq "Y")
}


function Select-Variant {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Enshrouded — Select Image    ║" -ForegroundColor Cyan
    Write-Host "╠═══════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ 1 - Windows  (Server Core)    ║" -ForegroundColor Cyan
    Write-Host "║ 2 - Linux    (Ubuntu + Wine)  ║" -ForegroundColor Cyan
    Write-Host "║ 3 - WSL2     (Ubuntu + Wine)  ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    while ($true) {
        $key = Read-SingleKey "Select variant (1/2/3): "
        Write-Host $key
        switch ($key) {
            "1" { Initialize-Variant "windows"; return }
            "2" { Initialize-Variant "linux";   return }
            "3" { Initialize-Variant "wsl";     return }
            default { Write-Host "Please press 1, 2, or 3." -ForegroundColor Red }
        }
    }
}

function Get-ContainerStats {
    param([switch]$Force)

    $now = [datetime]::UtcNow.Ticks

    # Return cached stats if still valid
    if (-not $Force -and $script:StatsCache -and (($now - $script:StatsCacheTime) / 10000000) -lt $script:CacheExpiry) {
        return $script:StatsCache
    }

    try {
        $container = Invoke-Docker @("inspect", $script:ContainerName) 2>$null | ConvertFrom-Json

        if (-not $container) {
            $stats = @{
                CpuUsage   = "N/A"
                CpuCores   = "N/A"
                CpuThreads = "4"
                CpuLimit   = "N/A"
                MemUsed    = "N/A"
                MemFree    = "N/A"
                MemTotal   = "N/A"
                MemLimit   = "N/A"
                IsRunning  = $false
            }
            $script:StatsCache = $stats
            $script:StatsCacheTime = $now
            return $stats
        }

        # Parse resource limits for the active service from docker-compose.yml
        $composeContent = Get-Content $ComposeFile -Raw
        $svcEscaped = [regex]::Escape($script:ServiceName)
        $svcMatch   = [regex]::Match($composeContent, "(?s)  ${svcEscaped}:.*?(?=\n  [a-zA-Z_-]|\z)")
        $svcBlock   = if ($svcMatch.Success) { $svcMatch.Value } else { $composeContent }

        $cpuLimitMatch = [regex]::Match($svcBlock, "cpus:\s*[''`"]?([0-9.]+)[''`"]?")
        $cpuLimit = if ($cpuLimitMatch.Success) { $cpuLimitMatch.Groups[1].Value } else { "Unlimited" }

        $memLimitMatch = [regex]::Match($svcBlock, "memory:\s*[''`"]?([0-9.]+)([a-zA-Z]+)[''`"]?")
        $memLimit = if ($memLimitMatch.Success) {
            "$($memLimitMatch.Groups[1].Value)$($memLimitMatch.Groups[2].Value)"
        } else { "Unlimited" }

        $cpuCores   = "4"
        $cpuThreads = "4"
        $cpuUsage   = "N/A"
        $memUsed    = "N/A"
        $memFree    = "N/A"
        $memTotal   = "N/A"

        if ($container.State.Running) {
            try {
                if ($script:ActiveVariant -eq "linux" -or $script:ActiveVariant -eq "wsl") {
                    # CPU core count (nproc = logical processors)
                    $cpuCoresRaw = Invoke-Docker @("exec", $script:ContainerName, "bash", "-c", "nproc --all") 2>$null
                    if ($cpuCoresRaw) {
                        $cpuCores   = ($cpuCoresRaw | Select-Object -Last 1).Trim()
                        $cpuThreads = $cpuCores
                    }

                    # CPU usage: two /proc/stat samples 500 ms apart via python3
                    $cpuUsageRaw = Invoke-Docker @("exec", $script:ContainerName, "python3", "-c", 'import time;f=open("/proc/stat");l1=f.readline().split();f.close();time.sleep(0.5);f=open("/proc/stat");l2=f.readline().split();f.close();v1=[int(x) for x in l1[1:8]];v2=[int(x) for x in l2[1:8]];d=[v2[i]-v1[i] for i in range(len(v1))];t=sum(d);print(round(100*(t-d[3])/t,2) if t>0 else 0)') 2>$null
                    if ($cpuUsageRaw) {
                        $cpuUsage = ($cpuUsageRaw | Select-Object -Last 1).Trim()
                    }

                    # Memory from /proc/meminfo (kB → GB), parsed in PowerShell
                    $memRaw = Invoke-Docker @("exec", $script:ContainerName, "bash", "-c", 'grep -E "^MemTotal:|^MemFree:" /proc/meminfo') 2>$null
                    if ($memRaw) {
                        $memLines    = $memRaw -split "`n" | Where-Object { $_ -match '\d' }
                        $memTotalKB  = [double](($memLines | Where-Object { $_ -match '^MemTotal' }) -replace '[^0-9]', '')
                        $memFreeKB   = [double](($memLines | Where-Object { $_ -match '^MemFree'  }) -replace '[^0-9]', '')
                        $memTotal    = [math]::Round($memTotalKB / 1048576, 2)
                        $memFree     = [math]::Round($memFreeKB  / 1048576, 2)
                        $memUsed     = [math]::Round($memTotal - $memFree, 2)
                    }
                } else {
                    # Windows container stats via PowerShell inside container
                    $cpuCmd = Invoke-Docker @("exec", $script:ContainerName, "powershell", "-NoProfile", "-Command", "(Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue") 2>$null
                    if ($cpuCmd) {
                        $cpuUsage = [math]::Round([double]($cpuCmd | Select-Object -Last 1), 2)
                    }

                    $coresCmd   = Invoke-Docker @("exec", $script:ContainerName, "powershell", "-NoProfile", "-Command", "(Get-CimInstance Win32_Processor).NumberOfCores") 2>$null
                    $threadsCmd = Invoke-Docker @("exec", $script:ContainerName, "powershell", "-NoProfile", "-Command", "(Get-CimInstance Win32_Processor).NumberOfLogicalProcessors") 2>$null
                    if ($coresCmd)   { $cpuCores   = $coresCmd   | Select-Object -Last 1 }
                    if ($threadsCmd) { $cpuThreads = $threadsCmd | Select-Object -Last 1 }

                    $memFreeCmd  = Invoke-Docker @("exec", $script:ContainerName, "powershell", "-NoProfile", "-Command", "([math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB / 1024, 2))") 2>$null
                    $memTotalCmd = Invoke-Docker @("exec", $script:ContainerName, "powershell", "-NoProfile", "-Command", "([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2))") 2>$null

                    if ($memFreeCmd -and $memTotalCmd) {
                        $memFree  = [double]($memFreeCmd  | Select-Object -Last 1)
                        $memTotal = [double]($memTotalCmd | Select-Object -Last 1)
                        $memUsed  = [math]::Round($memTotal - $memFree, 2)
                    }
                }
            }
            catch {
                # If exec fails, leave stats as N/A
            }
        }

        $stats = @{
            CpuUsage   = $cpuUsage
            CpuCores   = $cpuCores
            CpuThreads = $cpuThreads
            CpuLimit   = $cpuLimit
            MemUsed    = $memUsed
            MemFree    = $memFree
            MemTotal   = $memTotal
            MemLimit   = $memLimit
            IsRunning  = $container.State.Running
        }

        $script:StatsCache = $stats
        $script:StatsCacheTime = $now
        return $stats
    }
    catch {
        $stats = @{
            CpuUsage   = "N/A"
            CpuCores   = "4"
            CpuThreads = "4"
            CpuLimit   = "N/A"
            MemUsed    = "N/A"
            MemFree    = "N/A"
            MemTotal   = "N/A"
            MemLimit   = "N/A"
            IsRunning  = $false
        }
        $script:StatsCache = $stats
        $script:StatsCacheTime = $now
        return $stats
    }
}

function Get-VariantLabel {
    switch ($script:ActiveVariant) {
        "linux" { return "Linux/Wine  " }
        "wsl"   { return "WSL2/Ubuntu " }
        default { return "Windows     " }
    }
}

function Show-StatusLine {
    $stats = Get-ContainerStats
    $variantLabel = Get-VariantLabel
    Write-Host "┌─────────────────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│ [$variantLabel] CPU: $($stats.CpuUsage)% [$($stats.CpuCores)c/$($stats.CpuThreads)t] Limit: $($stats.CpuLimit) │ RAM: $($stats.MemUsed)GB/$($stats.MemTotal)GB (Free: $($stats.MemFree)GB) Limit: $($stats.MemLimit)" -ForegroundColor Cyan
    Write-Host "└─────────────────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
}

function Show-MainMenu {
    Clear-Host
    Show-StatusLine
    $variantLabel = (Get-VariantLabel).Trim()
    Write-Host ""
    Write-Host "╔═══════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   Enshrouded Container Menu   ║" -ForegroundColor Green
    Write-Host "╠═══════════════════════════════╣" -ForegroundColor Green
    Write-Host "║ Image: $($variantLabel.PadRight(23))║" -ForegroundColor Green
    Write-Host "╠═══════════════════════════════╣" -ForegroundColor Green
    Write-Host "║ 1 - Server Start              ║" -ForegroundColor Green
    Write-Host "║ 2 - Server Stop               ║" -ForegroundColor Green
    Write-Host "║ 3 - Server Restart            ║" -ForegroundColor Green
    Write-Host "║ 4 - Change Limits             ║" -ForegroundColor Green
    Write-Host "║ 5 - Rebuild Container         ║" -ForegroundColor Green
    Write-Host "║ 6 - Switch Image Variant      ║" -ForegroundColor Green
    Write-Host "║                               ║" -ForegroundColor Green
    Write-Host "║ 0 or ESC - Exit               ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
}

function Invoke-ServerStart {
    Clear-Host
    Show-StatusLine
    if (-not (Confirm-VariantCompatible)) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        Read-SingleKey "Press any key to continue..."
        return
    }
    Write-Host ""
    $stats = Get-ContainerStats
    if ($stats.IsRunning) {
        Write-Host "Server is already running." -ForegroundColor Yellow
    }
    else {
        Write-Host "Starting server..." -ForegroundColor Cyan
        Invoke-Compose @("up", "-d", $script:ServiceName)
        $script:StatsCache = $null  # Clear cache
        Write-Host "Server started." -ForegroundColor Green
    }
    Write-Host ""
    Read-SingleKey "Press any key to continue..."
}

function Invoke-ServerStop {
    Clear-Host
    Show-StatusLine
    if (-not (Confirm-VariantCompatible)) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        Read-SingleKey "Press any key to continue..."
        return
    }
    Write-Host ""
    $stats = Get-ContainerStats
    if (-not $stats.IsRunning) {
        Write-Host "Server is already stopped." -ForegroundColor Yellow
        Write-Host "Removing container..." -ForegroundColor Cyan
        Invoke-Compose @("down", $script:ServiceName)
        $script:StatsCache = $null
        Write-Host "Container removed." -ForegroundColor Green
    }
    else {
        Write-Host "Stopping server..." -ForegroundColor Cyan
        Invoke-Compose @("stop", $script:ServiceName)
        Invoke-Compose @("down", $script:ServiceName)
        $script:StatsCache = $null  # Clear cache
        Write-Host "Server stopped." -ForegroundColor Green
    }
    Write-Host ""
    Read-SingleKey "Press any key to continue..."
}

function Invoke-ServerRestart {
    Clear-Host
    Show-StatusLine
    if (-not (Confirm-VariantCompatible)) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        Read-SingleKey "Press any key to continue..."
        return
    }
    Write-Host ""
    Write-Host "Restarting server..." -ForegroundColor Cyan
    Invoke-Compose @("down", $script:ServiceName)
    Invoke-Compose @("up", "-d", $script:ServiceName)
    $script:StatsCache = $null  # Clear cache
    Write-Host "Server restarted." -ForegroundColor Green
    Write-Host ""
    Read-SingleKey "Press any key to continue..."
}

function Show-ChangeLimitsMenu {
    $continue = $true
    while ($continue) {
        Clear-Host
        Show-StatusLine
        Write-Host ""
        Write-Host "╔═══════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║    Change Limits Submenu      ║" -ForegroundColor Magenta
        Write-Host "╠═══════════════════════════════╣" -ForegroundColor Magenta
        Write-Host "║ 1 - Set CPU Limit             ║" -ForegroundColor Magenta
        Write-Host "║ 2 - Set Memory Limit          ║" -ForegroundColor Magenta
        Write-Host "║                               ║" -ForegroundColor Magenta
        Write-Host "║ 0 or ESC - Back               ║" -ForegroundColor Magenta
        Write-Host "╚═══════════════════════════════╝" -ForegroundColor Magenta
        Write-Host ""
        
        $key = Read-SingleKey "Select option: "
        Write-Host $key  # Echo the key
        
        switch ($key) {
            "1" { Invoke-SetCpuLimit }
            "2" { Invoke-SetMemoryLimit }
            "0" { $continue = $false }
            { $_ -eq [char]27 } { $continue = $false }
            default { Write-Host "Invalid option. Press any key..." -ForegroundColor Red; Read-SingleKey "" }
        }
    }
}

function Invoke-SetCpuLimit {
    Clear-Host
    Show-StatusLine
    Write-Host ""
    $stats = Get-ContainerStats
    Write-Host "Current CPU Limit: $($stats.CpuLimit) cores" -ForegroundColor Cyan
    Write-Host "Enter CPU limit in cores (e.g., 2, 4, 8) or press ESC to cancel:" -ForegroundColor Yellow
    $userInput = Read-Host " "

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        Read-SingleKey "Press any key to continue..."
        return
    }

    if (-not [double]::TryParse($userInput, [ref]$null)) {
        Write-Host "Invalid input." -ForegroundColor Red
        Read-SingleKey "Press any key to continue..."
        return
    }

    Write-Host "Updating CPU limit to $userInput cores..." -ForegroundColor Cyan

    [string]$yaml = Get-Content $ComposeFile -Raw

    $yaml = Edit-ServiceBlock $yaml {
        param($block)
        if ($block -match 'deploy:') {
            if ($block -match 'limits:') {
                if ($block -match 'cpus:') {
                    $block = $block -replace "cpus:\s*[''`"]?[0-9.]+[''`"]?", "cpus: '$userInput'"
                } else {
                    $block = $block -replace '(limits:)', "`$1`n          cpus: '$userInput'"
                }
            } else {
                $block = $block -replace '(resources:)', "`$1`n        limits:`n          cpus: '$userInput'"
            }
        } else {
            $block = $block + "`n    deploy:`n      resources:`n        limits:`n          cpus: '$userInput'"
        }
        return $block
    }

    Set-Content $ComposeFile $yaml
    $script:StatsCache = $null  # Clear cache

    Write-Host "docker-compose.yml updated. Restart container for changes to take effect." -ForegroundColor Green
    Read-SingleKey "Press any key to continue..."
}

function Invoke-SetMemoryLimit {
    Clear-Host
    Show-StatusLine
    Write-Host ""
    $stats = Get-ContainerStats
    Write-Host "Current Memory Limit: $($stats.MemLimit)" -ForegroundColor Cyan
    Write-Host "Enter memory limit (e.g., 4g, 8g, 16g) or press ESC to cancel:" -ForegroundColor Yellow
    $userInput = Read-Host " "

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        Read-SingleKey "Press any key to continue..."
        return
    }

    Write-Host "Updating memory limit to $userInput..." -ForegroundColor Cyan

    [string]$yaml = Get-Content $ComposeFile -Raw

    $yaml = Edit-ServiceBlock $yaml {
        param($block)
        if ($block -match 'deploy:') {
            if ($block -match 'limits:') {
                if ($block -match 'memory:') {
                    $block = $block -replace "memory:\s*[''`"]?[0-9.a-zA-Z]+[''`"]?", "memory: '$userInput'"
                } elseif ($block -match 'cpus:') {
                    $block = $block -replace "(cpus:\s*[''`"]?[0-9.]+[''`"]?)", "`$1`n          memory: '$userInput'"
                } else {
                    $block = $block -replace '(limits:)', "`$1`n          memory: '$userInput'"
                }
            } else {
                $block = $block -replace '(resources:)', "`$1`n        limits:`n          memory: '$userInput'"
            }
        } else {
            $block = $block + "`n    deploy:`n      resources:`n        limits:`n          memory: '$userInput'"
        }
        return $block
    }

    Set-Content $ComposeFile $yaml
    $script:StatsCache = $null  # Clear cache

    Write-Host "docker-compose.yml updated. Restart container for changes to take effect." -ForegroundColor Green
    Read-SingleKey "Press any key to continue..."
}

function Invoke-RebuildContainer {
    Clear-Host
    Show-StatusLine
    if (-not (Confirm-VariantCompatible)) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        Read-SingleKey "Press any key to continue..."
        return
    }
    Write-Host ""
    Write-Host "WARNING: This will rebuild the container image." -ForegroundColor Red
    Write-Host "Proceed? (y/n)" -ForegroundColor Yellow
    $confirm = Read-SingleKey " "
    Write-Host $confirm  # Echo the key

    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        Read-SingleKey "Press any key to continue..."
        return
    }

    Write-Host ""
    Write-Host "Rebuilding container..." -ForegroundColor Cyan
    Invoke-Compose @("build", "--no-cache", $script:ServiceName)
    $script:StatsCache = $null  # Clear cache
    Write-Host "Container rebuilt." -ForegroundColor Green
    Write-Host ""
    Read-SingleKey "Press any key to continue..."
}

# Initialize variant - auto-detect from Docker Desktop mode, or use explicit param
if ($Variant -eq "auto") {
    Initialize-Variant (Get-DockerMode)
} else {
    Initialize-Variant $Variant
}

# Main loop
$mainContinue = $true
while ($mainContinue) {
    Show-MainMenu
    
    $key = Read-SingleKey "Select option: "
    Write-Host $key  # Echo the key
    
    switch ($key) {
        "1" { Invoke-ServerStart }
        "2" { Invoke-ServerStop }
        "3" { Invoke-ServerRestart }
        "4" { Show-ChangeLimitsMenu }
        "5" { Invoke-RebuildContainer }
        "6" { Select-Variant }
        "0" { $mainContinue = $false }
        { $_ -eq [char]27 } { $mainContinue = $false }
        default { 
            Write-Host "Invalid option. Press any key..." -ForegroundColor Red
            Read-SingleKey ""
        }
    }
}

Write-Host "`nExiting..." -ForegroundColor Yellow
exit 0

