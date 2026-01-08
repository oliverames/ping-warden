#!/bin/bash
set -e

echo "🔨 Building AWDLControl..."
echo ""

# Build C daemon
echo "📦 Building C daemon..."
cd AWDLControl/AWDLMonitorDaemon
make clean > /dev/null 2>&1 || true
make
cd ../..
echo "✅ Daemon built successfully"
echo ""

# Build Swift app
echo "📱 Building Swift app..."

# Note: Building without code signing. Control Center widget requires code signing
# to work. To enable signing, open the project in Xcode and configure signing there.
echo "⚠️  Building without code signing (Control Center widget will not be available)"
echo "   To enable: Open project in Xcode → Signing & Capabilities → Select your team"

# Temporarily disable set -e to handle xcodebuild failure gracefully
set +e
xcodebuild -project AWDLControl/AWDLControl.xcodeproj \
           -target AWDLControl \
           -target AWDLControlWidget \
           -configuration Release \
           clean build \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO \
           > /tmp/xcodebuild.log 2>&1
XCODE_EXIT=$?
set -e

if [ $XCODE_EXIT -eq 0 ]; then
    echo "✅ App built successfully"
    echo ""

    # Copy daemon binary to app bundle Resources
    echo "📦 Bundling daemon binary..."
    RESOURCES_DIR="AWDLControl/build/Release/AWDLControl.app/Contents/Resources"
    cp AWDLControl/AWDLMonitorDaemon/awdl_monitor_daemon "$RESOURCES_DIR/"
    chmod 755 "$RESOURCES_DIR/awdl_monitor_daemon"
    echo "✅ Daemon binary bundled"
    echo ""

    # Verify bundle contents
    echo "📋 Bundle contents:"
    ls -la "$RESOURCES_DIR/"
    echo ""

    echo "📍 Built app location:"
    echo "   AWDLControl/build/Release/AWDLControl.app"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Copy to Applications: cp -r AWDLControl/build/Release/AWDLControl.app /Applications/"
    echo "   2. Launch AWDLControl.app"
    echo "   3. Click 'Set Up Now' when prompted"
else
    echo "❌ Build failed. Check /tmp/xcodebuild.log for details"
    tail -50 /tmp/xcodebuild.log
    exit 1
fi
