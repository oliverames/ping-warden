#!/bin/bash

echo "Testing AWDL daemon response time..."
echo ""

# Test 1: Bring AWDL up and immediately check if it's down
echo "Test 1: Bringing AWDL up and checking after 1ms..."
ifconfig awdl0 up
sleep 0.001
STATUS=$(ifconfig awdl0 | grep flags)
if echo "$STATUS" | grep -q "UP"; then
    echo "❌ FAILED: AWDL is still UP after 1ms"
    echo "   $STATUS"
else
    echo "✅ SUCCESS: AWDL is DOWN (daemon responded in <1ms)"
    echo "   $STATUS"
fi
echo ""

# Test 2: Try multiple times
echo "Test 2: Testing 5 rapid toggles..."
SUCCESS_COUNT=0
for i in {1..5}; do
    ifconfig awdl0 up
    sleep 0.001
    if ! ifconfig awdl0 | grep -q "UP"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi
done
echo "✅ $SUCCESS_COUNT/5 tests succeeded (AWDL brought down in <1ms)"
echo ""

# Test 3: Check final status
echo "Test 3: Final AWDL status..."
FINAL_STATUS=$(ifconfig awdl0 | grep flags)
if echo "$FINAL_STATUS" | grep -q "UP"; then
    echo "❌ AWDL is UP (not being controlled)"
else
    echo "✅ AWDL is DOWN (daemon is working)"
fi
echo "   $FINAL_STATUS"
echo ""

echo "Test complete!"
