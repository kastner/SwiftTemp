# SwiftTemp

SwiftUI menu bar app that shows the current temperature in Fahrenheit and Celsius, plus sun timing, UV index, and AQI.

> [!CAUTION]
> This app was "vibe coded" with Opus 4.6, GPT-5.4, and Sonnet 4.6. Do not use it as is, do not trust this code!

## Notes

- This version is intentionally minimal: one Swift source file plus this README.
- It uses IP-based geolocation instead of CoreLocation, so it does not need app bundles, entitlements, or location permission prompts.
- Weather and air-quality data come from [Open-Meteo](https://open-meteo.com/). IP lookup comes from [ipapi.co](https://ipapi.co/).
- If YoLink credentials are configured, the menu bar temperature comes from your YoLink temperature/humidity sensor and the weather APIs remain fallbacks/context.

## Build

```bash
git clone <your-repo-url>
cd SwiftTemp
swiftc -parse-as-library -framework SwiftUI -framework AppKit -o SwiftTemp SwiftTemp.swift
```

## Run

```bash
./SwiftTemp
```

The app lives in the macOS menu bar and refreshes automatically every 10 minutes.

## YoLink Outdoor Sensor

YoLink support is optional. Without these values, SwiftTemp keeps using the existing NWS/Open-Meteo source.

1. In the YoLink app, create Personal Access Credentials from Account -> Advanced Settings -> Personal Access Credentials.
2. Run the app with the credential values:

```bash
YOLINK_UAID="..." YOLINK_SECRET="..." ./SwiftTemp
```

If your account has more than one YoLink `THSensor`, SwiftTemp shows a YoLink Sensor picker in the menu and remembers your choice. You can also hard-code a device with exact device values:

```bash
YOLINK_UAID="..." \
YOLINK_SECRET="..." \
YOLINK_DEVICE_ID="..." \
YOLINK_DEVICE_TOKEN="..." \
YOLINK_DEVICE_NAME="Outdoor North Side" \
./SwiftTemp
```

You can get `YOLINK_DEVICE_ID` and `YOLINK_DEVICE_TOKEN` from YoLink's `Home.getDeviceList` API response. The app calls `THSensor.getState` every 10 minutes and displays the reported temperature, humidity, and report age.

## Launch At Startup

Because this project is a bare executable rather than a bundled `.app`, the simplest startup option is a per-user `launchd` agent managed by the included script.

1. Build the binary:

```bash
swiftc -parse-as-library -framework SwiftUI -framework AppKit -o SwiftTemp SwiftTemp.swift
```

2. Add it to startup:

```bash
./startup.sh add
```

If you use YoLink, set the YoLink environment variables when adding or updating the login item so `launchd` can pass them to the app:

```bash
YOLINK_UAID="..." YOLINK_SECRET="..." ./startup.sh add
```

3. If you rebuild the binary later, reload the login item:

```bash
./startup.sh update
```

4. To remove it from startup:

```bash
./startup.sh remove
```

The script writes `~/Library/LaunchAgents/com.kastner.swifttemp.plist` pointing at the `SwiftTemp` binary in this checkout. If you move the checkout, run `./startup.sh update`.
