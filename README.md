# SwiftTemp

SwiftUI menu bar app that shows the current temperature in Fahrenheit and Celsius.

## Notes

- This version is intentionally minimal: one Swift source file plus this README.
- It uses IP-based geolocation instead of CoreLocation, so it does not need app bundles, entitlements, or location permission prompts.
- Weather data comes from [Open-Meteo](https://open-meteo.com/). IP lookup comes from [ipapi.co](https://ipapi.co/).

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
