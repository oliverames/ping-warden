#!/bin/bash
# Quick script to start AWDL monitoring
sudo launchctl bootstrap system /Library/LaunchDaemons/com.awdlcontrol.daemon.plist 2>&1
exit $?
