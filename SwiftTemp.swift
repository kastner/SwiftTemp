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

                    if model.yolinkTemperatureDevices.count > 1 {
                        HStack(spacing: 4) {
                            Text("Observed by")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker(
                                "YoLink Sensor",
                                selection: Binding(
                                    get: { model.selectedYoLinkDeviceId },
                                    set: { model.selectYoLinkDevice(deviceId: $0) }
                                )
                            ) {
                                ForEach(model.yolinkTemperatureDevices) { device in
                                    Text(device.name).tag(device.deviceId)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .controlSize(.small)
                        }
                    } else if let observationSummary = model.observationSummary {
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
    @Published var yolinkTemperatureDevices: [YoLinkDevice] = []
    @Published var selectedYoLinkDeviceId: String = UserDefaults.standard.string(forKey: selectedYoLinkDeviceIdDefaultsKey) ?? ""

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 600
    private let stationCandidateLimit = 12
    private let stationUsedLimit = 8
    private let maxStationObservationAgeMinutes = 90.0
    private let yolinkConfig = YoLinkConfig.fromEnvironment()
    private static let selectedYoLinkDeviceIdDefaultsKey = "selectedYoLinkDeviceId"

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
                let yolinkSnapshot = try? await fetchYoLinkTemperature()

                temperatureC = yolinkSnapshot?.temperatureC ?? nwsContext?.averageTemperatureC ?? weather.temperatureC
                errorMessage = nil
                locationSummary = Self.formatLocationSummary(from: location)
                temperatureSourceSummary = yolinkSnapshot?.sourceSummary ?? nwsContext?.temperatureSourceSummary ?? "IP-based weather from Open-Meteo"
                coordinateSummary = Self.formatCoordinateSummary(latitude: location.latitude, longitude: location.longitude)
                geohash = Self.encodeGeohash(latitude: location.latitude, longitude: location.longitude)
                sunEventTitle = weather.sunEventTitle
                sunEventValue = weather.sunEventValue
                uvIndexSummary = Self.formatUVIndex(weather.uvIndex)
                airQualitySummary = Self.formatAirQuality(airQuality?.usAQI)
                observationSummary = yolinkSnapshot?.observationSummary ?? nwsContext?.observationSummary ?? Self.formatObservationSummary(
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

    func selectYoLinkDevice(deviceId: String) {
        UserDefaults.standard.set(deviceId, forKey: Self.selectedYoLinkDeviceIdDefaultsKey)
        refresh()
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

    private func fetchYoLinkTemperature() async throws -> YoLinkTemperatureSnapshot? {
        guard let yolinkConfig else {
            return nil
        }

        let accessToken = try await fetchYoLinkAccessToken(config: yolinkConfig)
        let device = try await resolveYoLinkTemperatureDevice(config: yolinkConfig, accessToken: accessToken)
        let response = try await sendYoLinkAPIRequest(
            accessToken: accessToken,
            packet: YoLinkRequestPacket(
                method: "THSensor.getState",
                time: Self.currentMilliseconds(),
                targetDevice: device.deviceId,
                token: device.token,
                params: nil
            ),
            responseType: YoLinkTHSensorStateResponse.self
        )

        guard response.code == "000000" else {
            throw WeatherError.yolinkFailed(response.desc ?? response.code)
        }

        return YoLinkTemperatureSnapshot(
            temperatureC: response.data.state.temperature,
            humidity: response.data.state.humidity,
            reportDate: Self.parseISODate(response.data.reportAt),
            deviceName: device.name
        )
    }

    private func fetchYoLinkAccessToken(config: YoLinkConfig) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.yosmart.com/open/yolink/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: config.uaid),
            URLQueryItem(name: "client_secret", value: config.secret)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(YoLinkTokenResponse.self, from: data).accessToken
    }

    private func resolveYoLinkTemperatureDevice(config: YoLinkConfig, accessToken: String) async throws -> YoLinkDevice {
        if let deviceId = config.deviceId, let token = config.deviceToken {
            let device = YoLinkDevice(deviceId: deviceId, name: config.deviceName ?? "YoLink outdoor sensor", token: token, type: "THSensor")
            yolinkTemperatureDevices = [device]
            selectedYoLinkDeviceId = device.deviceId
            return device
        }

        let response = try await sendYoLinkAPIRequest(
            accessToken: accessToken,
            packet: YoLinkRequestPacket(
                method: "Home.getDeviceList",
                time: Self.currentMilliseconds(),
                targetDevice: nil,
                token: nil,
                params: nil
            ),
            responseType: YoLinkDeviceListResponse.self
        )

        guard response.code == "000000" else {
            throw WeatherError.yolinkFailed(response.desc ?? response.code)
        }

        let temperatureDevices = response.data.devices.filter { $0.type == "THSensor" }
        yolinkTemperatureDevices = temperatureDevices

        guard !temperatureDevices.isEmpty else {
            throw WeatherError.yolinkFailed("No YoLink temperature/humidity sensor found")
        }

        let savedDeviceId = UserDefaults.standard.string(forKey: Self.selectedYoLinkDeviceIdDefaultsKey)
        let device = temperatureDevices.first { $0.deviceId == savedDeviceId } ?? temperatureDevices[0]
        selectedYoLinkDeviceId = device.deviceId
        UserDefaults.standard.set(device.deviceId, forKey: Self.selectedYoLinkDeviceIdDefaultsKey)
        return device
    }

    private func sendYoLinkAPIRequest<Response: Decodable>(
        accessToken: String,
        packet: YoLinkRequestPacket,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://api.yosmart.com/open/yolink/v2/api")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(packet)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(responseType, from: data)
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
        let sortedStations = stations.features
            .compactMap { station -> NWSStationDistance? in
                guard station.geometry.coordinates.count >= 2 else {
                    return nil
                }

                let distanceMeters = Self.distanceInMeters(
                    latitudeA: latitude,
                    longitudeA: longitude,
                    latitudeB: station.geometry.coordinates[1],
                    longitudeB: station.geometry.coordinates[0]
                )

                return NWSStationDistance(
                    stationIdentifier: station.properties.stationIdentifier,
                    distanceMeters: distanceMeters
                )
            }
            .sorted { lhs, rhs in
                lhs.distanceMeters < rhs.distanceMeters
            }
        let stationObservations = try await fetchStationObservations(
            stations: Array(sortedStations.prefix(stationCandidateLimit)),
            headers: headers,
            maxAgeMinutes: maxStationObservationAgeMinutes
        )
        let weightedStations = Array(
            stationObservations
                .sorted { lhs, rhs in lhs.weight > rhs.weight }
                .prefix(stationUsedLimit)
        )

        return NationalWeatherServiceContext(
            averageTemperatureC: Self.weightedAverageTemperature(from: weightedStations),
            temperatureSourceSummary: Self.formatTemperatureSourceSummary(
                usedStationCount: weightedStations.count,
                availableStationCount: stations.features.count
            ),
            observationSummary: Self.formatStationObservationSummary(for: weightedStations),
            gridTemperatureSummary: gridTemperatureSummary,
            stationTemperatureSummaries: weightedStations.map(Self.formatStationTemperatureSummary)
        )
    }

    private func fetchStationObservations(stations: [NWSStationDistance], headers: [String: String], maxAgeMinutes: Double) async throws -> [NWSStationObservation] {
        var observations: [NWSStationObservation] = []

        for station in stations {
            guard let url = URL(string: "https://api.weather.gov/stations/\(station.stationIdentifier)/observations/latest") else {
                continue
            }

            do {
                let data = try await fetchData(from: url, headers: headers)
                let observation = try JSONDecoder().decode(NWSObservationResponse.self, from: data)

                if let stationObservation = Self.makeStationObservation(
                    stationIdentifier: station.stationIdentifier,
                    distanceMeters: station.distanceMeters,
                    observation: observation.properties,
                    maxAgeMinutes: maxAgeMinutes
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
        let decimal = String(format: "%.5f, %.5f", latitude, longitude)
        let dms = "\(formatCoordinateDMS(latitude, positiveSuffix: "N", negativeSuffix: "S")) \(formatCoordinateDMS(longitude, positiveSuffix: "E", negativeSuffix: "W"))"
        return "\(decimal) | \(dms)"
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

    private static func makeStationObservation(
        stationIdentifier: String,
        distanceMeters: Double,
        observation: NWSObservationProperties,
        maxAgeMinutes: Double
    ) -> NWSStationObservation? {
        guard let temperatureC = observation.temperature.value,
              let observationDate = parseISODate(observation.timestamp) else {
            return nil
        }

        let ageMinutes = max(0, Date().timeIntervalSince(observationDate) / 60)
        guard ageMinutes <= maxAgeMinutes else {
            return nil
        }

        let distanceKilometers = distanceMeters / 1_000
        let distanceWeight = 1 / max(1, sqrt(distanceKilometers + 1))
        let recencyWeight = exp(-ageMinutes / 45)
        let weight = distanceWeight * recencyWeight

        return NWSStationObservation(
            stationIdentifier: stationIdentifier,
            timestamp: observation.timestamp,
            temperatureC: temperatureC,
            distanceMeters: distanceMeters,
            ageMinutes: ageMinutes,
            weight: weight
        )
    }

    private static func formatStationTemperatureSummary(_ observation: NWSStationObservation) -> String {
        let temperatureF = (observation.temperatureC * 9.0 / 5.0) + 32.0
        let distanceMiles = observation.distanceMeters / 1_609.344
        return String(
            format: "%@ %.0f°F %.0fmi %.0fm ago",
            observation.stationIdentifier,
            temperatureF,
            distanceMiles,
            observation.ageMinutes
        )
    }

    private static func weightedAverageTemperature(from observations: [NWSStationObservation]) -> Double? {
        guard !observations.isEmpty else {
            return nil
        }

        let weightSum = observations.reduce(0.0) { partialResult, observation in
            partialResult + observation.weight
        }
        guard weightSum > 0 else {
            return nil
        }

        let weightedTemperatureSum = observations.reduce(0.0) { partialResult, observation in
            partialResult + (observation.temperatureC * observation.weight)
        }
        return weightedTemperatureSum / weightSum
    }

    private static func formatTemperatureSourceSummary(usedStationCount: Int, availableStationCount: Int) -> String? {
        guard usedStationCount > 0 else {
            return nil
        }

        return "Weighted avg of \(usedStationCount) nearby NWS stations (\(availableStationCount) available)"
    }

    private static func formatStationObservationSummary(for observations: [NWSStationObservation]) -> String? {
        let ages = observations.map(\.ageMinutes).sorted()
        guard let youngest = ages.first, let oldest = ages.last else {
            return nil
        }

        if youngest == oldest {
            return String(format: "Distance + recency weighted, %.0fm old", youngest)
        }

        return String(format: "Distance + recency weighted, %.0f-%.0fm old", youngest, oldest)
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

    private static func currentMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private static func formatCoordinateDMS(_ coordinate: Double, positiveSuffix: String, negativeSuffix: String) -> String {
        let absoluteCoordinate = abs(coordinate)
        let degrees = Int(absoluteCoordinate)
        let minutesFull = (absoluteCoordinate - Double(degrees)) * 60
        let minutes = Int(minutesFull)
        let seconds = (minutesFull - Double(minutes)) * 60
        let suffix = coordinate >= 0 ? positiveSuffix : negativeSuffix
        return String(format: "%d°%02d'%02.0f\"%@", degrees, minutes, seconds, suffix)
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

private struct YoLinkConfig {
    let uaid: String
    let secret: String
    let deviceId: String?
    let deviceToken: String?
    let deviceName: String?

    static func fromEnvironment() -> YoLinkConfig? {
        let environment = ProcessInfo.processInfo.environment
        guard let uaid = trimmedEnvironmentValue("YOLINK_UAID", from: environment),
              let secret = trimmedEnvironmentValue("YOLINK_SECRET", from: environment) else {
            return nil
        }

        return YoLinkConfig(
            uaid: uaid,
            secret: secret,
            deviceId: trimmedEnvironmentValue("YOLINK_DEVICE_ID", from: environment),
            deviceToken: trimmedEnvironmentValue("YOLINK_DEVICE_TOKEN", from: environment),
            deviceName: trimmedEnvironmentValue("YOLINK_DEVICE_NAME", from: environment)
        )
    }

    private static func trimmedEnvironmentValue(_ key: String, from environment: [String: String]) -> String? {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}

private struct YoLinkTemperatureSnapshot {
    let temperatureC: Double
    let humidity: Double?
    let reportDate: Date?
    let deviceName: String

    var sourceSummary: String {
        let temperatureF = (temperatureC * 9.0 / 5.0) + 32.0
        let temperatureText = String(format: "%.1f°F / %.1f°C", temperatureF, temperatureC)

        if let humidity {
            return String(format: "%@ via YoLink, %@, %.0f%% humidity", deviceName, temperatureText, humidity)
        }

        return "\(deviceName) via YoLink, \(temperatureText)"
    }

    var observationSummary: String {
        guard let reportDate else {
            return "Observed by YoLink outdoor sensor"
        }

        let timestamp = reportDate.formatted(.dateTime.hour().minute())
        let ageMinutes = max(0, Date().timeIntervalSince(reportDate) / 60)
        return String(format: "YoLink reported at %@ (%.0fm old)", timestamp, ageMinutes)
    }
}

private struct YoLinkTokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct YoLinkRequestPacket: Encodable {
    let method: String
    let time: Int64
    let targetDevice: String?
    let token: String?
    let params: [String: String]?
}

private struct YoLinkBaseResponse<Data: Decodable>: Decodable {
    let code: String
    let desc: String?
    let data: Data
}

private typealias YoLinkDeviceListResponse = YoLinkBaseResponse<YoLinkDeviceListData>
private typealias YoLinkTHSensorStateResponse = YoLinkBaseResponse<YoLinkTHSensorStateData>

private struct YoLinkDeviceListData: Decodable {
    let devices: [YoLinkDevice]
}

struct YoLinkDevice: Decodable, Identifiable {
    let deviceId: String
    let name: String
    let token: String
    let type: String

    var id: String {
        deviceId
    }
}

private struct YoLinkTHSensorStateData: Decodable {
    let online: Bool
    let state: YoLinkTHSensorState
    let reportAt: String
}

private struct YoLinkTHSensorState: Decodable {
    let temperature: Double
    let humidity: Double?
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

private struct NWSStationDistance {
    let stationIdentifier: String
    let distanceMeters: Double
}

private struct NWSStationObservation {
    let stationIdentifier: String
    let timestamp: String
    let temperatureC: Double
    let distanceMeters: Double
    let ageMinutes: Double
    let weight: Double
}

private enum WeatherError: LocalizedError {
    case locationFailed
    case yolinkFailed(String)

    var errorDescription: String? {
        switch self {
        case .locationFailed:
            return "Could not determine location from your IP address"
        case .yolinkFailed(let message):
            return "Could not load YoLink temperature: \(message)"
        }
    }
}
