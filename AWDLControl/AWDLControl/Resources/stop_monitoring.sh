#!/bin/bash
# Quick script to stop AWDL monitoring
sudo launchctl bootout system/com.awdlcontrol.daemon 2>&1
exit $?
