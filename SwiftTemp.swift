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
    }
}

struct MenuContent: View {
    @ObservedObject var model: WeatherModel

    var body: some View {
        Group {
            if let tempC = model.temperatureC {
                let tempF = (tempC * 9.0 / 5.0) + 32.0

                Text(String(format: "%.1f°F / %.1f°C", tempF, tempC))
                    .font(.headline)

                if let locationName = model.locationName {
                    Text(locationName)
                        .foregroundStyle(.secondary)
                }

                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Button("Refresh Now") {
                    model.refresh()
                }
                .keyboardShortcut("r")
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)

                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Button("Retry") {
                    model.refresh()
                }
            } else {
                Text("Loading...")
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

@MainActor
final class WeatherModel: ObservableObject {
    @Published var temperatureC: Double?
    @Published var locationName: String?
    @Published var errorMessage: String?
    @Published var statusText = "Looking up IP-based location"

    private var refreshTimer: Timer?

    var menuBarText: String {
        guard let temperatureC else {
            return "--°F --°C"
        }
        let temperatureF = (temperatureC * 9.0 / 5.0) + 32.0
        return String(format: "%.0f°F %.0f°C", temperatureF, temperatureC)
    }

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        statusText = "Refreshing weather"

        Task {
            do {
                let location = try await fetchLocation()
                let temperature = try await fetchWeather(latitude: location.latitude, longitude: location.longitude)

                temperatureC = temperature
                locationName = location.city ?? "Current location"
                errorMessage = nil
                statusText = "IP-based location, updates every 10 minutes"
            } catch {
                temperatureC = nil
                errorMessage = error.localizedDescription
                statusText = "Last refresh failed"
            }
        }
    }

    private func fetchLocation() async throws -> IPLocationResponse {
        let url = URL(string: "https://ipwho.is/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(IPLocationResponse.self, from: data)

        guard response.success != false else {
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
}

private struct IPLocationResponse: Decodable {
    let city: String?
    let latitude: Double
    let longitude: Double
    let success: Bool?
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
