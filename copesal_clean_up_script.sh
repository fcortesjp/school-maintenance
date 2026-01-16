#!/bin/bash

# ==========================================
# SCHOOL COMPUTER MAINTENANCE SCRIPT v4
# For Linux Mint / Zorin OS
# ==========================================

# --- CONFIGURATION ---
TARGET_USER="copesal"  # The user whose folders we are cleaning
LOG_FILE="/var/log/school_maintenance.log"
BLEACHBIT_CFG_URL="https://github.com/fcortesjp/school-maintenance/raw/refs/heads/main/bleachbit.ini"

# Colors for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function for logging and printing
log_msg() {
    echo -e "${2}${1}${NC}"
    echo "$(date): $1" >> "$LOG_FILE"
}

# Ensure script is run as root (sudo)
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (use sudo).${NC}"
  exit 1
fi

# 1. CHECK DISK USAGE (START)
# ==========================================
log_msg "--------------------------------" "$BLUE"
log_msg "STARTING MAINTENANCE TASK" "$BLUE"
log_msg "--------------------------------" "$BLUE"

USAGE_START=$(df -h / | awk 'NR==2 {print $5}')
AVAIL_START=$(df -h / | awk 'NR==2 {print $4}')
log_msg "Initial Disk Usage: $USAGE_START ($AVAIL_START Available)" "$YELLOW"


# 2. CLEAN USER FOLDERS (MOVED UP)
# ==========================================
log_msg "Step 2: Clearing Student Folders..." "$BLUE"

DIRS_TO_CLEAN=(
    "/home/$TARGET_USER/Downloads"
    "/home/$TARGET_USER/Pictures"
)

for dir in "${DIRS_TO_CLEAN[@]}"; do
    if [ -d "$dir" ]; then
        # Remove contents, but keep the folder itself
        # The :? ensures we never run this on an empty variable
        rm -rf "${dir:?}"/*
        log_msg "  [OK] Cleared contents of $dir" "$GREEN"
    else
        log_msg "  [WARN] Directory not found: $dir" "$YELLOW"
    fi
done


# 3. REMOVE FLATPAKS
# ==========================================
log_msg "Step 3: Removing Flatpaks..." "$BLUE"

FLATPAK_LIST=(
    "ch.openboard.OpenBoard"
    "com.github.johnfactotum.Foliate"
    "com.github.xournalpp.xournalpp"
    "com.logseq.Logseq"
    "edu.mit.Scratch"
    "io.gdevelop.ide"
    "org.fritzing.Fritzing"
    "org.kde.gcompris"
    "org.learningequality.Kolibri"
    "com.github.phase1geo.minder"
    "org.kde.minuet"
)

for app in "${FLATPAK_LIST[@]}"; do
    if flatpak list --app | grep -q "$app"; then
        log_msg "Removing $app..." "$NC"
        flatpak uninstall "$app" -y >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log_msg "  [OK] $app removed." "$GREEN"
        else
            log_msg "  [ERR] Failed to remove $app." "$RED"
        fi
    else
        log_msg "  [SKIP] $app not found." "$NC"
    fi
done

# Clean up unused flatpak runtimes immediately to free space
log_msg "Cleaning unused Flatpak runtimes..." "$NC"
flatpak uninstall --unused -y >> "$LOG_FILE" 2>&1


# 4. REMOVE APT PACKAGES
# ==========================================
log_msg "Step 4: Removing Standard Packages (APT)..." "$BLUE"

APT_LIST=(
    "thunderbird"
    "libreoffice-base"
    "audacity"
    "musescore"
    "transmission-gtk"
    "hexchat"
    "aisleriot"
    "gnome-mahjongg"
    "gnome-mines"
    "gnome-sudoku"
)

for pkg in "${APT_LIST[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg"; then
        log_msg "Purging $pkg..." "$NC"
        apt purge "$pkg" -y >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log_msg "  [OK] $pkg purged." "$GREEN"
        else
            log_msg "  [ERR] Failed to purge $pkg." "$RED"
        fi
    else
        log_msg "  [SKIP] $pkg not installed." "$NC"
    fi
done


# 5. BLEACHBIT (INSTALL/CONFIGURE/RUN)
# ==========================================
log_msg "Step 5: Setting up BleachBit..." "$BLUE"

# A. Check and Install
if ! command -v bleachbit &> /dev/null; then
    log_msg "  BleachBit not found. Installing..." "$YELLOW"
    apt update >> "$LOG_FILE" 2>&1
    apt install bleachbit -y >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_msg "  [OK] BleachBit installed." "$GREEN"
    else
        log_msg "  [ERR] Could not install BleachBit." "$RED"
    fi
else
    log_msg "  [OK] BleachBit is already installed." "$GREEN"
fi

# B. Download Config (Force overwrite to ensure latest version)
# We place it in /root/.config
mkdir -p /root/.config/bleachbit
log_msg "  Downloading config from GitHub..." "$NC"
wget -q -O /root/.config/bleachbit/bleachbit.ini "$BLEACHBIT_CFG_URL"

if [ $? -eq 0 ]; then
    log_msg "  [OK] Config applied." "$GREEN"
    # C. Run Clean
    bleachbit --clean --preset >> "$LOG_FILE" 2>&1
    log_msg "  [OK] BleachBit cycle complete." "$GREEN"
else
    log_msg "  [ERR] Failed to download config. Skipping cleanup." "$RED"
fi

# 6. SYSTEM UPDATES (APT)
# ==========================================
log_msg "Step 6: Updating System Packages (APT)..." "$BLUE"

export DEBIAN_FRONTEND=noninteractive

apt update >> "$LOG_FILE" 2>&1
apt upgrade -y >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log_msg "  [OK] System (APT) Upgraded successfully." "$GREEN"
else
    log_msg "  [ERR] Errors occurred during APT upgrade." "$RED"
fi


# 7. REFRESH SNAPS & FLATPAKS (NEW STEP)
# ==========================================
log_msg "Step 7: Refreshing Snaps and Flatpaks..." "$BLUE"

# Refresh Snaps
if command -v snap &> /dev/null; then
    log_msg "Updating Snaps..." "$NC"
    snap refresh >> "$LOG_FILE" 2>&1
    log_msg "  [OK] Snaps refreshed." "$GREEN"
fi

# Update Flatpaks
if command -v flatpak &> /dev/null; then
    log_msg "Updating Flatpaks..." "$NC"
    flatpak update -y >> "$LOG_FILE" 2>&1
    log_msg "  [OK] Flatpaks updated." "$GREEN"
fi


# 8. POST-UPDATE CLEANUP
# ==========================================
log_msg "Step 8: Final Cache Cleanup..." "$BLUE"
apt clean >> "$LOG_FILE" 2>&1
apt autoremove --purge -y >> "$LOG_FILE" 2>&1
log_msg "  [OK] Cache cleaned." "$GREEN"


# FINAL STATUS
# ==========================================
log_msg "--------------------------------" "$BLUE"
USAGE_END=$(df -h / | awk 'NR==2 {print $5}')
AVAIL_END=$(df -h / | awk 'NR==2 {print $4}')

log_msg "MAINTENANCE COMPLETE" "$GREEN"
log_msg "Started at: $USAGE_START ($AVAIL_START)" "$YELLOW"
log_msg "Ended at:   $USAGE_END ($AVAIL_END)" "$GREEN"
log_msg "--------------------------------" "$BLUE"
