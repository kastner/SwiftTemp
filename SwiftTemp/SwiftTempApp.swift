import SwiftUI
import CoreLocation

@main
struct SwiftTempApp: App {
    @StateObject private var weatherManager = WeatherManager()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(weatherManager: weatherManager)
        } label: {
            Text(weatherManager.menuBarText)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var weatherManager: WeatherManager

    var body: some View {
        if let temp = weatherManager.temperatureC {
            let f = temp * 9.0 / 5.0 + 32.0
            Text(String(format: "%.1f°F / %.1f°C", f, temp))
                .font(.headline)

            if let name = weatherManager.locationName {
                Text(name)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Updates every 10 minutes")
                .foregroundStyle(.secondary)
                .font(.caption)

            Button("Refresh Now") {
                weatherManager.refresh()
            }
            .keyboardShortcut("r")
        } else if let error = weatherManager.errorMessage {
            Text(error)
                .foregroundStyle(.red)
            Button("Retry") {
                weatherManager.refresh()
            }
        } else {
            Text("Loading...")
        }

        Divider()

        Text("v\(WeatherManager.version) · \(weatherManager.locationSource)")
            .foregroundStyle(.secondary)
            .font(.caption)

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let version = "0.10"

    private static let logFile: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("swifttemp.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return url
    }()

    static func log(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        NSLog("SwiftTemp: %@", msg)
        if let data = line.data(using: .utf8),
           let fh = try? FileHandle(forWritingTo: logFile) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        }
    }

    @Published var temperatureC: Double?
    @Published var locationName: String?
    @Published var errorMessage: String?
    @Published var locationSource: String = "pending"

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var lastLocation: CLLocation?
    private var gotCoreLocation = false


    var menuBarText: String {
        guard let temp = temperatureC else {
            return "🌡 --°F --°C"
        }
        let f = temp * 9.0 / 5.0 + 32.0
        return String(format: "%.0f°F %.0f°C", f, temp)
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers

        WeatherManager.log("locationServicesEnabled=\(CLLocationManager.locationServicesEnabled())")
        WeatherManager.log("authStatus=\(locationManager.authorizationStatus.rawValue)")

        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()

        // Also try significant location changes (uses cell/wifi, lower bar than GPS)
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            WeatherManager.log("Starting significant location change monitoring")
            locationManager.startMonitoringSignificantLocationChanges()
        }

        // After auth, try reading cached location directly
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, !self.gotCoreLocation else { return }
            if let cached = self.locationManager.location {
                WeatherManager.log("Using cached location: \(cached.coordinate.latitude), \(cached.coordinate.longitude) age=\(cached.timestamp.timeIntervalSinceNow)s")
                self.gotCoreLocation = true
                DispatchQueue.main.async { self.locationSource = "Location Services (cached)" }
                self.reverseGeocode(cached)
                self.fetchWeather(lat: cached.coordinate.latitude, lon: cached.coordinate.longitude)
                self.lastLocation = cached
                return
            }
            WeatherManager.log("No cached location available")
        }

        // IP fallback if nothing works after 6s
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self, !self.gotCoreLocation else { return }
            WeatherManager.log("CoreLocation hasn't delivered, using IP fallback")
            self.fallbackToIPLocation()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.fetchWeatherIfPossible()
        }
    }

    func refresh() {
        gotCoreLocation = false
        DispatchQueue.main.async { self.locationSource = "refreshing..." }
        locationManager.startUpdatingLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, !self.gotCoreLocation else { return }
            self.fallbackToIPLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        gotCoreLocation = true
        locationManager.stopUpdatingLocation()
        WeatherManager.log("CoreLocation success: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        DispatchQueue.main.async { self.locationSource = "Location Services" }
        reverseGeocode(location)
        fetchWeather(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as NSError).code
        WeatherManager.log("CoreLocation error code=\(code): \(error.localizedDescription)")
        // code 0 = kCLErrorLocationUnknown (transient, keep trying)
        // code 1 = kCLErrorDenied (auth problem)
        if code == 1 {
            WeatherManager.log("Location denied (error code 1), falling back to IP")
            fallbackToIPLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        WeatherManager.log("auth changed to \(status.rawValue)")
        switch status {
        case .authorized, .authorizedAlways:
            WeatherManager.log("authorized, starting location updates")
            manager.startUpdatingLocation()
        case .denied, .restricted:
            WeatherManager.log("denied/restricted, using IP fallback")
            if temperatureC == nil {
                fallbackToIPLocation()
            }
            DispatchQueue.main.async { self.locationSource = "IP (location denied)" }
        case .notDetermined:
            DispatchQueue.main.async { self.locationSource = "waiting for permission" }
        @unknown default:
            break
        }
    }

    private func fallbackToIPLocation() {
        guard let url = URL(string: "https://ipwho.is/") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                WeatherManager.log("IP geolocation error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["latitude"] as? Double,
                  let lon = json["longitude"] as? Double else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no data"
                WeatherManager.log("IP geolocation parse failed: \(body)")
                DispatchQueue.main.async {
                    self?.errorMessage = "Could not determine location"
                }
                return
            }
            let city = json["city"] as? String
            WeatherManager.log("IP geolocation success: \(city ?? "?") (\(lat), \(lon))")
            DispatchQueue.main.async {
                self?.locationName = city
                self?.locationSource = "IP geolocation"
            }
            self?.lastLocation = CLLocation(latitude: lat, longitude: lon)
            self?.fetchWeather(lat: lat, lon: lon)
        }.resume()
    }

    private func reverseGeocode(_ location: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            if let name = placemarks?.first?.locality {
                DispatchQueue.main.async {
                    self?.locationName = name
                }
            }
        }
    }

    private func fetchWeatherIfPossible() {
        gotCoreLocation = false
        locationManager.startUpdatingLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, !self.gotCoreLocation else { return }
            if let loc = self.lastLocation {
                self.fetchWeather(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
            } else {
                self.fallbackToIPLocation()
            }
        }
    }

    private func fetchWeather(lat: Double, lon: Double) {
        let urlString = String(
            format: "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current_weather=true",
            lat, lon
        )
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Network error"
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let current = json["current_weather"] as? [String: Any],
                   let temp = current["temperature"] as? Double {
                    DispatchQueue.main.async {
                        self?.temperatureC = temp
                        self?.errorMessage = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Parse error"
                }
            }
        }.resume()
    }
}
