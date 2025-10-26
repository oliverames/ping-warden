#!/bin/bash

# Automated Build and Install Script for AWDLControl
# This script builds and installs the complete AWDL control system
# WITHOUT requiring manual Xcode interaction

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================"
echo "  AWDLControl - Automated Build & Install"
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo "ℹ️  $1"
}

# Check if Xcode.app exists
if [ ! -d "/Applications/Xcode.app" ]; then
    print_error "Xcode.app not found in /Applications/"
    print_info "Please install Xcode from the App Store"
    exit 1
fi

# Check if xcode-select is pointing to Xcode.app
CURRENT_XCODE=$(xcode-select -p)
if [ "$CURRENT_XCODE" != "/Applications/Xcode.app/Contents/Developer" ]; then
    print_warning "Xcode developer directory is set to: $CURRENT_XCODE"
    print_info "Switching to Xcode.app (requires sudo)..."
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
    print_success "Switched to Xcode.app"
fi

# Check if running as regular user (we'll escalate when needed)
if [ "$EUID" -eq 0 ]; then
    print_error "Do not run this script with sudo"
    print_info "The script will ask for your password when needed"
    exit 1
fi

echo "Step 1: Building C Daemon"
echo "---------------------------------------"
cd AWDLMonitorDaemon
make clean
make

if [ ! -f "awdl_monitor_daemon" ]; then
    print_error "Failed to build C daemon"
    exit 1
fi
print_success "C daemon built successfully"
cd ..
echo ""

echo "Step 2: Installing C Daemon"
echo "---------------------------------------"
print_info "This step requires sudo privileges to install the daemon"
sudo ./install_daemon.sh

if [ ! -f "/usr/local/bin/awdl_monitor_daemon" ]; then
    print_error "Failed to install daemon"
    exit 1
fi
print_success "C daemon installed to /usr/local/bin/"
echo ""

echo "Step 3: Building Xcode Project"
echo "---------------------------------------"
print_info "Building AWDLControlHelper (privileged helper tool)..."

# Build AWDLControlHelper first
xcodebuild -project AWDLControl.xcodeproj \
    -scheme AWDLControlHelper \
    -configuration Debug \
    -derivedDataPath ./DerivedData \
    clean build

if [ ! -f "./DerivedData/Build/Products/Debug/AWDLControlHelper" ]; then
    print_error "Failed to build AWDLControlHelper"
    exit 1
fi
print_success "AWDLControlHelper built successfully"
echo ""

print_info "Building AWDLControl (main app)..."

# Build AWDLControl app
xcodebuild -project AWDLControl.xcodeproj \
    -scheme AWDLControl \
    -configuration Debug \
    -derivedDataPath ./DerivedData \
    build

if [ ! -d "./DerivedData/Build/Products/Debug/AWDLControl.app" ]; then
    print_error "Failed to build AWDLControl.app"
    exit 1
fi
print_success "AWDLControl.app built successfully"
echo ""

echo "Step 4: Embedding Helper in App Bundle"
echo "---------------------------------------"

APP_PATH="./DerivedData/Build/Products/Debug/AWDLControl.app"
HELPER_PATH="./DerivedData/Build/Products/Debug/AWDLControlHelper"
LAUNCH_SERVICES_DIR="$APP_PATH/Contents/Library/LaunchServices"

mkdir -p "$LAUNCH_SERVICES_DIR"
cp -f "$HELPER_PATH" "$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper"
chmod 755 "$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper"

if [ ! -f "$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper" ]; then
    print_error "Failed to embed helper in app bundle"
    exit 1
fi
print_success "Helper embedded in app bundle"
echo ""

echo "Step 5: Verifying Build"
echo "---------------------------------------"
print_info "Checking daemon installation..."
ls -lh /usr/local/bin/awdl_monitor_daemon
ls -lh /Library/LaunchDaemons/com.awdlcontrol.daemon.plist

print_info "Checking app bundle structure..."
ls -lh "$APP_PATH/Contents/MacOS/AWDLControl"
ls -lh "$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper"

print_success "All components verified"
echo ""

echo "============================================"
echo "  Build Complete!"
echo "============================================"
echo ""
echo "What was built and installed:"
echo "  • C Daemon: /usr/local/bin/awdl_monitor_daemon"
echo "  • Daemon plist: /Library/LaunchDaemons/com.awdlcontrol.daemon.plist"
echo "  • Main app: $APP_PATH"
echo "  • Embedded helper: $LAUNCH_SERVICES_DIR/com.awdlcontrol.helper"
echo ""
echo "Next Steps:"
echo "---------------------------------------"
echo "1. Run the app:"
echo "   open \"$APP_PATH\""
echo ""
echo "2. Click the menu bar icon (antenna symbol)"
echo ""
echo "3. Click 'Enable AWDL Monitoring'"
echo ""
echo "4. Enter your password when prompted (ONE TIME ONLY)"
echo "   This installs the privileged helper to /Library/PrivilegedHelperTools/"
echo ""
echo "5. After this initial setup, you can:"
echo "   • Toggle monitoring on/off without password prompts"
echo "   • Quit and relaunch without password prompts"
echo "   • Reboot and enable monitoring without password prompts"
echo ""
echo "Testing:"
echo "---------------------------------------"
echo "After enabling monitoring, test that AWDL is blocked:"
echo "  sudo ifconfig awdl0 up"
echo "  ifconfig awdl0 | grep flags"
echo "  # Should show DOWN (daemon brings it down in <1ms)"
echo ""
echo "View daemon logs:"
echo "  log show --predicate 'process == \"awdl_monitor_daemon\"' --last 10m"
echo ""
echo "View helper logs:"
echo "  log show --predicate 'process == \"com.awdlcontrol.helper\"' --last 10m"
echo ""
