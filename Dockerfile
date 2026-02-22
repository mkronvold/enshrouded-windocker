# escape=`
FROM mcr.microsoft.com/windows/servercore:ltsc2022

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install SteamCMD
RUN New-Item -ItemType Directory -Path C:\steamcmd -Force | Out-Null; `
    Invoke-WebRequest -Uri 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' `
      -OutFile 'C:\steamcmd\steamcmd.zip'; `
    Expand-Archive -Path 'C:\steamcmd\steamcmd.zip' -DestinationPath 'C:\steamcmd'; `
    Remove-Item 'C:\steamcmd\steamcmd.zip'

# Bootstrap SteamCMD (first run updates itself)
RUN C:\steamcmd\steamcmd.exe +quit; exit 0

# Create server directory
RUN New-Item -ItemType Directory -Path C:\enshrouded -Force | Out-Null

# Copy entrypoint
COPY scripts\entrypoint.ps1 C:\entrypoint.ps1

ENV UPDATE_ON_START="true" `
    NAME="Enshrouded Server" `
    GAME_PORT="15636" `
    QUERY_PORT="15637" `
    SLOT_COUNT="16" `
    AUTO_UPDATE="true" `
    AUTO_UPDATE_SCHEDULE="0 3 * * *" `
    SCHEDULED_RESTART="true" `
    SCHEDULED_RESTART_SCHEDULE="0 4 * * *"

EXPOSE 15636/tcp 15636/udp 15637/tcp 15637/udp

VOLUME ["C:\\enshrouded"]

ENTRYPOINT ["powershell", "-ExecutionPolicy", "Bypass", "-File", "C:\\entrypoint.ps1"]
