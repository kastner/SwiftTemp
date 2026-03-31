import AppKit
import Foundation
import SwiftUI

@main
struct SwiftTempApp: App {
    @StateObject private var model = WeatherModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Text(model.menuBarText)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @ObservedObject var model: WeatherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let tempC = model.temperatureC {
                let tempF = (tempC * 9.0 / 5.0) + 32.0

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.1f°F / %.1f°C", tempF, tempC))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let locationSummary = model.locationSummary {
                        Text(locationSummary)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text("IP-based weather from Open-Meteo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if let coordinateSummary = model.coordinateSummary {
                        CopyValueRow(
                            title: "Coordinates",
                            value: coordinateSummary
                        )
                    }

                    if let geohash = model.geohash {
                        CopyValueRow(
                            title: "Geohash",
                            value: geohash
                        )
                    }
                }

                RefreshStatusView(nextRefreshDate: model.nextRefreshDate)

                Divider()

                HStack(spacing: 10) {
                    Button {
                        model.refresh()
                    } label: {
                        Label("Refresh Now", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "xmark.circle")
                    }
                    .keyboardShortcut("q")
                }
                .buttonStyle(.bordered)
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.red)

                if let locationSummary = model.locationSummary {
                    Text(locationSummary)
                        .foregroundStyle(.secondary)
                }

                RefreshStatusView(nextRefreshDate: model.nextRefreshDate)

                Divider()

                HStack(spacing: 10) {
                    Button {
                        model.refresh()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "xmark.circle")
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Text("Loading...")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)

                RefreshStatusView(nextRefreshDate: model.nextRefreshDate)
            }
        }
        .frame(width: 360)
        .padding(16)
    }
}

@MainActor
final class WeatherModel: ObservableObject {
    @Published var temperatureC: Double?
    @Published var errorMessage: String?
    @Published var locationSummary: String?
    @Published var coordinateSummary: String?
    @Published var geohash: String?
    @Published var nextRefreshDate: Date?

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 600

    var menuBarText: String {
        guard let temperatureC else {
            return "--°F --°C"
        }
        let temperatureF = (temperatureC * 9.0 / 5.0) + 32.0
        return String(format: "%.0f°F %.0f°C", temperatureF, temperatureC)
    }

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        nextRefreshDate = Date().addingTimeInterval(refreshInterval)

        Task {
            do {
                let location = try await fetchLocation()
                let temperature = try await fetchWeather(latitude: location.latitude, longitude: location.longitude)

                temperatureC = temperature
                errorMessage = nil
                locationSummary = Self.formatLocationSummary(from: location)
                coordinateSummary = Self.formatCoordinateSummary(latitude: location.latitude, longitude: location.longitude)
                geohash = Self.encodeGeohash(latitude: location.latitude, longitude: location.longitude)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fetchLocation() async throws -> IPLocationResponse {
        let url = URL(string: "https://ipapi.co/json/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(IPLocationResponse.self, from: data)

        if let error = response.error, error {
            throw WeatherError.locationFailed
        }

        return response
    }

    private func fetchWeather(latitude: Double, longitude: Double) async throws -> Double {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current_weather", value: "true")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return response.currentWeather.temperature
    }

    private static func formatLocationSummary(from location: IPLocationResponse) -> String {
        let city = location.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = location.regionCode ?? location.region
        let postal = location.postal?.trimmingCharacters(in: .whitespacesAndNewlines)

        let cityState = [city, state]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")

        if let postal, !postal.isEmpty, !cityState.isEmpty {
            return "\(cityState) \(postal)"
        }

        if !cityState.isEmpty {
            return cityState
        }

        return "Unknown location"
    }

    private static func formatCoordinateSummary(latitude: Double, longitude: Double) -> String {
        String(format: "GPS: %.5f, %.5f", latitude, longitude)
    }

    private static func encodeGeohash(latitude: Double, longitude: Double, precision: Int = 8) -> String {
        let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latitudeRange = (-90.0, 90.0)
        var longitudeRange = (-180.0, 180.0)
        var geohash = ""
        var bit = 0
        var characterBits = 0
        var isEncodingLongitude = true

        while geohash.count < precision {
            if isEncodingLongitude {
                let midpoint = (longitudeRange.0 + longitudeRange.1) / 2
                if longitude >= midpoint {
                    characterBits = (characterBits << 1) | 1
                    longitudeRange.0 = midpoint
                } else {
                    characterBits = characterBits << 1
                    longitudeRange.1 = midpoint
                }
            } else {
                let midpoint = (latitudeRange.0 + latitudeRange.1) / 2
                if latitude >= midpoint {
                    characterBits = (characterBits << 1) | 1
                    latitudeRange.0 = midpoint
                } else {
                    characterBits = characterBits << 1
                    latitudeRange.1 = midpoint
                }
            }

            isEncodingLongitude.toggle()
            bit += 1

            if bit == 5 {
                geohash.append(alphabet[characterBits])
                bit = 0
                characterBits = 0
            }
        }

        return geohash
    }
}

private struct CopyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)

                    Image(systemName: "clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .help("Copy \(title.lowercased())")
        }
    }
}

private struct RefreshStatusView: View {
    let nextRefreshDate: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(statusText(now: context.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusText(now: Date) -> String {
        guard let nextRefreshDate else {
            return "Refreshing via ipapi.co"
        }

        let timeText = nextRefreshDate.formatted(
            Date.FormatStyle()
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
        )

        let remaining = max(0, Int(nextRefreshDate.timeIntervalSince(now)))
        let minutes = remaining / 60
        let seconds = remaining % 60

        return String(format: "Next refresh at %@ (%dm %02ds)", timeText, minutes, seconds)
    }
}

private struct IPLocationResponse: Decodable {
    let city: String?
    let region: String?
    let regionCode: String?
    let postal: String?
    let latitude: Double
    let longitude: Double
    let error: Bool?

    enum CodingKeys: String, CodingKey {
        case city
        case region
        case regionCode = "region_code"
        case postal
        case latitude
        case longitude
        case error
    }
}

private struct ForecastResponse: Decodable {
    let currentWeather: CurrentWeather

    enum CodingKeys: String, CodingKey {
        case currentWeather = "current_weather"
    }
}

private struct CurrentWeather: Decodable {
    let temperature: Double
}

private enum WeatherError: LocalizedError {
    case locationFailed

    var errorDescription: String? {
        switch self {
        case .locationFailed:
            return "Could not determine location from your IP address"
        }
    }
}
