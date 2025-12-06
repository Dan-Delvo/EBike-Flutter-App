# ESP32 Bluetooth Connection Troubleshooting Guide

## Issue: Cannot connect to ESP32 even when powered on and paired

### Key Points:

1. **BLE vs Classic Bluetooth**

   - ✅ The Flutter app uses **BLE (Bluetooth Low Energy)** via `flutter_blue_plus`
   - ❌ Classic Bluetooth (used for audio devices, keyboards) will NOT work
   - Your ESP32 must be running BLE, not Classic Bluetooth

2. **Pairing is NOT required for BLE**

   - BLE devices don't need to be "paired" in Android Bluetooth settings
   - Remove the ESP32 from paired devices if you paired it
   - The app will connect directly to the BLE device

3. **Check Your ESP32 Code**
   - Device name MUST be exactly: `LUIGI` (case-sensitive)
   - Must use BLE libraries (`BLEDevice.h`), not Classic Bluetooth
   - See `ESP32_BLE_Example.ino` for reference code

## Fixes Applied:

### 1. Improved Scanning

- Increased scan timeout to 15 seconds
- Added real-time scan results logging
- Matches by both name and MAC address
- Shows all discovered devices in logs

### 2. Better Error Messages

- Bluetooth state checking (on/off)
- Detailed service and characteristic discovery logs
- Clear warnings if write/notify characteristics not found

### 3. Enhanced Debugging

- All steps now logged in diagnostics page
- Shows UUIDs of discovered services
- Shows characteristic properties

## How to Test:

### Step 1: Check ESP32

```
1. Upload the ESP32_BLE_Example.ino to your ESP32
2. Open Serial Monitor (115200 baud)
3. You should see: "BLE Server is now advertising!"
4. Device name should show as "LUIGI"
```

### Step 2: Test Flutter App

```
1. Install the new APK: build/app/outputs/flutter-apk/app-release.apk
2. Open the app
3. Go to Diagnostics page
4. Tap "Connect"
5. Watch the logs - you'll see all discovered devices
```

### Step 3: Check Logs

The diagnostics page will show:

- ✓ "Scanning for ESP32 'LUIGI'..."
- ✓ "Found: LUIGI [84:1F:E8:69:2F:FE]"
- ✓ "Matched ESP32 by name: LUIGI"
- ✓ "Connected to LUIGI"
- ✓ "Discovering services..."
- ✓ "Found X services"

## Common Issues:

### Issue: "ESP32 'LUIGI' not found"

**Solutions:**

- ESP32 is off → Turn it on
- Wrong device name → Change ESP32 code to use "LUIGI"
- Using Classic Bluetooth → Switch to BLE (see example code)
- ESP32 not advertising → Check Serial Monitor for errors

### Issue: "Bluetooth is turned off"

**Solution:**

- Enable Bluetooth in Android settings
- Grant Bluetooth permissions to the app

### Issue: Device found but won't connect

**Solutions:**

- Unpair the device from Android Bluetooth settings
- ESP32 already connected to another device → Reset ESP32
- Increase connection timeout (already set to 20 seconds)

### Issue: Connected but no data received

**Solutions:**

- Check if notify characteristic exists (see logs)
- Verify ESP32 is calling `pCharacteristic->notify()`
- Check message format: "COIN:5", "BILL:20", etc.

## ESP32 Code Requirements:

Your ESP32 code MUST:

1. Use `#include <BLEDevice.h>` (BLE, not Classic)
2. Set device name: `BLEDevice::init("LUIGI");`
3. Create a characteristic with NOTIFY property
4. Create a characteristic with WRITE property
5. Call `pCharacteristic->notify()` to send data
6. Send messages in format: "COIN:X", "BILL:X", "CREDIT:X"

## Testing Without Hardware:

You can test BLE connection using:

- **Android:** nRF Connect app
- **iOS:** LightBlue app

These apps will show if your ESP32 is advertising as a BLE device named "LUIGI"

## MAC Address:

Current configured MAC: `84:1F:E8:69:2F:FE`

To find your ESP32's actual MAC address:

1. Upload the example code
2. Check Serial Monitor - it may print the MAC
3. Or use nRF Connect app to scan and find "LUIGI"
4. Update the MAC in `bluetooth_controller.dart` line 18
