# Developer setup: the device loop

This is the loop used in Phase 0 to build, install and debug on a real phone **without a USB data cable**: the PC creates a Wi-Fi hotspot, the phone joins it, and `adb` talks to the phone over wireless debugging. The same network then carries the live view and clip traffic to a browser on the PC.

Reference device: Redmi Note 12 Pro 5G (Android 14 / HyperOS 2). Host: Windows 11.

## 1. Network: a Windows Mobile Hotspot

1. Windows Settings → Network & internet → **Mobile hotspot**.
2. Share from your current connection (Wi-Fi is fine: Windows can share Wi-Fi over Wi-Fi), over **Wi-Fi**. Turn it on.
3. Connect the phone to the hotspot SSID. The PC is the gateway (usually `192.168.137.1`); the phone gets a `192.168.137.x` address.

**Why not just use the building Wi-Fi?** Public, university and many corporate networks enable *client isolation*: devices on the same access point cannot reach each other. `adb`, the WebRTC live view and the clip server all need direct device-to-device traffic, so they silently fail there. A home router usually works; a PC or phone hotspot always does.

## 2. Phone: developer options and wireless debugging

1. Settings → About phone → tap **OS version** (on HyperOS; "Build number" on most other phones) 7 times to unlock Developer options.
2. Developer options → enable **Wireless debugging**.

### Xiaomi / HyperOS specifics

- Enable **Install via USB**. It requires being signed in with a Mi account. Without it, `adb install` fails even over Wi-Fi.
- Optionally enable **USB debugging (Security settings)**. Needed for `adb install -g` (grant all runtime permissions) and `adb shell pm grant` to work; without it, grant permissions on the phone instead.
- Each `adb install` shows a confirmation prompt on the phone. Accept it, or the install times out.

## 3. Pair and connect

On the phone: Wireless debugging → **Pair device with pairing code**. It shows an IP, a pairing port and a 6-digit code.

```sh
adb pair 192.168.137.x:PAIR_PORT CODE     # once per PC
adb connect 192.168.137.x:PORT            # PORT is the one on the main Wireless debugging screen, not the pairing port
adb devices                               # should list the phone
```

The connect port changes whenever wireless debugging restarts (reboot, toggling Wi-Fi). Pairing persists; just run `adb connect` again with the new port.

## 4. Build and install

```sh
cd app && flutter build apk --debug
adb install -r app/build/app/outputs/flutter-apk/app-debug.apk   # from the repo root
```

`flutter run` also works over the wireless connection and gives hot reload.

## 5. Logs

```sh
adb logcat -b crash                                              # native and Java crashes only
adb logcat --pid=$(adb shell pidof -s io.github.instantreplay.instant_replay)
adb logcat -s rtc                                                # libwebrtc native logs
```

Filtering by pid keeps the output readable; re-run it after the app restarts (the pid changes). In PowerShell, run `adb shell pidof -s io.github.instantreplay.instant_replay` first and pass the number to `--pid`.

## 6. The Lab harness (spike)

The Phase 0 spike (branch `spike/phase-0`) runs a small HTTP server on the phone, port **8080**:

- `http://PHONE_IP:8080/` - save buttons, clip list and live stats; clips are served under `/clips/`.
- `http://PHONE_IP:8080/live` - WebRTC live view with an on-screen millisecond clock. Point the camera at this page: the clock next to its own image in the video gives the glass-to-glass latency in one screenshot.
- `http://PHONE_IP:8080/api/stats` - JSON capture stats, polled once per second by the index page.

## Known gotchas

- **libwebrtc aborts natively** with `jvm.cc ... Check failed` if the app lacks the `ACCESS_NETWORK_STATE` permission. It looks like a random crash; check `adb logcat -b crash` and the manifest.
- Native WebRTC logging is enabled at `LS_ERROR`, so `RTC_CHECK` failures show up in logcat under the tag **`rtc`** before the abort.
- **Weak chargers** may not keep up with continuous capture + encoding + Wi-Fi: the battery drains even while plugged in. Use a strong charger for long runs and watch the battery level.
- Wireless debugging turns itself off when the phone leaves the network; re-enable it and `adb connect` again.
