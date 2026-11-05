import CoreLocation
import Foundation
import Observation
import os
import ShelfCore

/// Weather per place, refreshed every 20 minutes. A place is a typed city or the current location.
@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    struct Place: Hashable, Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private(set) var reports: [String: (place: Place, report: WeatherReport, fetched: Date)] = [:]
    private(set) var currentLocation: Place?
    private(set) var locationDenied = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var inFlight: Set<String> = []
    /// Last attempt per place, so a failing lookup is retried at most once a minute rather than on every redraw.
    @ObservationIgnored private var lastAttempt: [String: Date] = [:]
    static let retryInterval: TimeInterval = 60
    @ObservationIgnored nonisolated private static let logger = Logger(subsystem: "app.shelf", category: "weather")
    static let refreshInterval: TimeInterval = 20 * 60

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    /// `city` empty means "here".
    func report(for city: String, fahrenheit: Bool) -> (place: Place, report: WeatherReport)? {
        let key = cacheKey(city, fahrenheit)
        if let entry = reports[key] {
            if Date().timeIntervalSince(entry.fetched) > Self.refreshInterval { load(city, fahrenheit: fahrenheit) }
            return (entry.place, entry.report)
        }
        load(city, fahrenheit: fahrenheit)
        return nil
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: locationDenied = true
        default: manager.requestLocation()
        }
    }

    private func cacheKey(_ city: String, _ fahrenheit: Bool) -> String {
        "\(city.lowercased())|\(fahrenheit)"
    }

    private func load(_ city: String, fahrenheit: Bool) {
        let key = cacheKey(city, fahrenheit)
        guard !inFlight.contains(key) else { return }
        if let last = lastAttempt[key], Date().timeIntervalSince(last) < Self.retryInterval { return }
        lastAttempt[key] = Date()
        let trimmed = city.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty, currentLocation == nil {
            requestLocation()
            return
        }
        inFlight.insert(key)
        Task {
            defer { inFlight.remove(key) }
            do {
                let place = trimmed.isEmpty ? currentLocation : try await Self.geocode(trimmed)
                guard let place else { return }
                let report = try await OpenMeteoClient.fetch(latitude: place.latitude, longitude: place.longitude, fahrenheit: fahrenheit)
                reports[key] = (place, report, Date())
            } catch {
                Self.logger.error("Weather failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Open-Meteo geocoding (free, no key).
    static func geocode(_ name: String) async throws -> Place? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "1")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        struct Response: Decodable {
            struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double }
            let results: [Result]?
        }
        guard let first = try JSONDecoder().decode(Response.self, from: data).results?.first else { return nil }
        return Place(name: first.name, latitude: first.latitude, longitude: first.longitude)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            locationDenied = status == .denied || status == .restricted
            if status != .notDetermined, status != .denied, status != .restricted { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        MainActor.assumeIsolated {
            currentLocation = Place(name: "Current Location", latitude: coordinate.latitude, longitude: coordinate.longitude)
            reports = reports.filter { !$0.key.hasPrefix("|") }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.logger.error("Location failed: \(error.localizedDescription, privacy: .public)")
    }
}
