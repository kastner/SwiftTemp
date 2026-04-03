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

                    if let temperatureSourceSummary = model.temperatureSourceSummary {
                        Text(temperatureSourceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let observationSummary = model.observationSummary {
                        Text(observationSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    if let sunEventTitle = model.sunEventTitle, let sunEventValue = model.sunEventValue {
                        MetricRow(
                            title: sunEventTitle,
                            value: sunEventValue
                        )
                    }

                    if let uvIndexSummary = model.uvIndexSummary {
                        MetricRow(
                            title: "UV Index",
                            value: uvIndexSummary
                        )
                    }

                    if let airQualitySummary = model.airQualitySummary {
                        MetricRow(
                            title: "AQI",
                            value: airQualitySummary
                        )
                    }

                    if let openMeteoGridSummary = model.openMeteoGridSummary {
                        MetricRow(
                            title: "Open-Meteo Grid",
                            value: openMeteoGridSummary
                        )
                    }

                    if let nwsGridSummary = model.nwsGridSummary {
                        MetricRow(
                            title: "NWS Grid",
                            value: nwsGridSummary
                        )
                    }

                    if !model.stationTemperatureSummaries.isEmpty {
                        StationTemperatureListView(
                            title: "Nearby Stations",
                            values: model.stationTemperatureSummaries
                        )
                    }
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
    @Published var temperatureSourceSummary: String?
    @Published var coordinateSummary: String?
    @Published var geohash: String?
    @Published var sunEventTitle: String?
    @Published var sunEventValue: String?
    @Published var uvIndexSummary: String?
    @Published var airQualitySummary: String?
    @Published var observationSummary: String?
    @Published var openMeteoGridSummary: String?
    @Published var nwsGridSummary: String?
    @Published var stationTemperatureSummaries: [String] = []
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
                async let weatherTask = fetchWeather(latitude: location.latitude, longitude: location.longitude)
                async let airQualityTask = fetchAirQuality(latitude: location.latitude, longitude: location.longitude)
                async let nwsTask = fetchNationalWeatherServiceContext(latitude: location.latitude, longitude: location.longitude)

                let weather = try await weatherTask
                let airQuality = try? await airQualityTask
                let nwsContext = try? await nwsTask

                temperatureC = nwsContext?.averageTemperatureC ?? weather.temperatureC
                errorMessage = nil
                locationSummary = Self.formatLocationSummary(from: location)
                temperatureSourceSummary = nwsContext?.temperatureSourceSummary ?? "IP-based weather from Open-Meteo"
                coordinateSummary = Self.formatCoordinateSummary(latitude: location.latitude, longitude: location.longitude)
                geohash = Self.encodeGeohash(latitude: location.latitude, longitude: location.longitude)
                sunEventTitle = weather.sunEventTitle
                sunEventValue = weather.sunEventValue
                uvIndexSummary = Self.formatUVIndex(weather.uvIndex)
                airQualitySummary = Self.formatAirQuality(airQuality?.usAQI)
                observationSummary = nwsContext?.observationSummary ?? Self.formatObservationSummary(
                    time: weather.observationTime,
                    intervalSeconds: weather.observationIntervalSeconds,
                    timezoneIdentifier: weather.timezoneIdentifier
                )
                openMeteoGridSummary = Self.formatTemperatureSummary(
                    temperatureC: weather.temperatureC,
                    time: weather.observationTime,
                    timezoneIdentifier: weather.timezoneIdentifier,
                    includeCelsius: true
                )
                nwsGridSummary = nwsContext?.gridTemperatureSummary
                stationTemperatureSummaries = nwsContext?.stationTemperatureSummaries ?? []
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fetchData(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func fetchLocation() async throws -> IPLocationResponse {
        let url = URL(string: "https://ipapi.co/json/")!
        let data = try await fetchData(from: url)
        let response = try JSONDecoder().decode(IPLocationResponse.self, from: data)

        if let error = response.error, error {
            throw WeatherError.locationFailed
        }

        return response
    }

    private func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,is_day,uv_index"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let data = try await fetchData(from: components.url!)
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return WeatherSnapshot(
            temperatureC: response.current.temperature2m,
            uvIndex: response.current.uvIndex,
            sunEvent: Self.resolveSunEvent(currentTime: response.current.time, isDay: response.current.isDay, daily: response.daily, timezoneIdentifier: response.timezone),
            observationTime: response.current.time,
            observationIntervalSeconds: response.current.interval,
            timezoneIdentifier: response.timezone
        )
    }

    private func fetchAirQuality(latitude: Double, longitude: Double) async throws -> AirQualitySnapshot {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "us_aqi"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let data = try await fetchData(from: components.url!)
        let response = try JSONDecoder().decode(AirQualityResponse.self, from: data)
        return AirQualitySnapshot(usAQI: response.current.usAQI)
    }

    private func fetchNationalWeatherServiceContext(latitude: Double, longitude: Double) async throws -> NationalWeatherServiceContext {
        let headers = ["User-Agent": "SwiftTemp/1.0 (temperature comparison)"]
        let pointsURL = URL(string: "https://api.weather.gov/points/\(latitude),\(longitude)")!
        let pointsData = try await fetchData(from: pointsURL, headers: headers)
        let points = try JSONDecoder().decode(NWSPointsResponse.self, from: pointsData)

        async let hourlyDataTask = fetchData(from: URL(string: points.properties.forecastHourly)!, headers: headers)
        async let stationsDataTask = fetchData(from: URL(string: points.properties.observationStations)!, headers: headers)

        let hourlyData = try await hourlyDataTask
        let stationsData = try await stationsDataTask

        let hourlyForecast = try JSONDecoder().decode(NWSHourlyForecastResponse.self, from: hourlyData)
        let stations = try JSONDecoder().decode(NWSStationsResponse.self, from: stationsData)
        let gridTemperatureSummary = hourlyForecast.properties.periods.first.map(Self.formatNWSGridTemperatureSummary)
        let sortedStationIdentifiers = stations.features
            .sorted { lhs, rhs in
                Self.distanceInMeters(
                    latitudeA: latitude,
                    longitudeA: longitude,
                    latitudeB: lhs.geometry.coordinates[1],
                    longitudeB: lhs.geometry.coordinates[0]
                ) < Self.distanceInMeters(
                    latitudeA: latitude,
                    longitudeA: longitude,
                    latitudeB: rhs.geometry.coordinates[1],
                    longitudeB: rhs.geometry.coordinates[0]
                )
            }
            .map(\.properties.stationIdentifier)
        let stationObservations = try await fetchStationObservations(
            stationIdentifiers: Array(sortedStationIdentifiers.prefix(8)),
            headers: headers,
            limit: 3
        )

        return NationalWeatherServiceContext(
            averageTemperatureC: Self.averageTemperature(from: stationObservations),
            temperatureSourceSummary: Self.formatTemperatureSourceSummary(for: stationObservations.count),
            observationSummary: Self.formatStationObservationSummary(for: stationObservations),
            gridTemperatureSummary: gridTemperatureSummary,
            stationTemperatureSummaries: stationObservations.map(Self.formatStationTemperatureSummary)
        )
    }

    private func fetchStationObservations(stationIdentifiers: [String], headers: [String: String], limit: Int) async throws -> [NWSStationObservation] {
        var observations: [NWSStationObservation] = []

        for stationIdentifier in stationIdentifiers {
            if observations.count == limit {
                break
            }

            guard let url = URL(string: "https://api.weather.gov/stations/\(stationIdentifier)/observations/latest") else {
                continue
            }

            do {
                let data = try await fetchData(from: url, headers: headers)
                let observation = try JSONDecoder().decode(NWSObservationResponse.self, from: data)

                if let stationObservation = Self.makeStationObservation(
                    stationIdentifier: stationIdentifier,
                    observation: observation.properties
                ) {
                    observations.append(stationObservation)
                }
            } catch {
                continue
            }
        }

        return observations
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

    private static func resolveSunEvent(currentTime: String, isDay: Int, daily: DailyForecast, timezoneIdentifier: String) -> SunEvent? {
        if isDay == 1 {
            if let sunset = daily.sunset.first {
                return SunEvent(title: "Sunset", value: formatSunEventTime(sunset, timezoneIdentifier: timezoneIdentifier))
            }
            return nil
        }

        let sunrise = daily.sunrise.first(where: { $0 > currentTime }) ?? daily.sunrise.last
        guard let sunrise else {
            return nil
        }

        return SunEvent(title: "Sunrise", value: formatSunEventTime(sunrise, timezoneIdentifier: timezoneIdentifier))
    }

    private static func formatSunEventTime(_ value: String, timezoneIdentifier: String) -> String {
        guard let date = parseLocalDate(value, timezoneIdentifier: timezoneIdentifier) else {
            return value
        }

        let calendar = Calendar.current
        let dayPrefix: String
        if calendar.isDateInToday(date) {
            dayPrefix = ""
        } else if calendar.isDateInTomorrow(date) {
            dayPrefix = "Tomorrow "
        } else {
            dayPrefix = date.formatted(.dateTime.weekday(.abbreviated)) + " "
        }

        return dayPrefix + date.formatted(.dateTime.hour().minute())
    }

    private static func parseLocalDate(_ value: String, timezoneIdentifier: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: value)
    }

    private static func formatUVIndex(_ value: Double?) -> String? {
        guard let value else {
            return nil
        }

        return String(format: "%.1f", value)
    }

    private static func formatAirQuality(_ value: Double?) -> String? {
        guard let value else {
            return nil
        }

        let roundedValue = Int(value.rounded())
        return "\(roundedValue) (\(aqiCategory(for: roundedValue)))"
    }

    private static func formatObservationSummary(time: String, intervalSeconds: Int?, timezoneIdentifier: String) -> String {
        let timestamp: String
        if let date = parseLocalDate(time, timezoneIdentifier: timezoneIdentifier) {
            timestamp = date.formatted(.dateTime.hour().minute())
        } else {
            timestamp = time
        }

        guard let intervalSeconds, intervalSeconds > 0 else {
            return "Observed at \(timestamp)"
        }

        let intervalMinutes = max(1, intervalSeconds / 60)
        return "Observed at \(timestamp) (\(intervalMinutes)-minute cadence)"
    }

    private static func formatTemperatureSummary(temperatureC: Double, time: String, timezoneIdentifier: String, includeCelsius: Bool) -> String {
        let temperatureF = (temperatureC * 9.0 / 5.0) + 32.0
        let timestamp = parseLocalDate(time, timezoneIdentifier: timezoneIdentifier)?
            .formatted(.dateTime.hour().minute()) ?? time

        if includeCelsius {
            return String(format: "%.0f°F / %.1f°C at %@", temperatureF, temperatureC, timestamp)
        }

        return String(format: "%.0f°F at %@", temperatureF, timestamp)
    }

    private static func formatNWSGridTemperatureSummary(_ period: NWSHourlyPeriod) -> String {
        let timestamp = parseISODate(period.startTime)?.formatted(.dateTime.hour().minute()) ?? period.startTime
        return "\(period.temperature)°\(period.temperatureUnit) at \(timestamp)"
    }

    private static func makeStationObservation(stationIdentifier: String, observation: NWSObservationProperties) -> NWSStationObservation? {
        guard let temperatureC = observation.temperature.value else {
            return nil
        }

        return NWSStationObservation(
            stationIdentifier: stationIdentifier,
            timestamp: observation.timestamp,
            temperatureC: temperatureC
        )
    }

    private static func formatStationTemperatureSummary(_ observation: NWSStationObservation) -> String {
        let temperatureF = (observation.temperatureC * 9.0 / 5.0) + 32.0
        let timestamp = parseISODate(observation.timestamp)?.formatted(.dateTime.hour().minute()) ?? observation.timestamp
        return String(format: "%@ %.0f°F at %@", observation.stationIdentifier, temperatureF, timestamp)
    }

    private static func averageTemperature(from observations: [NWSStationObservation]) -> Double? {
        guard !observations.isEmpty else {
            return nil
        }

        let sum = observations.reduce(0.0) { partialResult, observation in
            partialResult + observation.temperatureC
        }
        return sum / Double(observations.count)
    }

    private static func formatTemperatureSourceSummary(for stationCount: Int) -> String? {
        guard stationCount > 0 else {
            return nil
        }

        return "Average of \(stationCount) closest NWS stations"
    }

    private static func formatStationObservationSummary(for observations: [NWSStationObservation]) -> String? {
        let dates = observations.compactMap { parseISODate($0.timestamp) }.sorted()
        guard let first = dates.first, let last = dates.last else {
            return nil
        }

        if first == last {
            return "Stations observed at \(first.formatted(.dateTime.hour().minute()))"
        }

        return "Stations observed \(first.formatted(.dateTime.hour().minute()))-\(last.formatted(.dateTime.hour().minute()))"
    }

    private static func distanceInMeters(latitudeA: Double, longitudeA: Double, latitudeB: Double, longitudeB: Double) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let lat1 = latitudeA * .pi / 180
        let lat2 = latitudeB * .pi / 180
        let deltaLat = (latitudeB - latitudeA) * .pi / 180
        let deltaLon = (longitudeB - longitudeA) * .pi / 180

        let haversine = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let angularDistance = 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
        return earthRadiusMeters * angularDistance
    }

    private static func parseISODate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func aqiCategory(for value: Int) -> String {
        switch value {
        case ..<0:
            return "Unknown"
        case 0...50:
            return "Good"
        case 51...100:
            return "Moderate"
        case 101...150:
            return "Unhealthy for Sensitive Groups"
        case 151...200:
            return "Unhealthy"
        case 201...300:
            return "Very Unhealthy"
        default:
            return "Hazardous"
        }
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

private struct MetricRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}

private struct StationTemperatureListView: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
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
    let timezone: String
    let current: CurrentForecast
    let daily: DailyForecast

    enum CodingKeys: String, CodingKey {
        case timezone
        case current
        case daily
    }
}

private struct CurrentForecast: Decodable {
    let time: String
    let interval: Int?
    let temperature2m: Double
    let isDay: Int
    let uvIndex: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case interval
        case temperature2m = "temperature_2m"
        case isDay = "is_day"
        case uvIndex = "uv_index"
    }
}

private struct DailyForecast: Decodable {
    let sunrise: [String]
    let sunset: [String]
}

private struct AirQualityResponse: Decodable {
    let current: CurrentAirQuality
}

private struct CurrentAirQuality: Decodable {
    let usAQI: Double?

    enum CodingKeys: String, CodingKey {
        case usAQI = "us_aqi"
    }
}

private struct WeatherSnapshot {
    let temperatureC: Double
    let uvIndex: Double?
    let sunEvent: SunEvent?
    let observationTime: String
    let observationIntervalSeconds: Int?
    let timezoneIdentifier: String

    var sunEventTitle: String? {
        sunEvent?.title
    }

    var sunEventValue: String? {
        sunEvent?.value
    }
}

private struct AirQualitySnapshot {
    let usAQI: Double?
}

private struct NationalWeatherServiceContext {
    let averageTemperatureC: Double?
    let temperatureSourceSummary: String?
    let observationSummary: String?
    let gridTemperatureSummary: String?
    let stationTemperatureSummaries: [String]
}

private struct SunEvent {
    let title: String
    let value: String
}

private struct NWSPointsResponse: Decodable {
    let properties: NWSPointProperties
}

private struct NWSPointProperties: Decodable {
    let forecastHourly: String
    let observationStations: String
}

private struct NWSHourlyForecastResponse: Decodable {
    let properties: NWSHourlyForecastProperties
}

private struct NWSHourlyForecastProperties: Decodable {
    let periods: [NWSHourlyPeriod]
}

private struct NWSHourlyPeriod: Decodable {
    let startTime: String
    let temperature: Int
    let temperatureUnit: String
}

private struct NWSStationsResponse: Decodable {
    let features: [NWSStationFeature]
}

private struct NWSStationFeature: Decodable {
    let geometry: NWSGeometry
    let properties: NWSStationProperties
}

private struct NWSGeometry: Decodable {
    let coordinates: [Double]
}

private struct NWSStationProperties: Decodable {
    let stationIdentifier: String
}

private struct NWSObservationResponse: Decodable {
    let properties: NWSObservationProperties
}

private struct NWSObservationProperties: Decodable {
    let timestamp: String
    let temperature: NWSQuantitativeValue
}

private struct NWSQuantitativeValue: Decodable {
    let value: Double?
}

private struct NWSStationObservation {
    let stationIdentifier: String
    let timestamp: String
    let temperatureC: Double
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
