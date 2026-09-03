#!/bin/bash
# ==============================================================================
# Script: update-antigravity-ide.sh
# Description: Automatically checks, downloads, and updates the Antigravity IDE
#              and Antigravity Hub to the latest versions by parsing the
#              official website dynamically.
# Authors: Antigravity AI
# ==============================================================================

set -euo pipefail

# Default installation directory and symlink directory
INSTALL_DIR="/usr/local"
BIN_DIR="/usr/local/bin"
TEMP_DIR="/tmp/antigravity-update"

# Options
UPDATE_IDE=true
UPDATE_HUB=true
FORCE=false

# Print usage instructions
print_usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
  -d, --dir <path>     Target installation directory (default: /usr/local)
  -b, --bin <path>     Directory for symlinks (default: /usr/local/bin)
  --ide-only           Only update the Antigravity IDE
  --hub-only           Only update the Antigravity Hub
  -f, --force          Force download and update even if up to date
  -h, --help           Show this help message

Examples:
  sudo ./update-antigravity-ide.sh
  ./update-antigravity-ide.sh --dir ~/.local --bin ~/.local/bin --ide-only
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -b|--bin)
            BIN_DIR="$2"
            shift 2
            ;;
        --ide-only)
            UPDATE_IDE=true
            UPDATE_HUB=false
            shift
            ;;
        --hub-only)
            UPDATE_IDE=false
            UPDATE_HUB=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            print_usage
            exit 1
            ;;
    esac
done

# Check dependencies
for cmd in curl grep tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' is not installed."
        exit 1
    fi
done

# Ensure we have write permission to directories
if [ ! -w "$INSTALL_DIR" ] || [ ! -w "$BIN_DIR" ]; then
    echo "Warning: You do not have write permission to $INSTALL_DIR or $BIN_DIR."
    echo "If you are installing system-wide, please run with sudo:"
    echo "  sudo $0 $@"
    echo "Or specify a user-owned directory:"
    echo "  $0 --dir ~/.local --bin ~/.local/bin"
    exit 1
fi

echo "--------------------------------------------------------"
echo "🔍 Resolving latest version details from antigravity.google..."
echo "--------------------------------------------------------"

# 1. Fetch download page and locate the main angular bundle
DOWNLOAD_PAGE="https://antigravity.google/download"
JS_BUNDLE_NAME=$(curl -sL --compressed "$DOWNLOAD_PAGE" | grep -oE 'main-[A-Za-z0-9_-]+\.js' | head -n1 || true)

if [ -z "$JS_BUNDLE_NAME" ]; then
    echo "Error: Failed to locate JavaScript bundle on the download page ($DOWNLOAD_PAGE)."
    exit 1
fi

JS_BUNDLE_URL="https://antigravity.google/$JS_BUNDLE_NAME"
echo "Found JS Bundle: $JS_BUNDLE_NAME"

# 2. Extract direct download URLs
IDE_URL=""
HUB_URL=""

# Read the JS bundle content into a temporary variable to avoid multiple network calls
echo "Fetching JS bundle content..."
JS_CONTENT=$(curl -sL --compressed "$JS_BUNDLE_URL")

if [ "$UPDATE_IDE" = true ]; then
    IDE_URL=$(echo "$JS_CONTENT" | grep -oE 'https://edgedl\.me\.gvt1\.com/[^"'\'']+/linux-x64/Antigravity%20IDE\.tar\.gz' | head -n1 || true)
    if [ -z "$IDE_URL" ]; then
        echo "Error: Could not extract the Linux x64 IDE download URL from the JS bundle."
        exit 1
    fi
    # Extract version from URL: e.g. stable/2.0.3-6242596486512640/linux-x64
    IDE_VERSION=$(echo "$IDE_URL" | grep -oE 'stable/[^/]+' | cut -d'/' -f2 || echo "unknown")
    echo "Latest IDE Version Found: $IDE_VERSION"
    echo "Direct Link: $IDE_URL"
fi

if [ "$UPDATE_HUB" = true ]; then
    HUB_URL=$(echo "$JS_CONTENT" | grep -oE 'https://storage\.googleapis\.com/antigravity-public/antigravity-hub/[^"'\'']+/linux-x64/Antigravity\.tar\.gz' | head -n1 || true)
    if [ -z "$HUB_URL" ]; then
        echo "Error: Could not extract the Linux x64 Hub download URL from the JS bundle."
        exit 1
    fi
    HUB_VERSION=$(echo "$HUB_URL" | grep -oE 'antigravity-hub/[^/]+' | cut -d'/' -f2 || echo "unknown")
    echo "Latest Hub Version Found: $HUB_VERSION"
    echo "Direct Link: $HUB_URL"
fi

# Set up clean temporary working area
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# --------------------------------------------------------
# Update Antigravity IDE
# --------------------------------------------------------
if [ "$UPDATE_IDE" = true ]; then
    echo ""
    echo "--------------------------------------------------------"
    echo "🚀 Updating Antigravity IDE..."
    echo "--------------------------------------------------------"
    
    TARGET_PATH="$INSTALL_DIR/Antigravity IDE"
    
    # Check current version if installed
    CURRENT_VERSION=""
    if [ -d "$TARGET_PATH" ] && [ "$FORCE" = false ]; then
        # Try to identify version from package.json or resources
        # Usually it can be read from resources/app/package.json
        PACKAGE_JSON="$TARGET_PATH/resources/app/package.json"
        if [ -f "$PACKAGE_JSON" ]; then
            CURRENT_VERSION=$(grep -oE '"version":\s*"[^"]+"' "$PACKAGE_JSON" | head -n1 | cut -d'"' -f4 || echo "")
        fi
        
        if [ -n "$CURRENT_VERSION" ] && [[ "$IDE_VERSION" == *"$CURRENT_VERSION"* ]]; then
            echo "✅ Antigravity IDE is already up to date (installed: $CURRENT_VERSION)."
        else
            echo "Update available! Current version: ${CURRENT_VERSION:-unknown} -> Newest: $IDE_VERSION"
        fi
    fi

    if [ -z "$CURRENT_VERSION" ] || [[ ! "$IDE_VERSION" == *"$CURRENT_VERSION"* ]] || [ "$FORCE" = true ]; then
        echo "Downloading tarball..."
        curl -L --progress-bar "$IDE_URL" -o "Antigravity_IDE.tar.gz"
        
        echo "Extracting to $INSTALL_DIR..."
        # Safely remove old version directory to avoid conflicts
        rm -rf "$TARGET_PATH"
        tar -xzf "Antigravity_IDE.tar.gz" -C "$INSTALL_DIR"
        
        echo "Updating symlink at $BIN_DIR/antigravity2-ide..."
        mkdir -p "$BIN_DIR"
        rm -f "$BIN_DIR/antigravity2-ide"
        ln -sf "$TARGET_PATH/bin/antigravity-ide" "$BIN_DIR/antigravity2-ide"
        
        echo "✅ Antigravity IDE updated successfully!"
    fi
fi

# --------------------------------------------------------
# Update Antigravity Hub
# --------------------------------------------------------
if [ "$UPDATE_HUB" = true ]; then
    echo ""
    echo "--------------------------------------------------------"
    echo "🚀 Updating Antigravity Hub..."
    echo "--------------------------------------------------------"
    
    TARGET_PATH="$INSTALL_DIR/Antigravity-x64"
    
    # Check current version if installed
    CURRENT_VERSION=""
    if [ -d "$TARGET_PATH" ] && [ "$FORCE" = false ]; then
        # Try to read package.json
        PACKAGE_JSON="$TARGET_PATH/resources/app/package.json"
        if [ -f "$PACKAGE_JSON" ]; then
            CURRENT_VERSION=$(grep -oE '"version":\s*"[^"]+"' "$PACKAGE_JSON" | head -n1 | cut -d'"' -f4 || echo "")
        fi
        
        if [ -n "$CURRENT_VERSION" ] && [[ "$HUB_VERSION" == *"$CURRENT_VERSION"* ]]; then
            echo "✅ Antigravity Hub is already up to date (installed: $CURRENT_VERSION)."
        else
            echo "Update available! Current version: ${CURRENT_VERSION:-unknown} -> Newest: $HUB_VERSION"
        fi
    fi

    if [ -z "$CURRENT_VERSION" ] || [[ ! "$HUB_VERSION" == *"$CURRENT_VERSION"* ]] || [ "$FORCE" = true ]; then
        echo "Downloading tarball..."
        curl -L --progress-bar "$HUB_URL" -o "Antigravity_Hub.tar.gz"
        
        echo "Extracting to $INSTALL_DIR..."
        rm -rf "$TARGET_PATH"
        tar -xzf "Antigravity_Hub.tar.gz" -C "$INSTALL_DIR"
        
        echo "Updating symlink at $BIN_DIR/antigravity2..."
        mkdir -p "$BIN_DIR"
        rm -f "$BIN_DIR/antigravity2"
        ln -sf "$TARGET_PATH/antigravity" "$BIN_DIR/antigravity2"
        
        echo "✅ Antigravity Hub updated successfully!"
    fi
fi

# Clean up temp files
rm -rf "$TEMP_DIR"
echo ""
echo "🎉 Update check completed successfully!"
echo "--------------------------------------------------------"
