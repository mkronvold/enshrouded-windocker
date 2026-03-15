FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ── System packages ────────────────────────────────────────────────────────────
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wget curl ca-certificates gnupg2 \
        lib32gcc-s1 libstdc++6 libstdc++6:i386 \
        xvfb \
        python3 \
        locales tzdata \
        libvulkan1 libvulkan1:i386 \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        libegl-mesa0 libegl1 libegl1:i386 \
    && rm -rf /var/lib/apt/lists/*

# ── WineHQ staging ─────────────────────────────────────────────────────────────
RUN mkdir -p /etc/apt/keyrings && \
    wget -qO /etc/apt/keyrings/winehq-archive.key \
        https://dl.winehq.org/wine-builds/winehq.key && \
    echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq-archive.key] \
https://dl.winehq.org/wine-builds/ubuntu/ jammy main" \
        > /etc/apt/sources.list.d/winehq.list && \
    apt-get update && \
    apt-get install -y winehq-staging && \
    rm -rf /var/lib/apt/lists/*

# ── Steam user ─────────────────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash steam

# ── SteamCMD ───────────────────────────────────────────────────────────────────
RUN mkdir -p /home/steam/steamcmd && \
    wget -qO /tmp/steamcmd_linux.tar.gz \
        https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar xzf /tmp/steamcmd_linux.tar.gz -C /home/steam/steamcmd && \
    rm /tmp/steamcmd_linux.tar.gz && \
    chown -R steam:steam /home/steam

# Bootstrap SteamCMD (first run updates itself)
RUN su steam -c "/home/steam/steamcmd/steamcmd.sh +quit || true"

# ── Server directory ───────────────────────────────────────────────────────────
RUN mkdir -p /home/steam/enshrouded && chown steam:steam /home/steam/enshrouded

# Pre-create X11 socket dir so Xvfb works as non-root
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# ── winetricks ─────────────────────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends cabextract unzip && \
    wget -qO /usr/local/bin/winetricks \
        https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x /usr/local/bin/winetricks && \
    rm -rf /var/lib/apt/lists/*

# Pre-initialise Wine prefix at build time so startup is instant
RUN su steam -c \
    "WINEPREFIX=/home/steam/.wine WINEARCH=win64 WINEDEBUG=-all WINEDLLOVERRIDES='mscoree=d;mshtml=d' \
     xvfb-run --auto-servernum wineboot --init || true"

# Install DXVK (D3D9/10/11 → Vulkan) — required by Unreal Engine dedicated servers
RUN su steam -c \
    "WINEPREFIX=/home/steam/.wine WINEARCH=win64 WINEDEBUG=-all \
     xvfb-run --auto-servernum winetricks -q dxvk"

# Install Visual C++ 2022 runtime DLLs by direct cabinet extraction — the Windows
# vc_redist installer always fails (exit 243) in a headless Docker build.
# cabextract reads the embedded "a10" cabinet directly without needing Wine or X.
RUN mkdir -p /tmp/vc64c /tmp/vc86c && \
    wget -q -O /tmp/vc64.exe "https://aka.ms/vs/17/release/vc_redist.x64.exe" && \
    wget -q -O /tmp/vc86.exe "https://aka.ms/vs/17/release/vc_redist.x86.exe" && \
    cabextract -q -d /tmp/vc64c /tmp/vc64.exe -F a10 2>/dev/null || true && \
    cabextract -q -d /tmp/vc86c /tmp/vc86.exe -F a10 2>/dev/null || true && \
    cabextract -q -d /home/steam/.wine/dosdevices/c:/windows/system32  /tmp/vc64c/a10 2>/dev/null || true && \
    cabextract -q -d /home/steam/.wine/dosdevices/c:/windows/syswow64  /tmp/vc86c/a10 2>/dev/null || true && \
    ls /home/steam/.wine/dosdevices/c:/windows/system32/msvcp140.dll 2>/dev/null \
        && echo "[OK] VC++ 2022 (x64) DLLs extracted" \
        || echo "[WARN] VC++ 2022 (x64) extraction produced no DLLs" && \
    chown -R steam:steam /home/steam/.wine && \
    rm -rf /tmp/vc64.exe /tmp/vc86.exe /tmp/vc64c /tmp/vc86c

# ── Entrypoint ─────────────────────────────────────────────────────────────────
COPY scripts/entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

USER steam
WORKDIR /home/steam

# Wine technical defaults — game settings come from .env at runtime
ENV PATH="/opt/wine-staging/bin:${PATH}" \
    WINEPREFIX="/home/steam/.wine" \
    WINEARCH="win64" \
    WINEDEBUG="-all" \
    WINEDLLOVERRIDES="mscoree=d;mshtml=d;msvcp140=n,b;vcruntime140=n,b;vcruntime140_1=n,b" \
    WINEESYNC="1" \
    DISPLAY=":99"

EXPOSE 15636/udp 15636/tcp 15637/udp 15637/tcp

VOLUME ["/home/steam/enshrouded"]

ENTRYPOINT ["/entrypoint.sh"]
