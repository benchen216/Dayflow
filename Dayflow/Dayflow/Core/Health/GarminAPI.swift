//
//  GarminAPI.swift
//  Dayflow
//
//  Talks to the Garmin Connect Personal API (https://personal.connectapi.garmin.com). The
//  developer key from the Keychain is traded for a bearer token that lasts about a day; there
//  is no refresh token, so a new one is requested when it runs out. The token lives in memory
//  only. Paths follow Garmin's own client, github.com/garmin/connect-personal-api-python.
//

import Foundation

protocol GarminTransport: Sendable {
  func send(_ request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionGarminTransport: GarminTransport {
  func send(_ request: URLRequest) async throws -> (Data, Int) {
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }
}

enum GarminAPIError: Error, Equatable {
  /// Garmin refused the key: it expired or was deleted in the developer portal.
  case keyRejected
  case http(Int)
  case badToken
}

struct GarminFetchResult: Equatable, Sendable {
  var days: [GarminDay]
  var samples: [GarminSample]
}

actor GarminAPI {
  static let baseURL = URL(string: "https://personal.connectapi.garmin.com")!
  private static let tokenPath =
    "/personalapitoken-service/personal-api/personal-api-key/token"
  /// Tokens are good for about 24 hours; renew a little early.
  static let tokenLifetime: TimeInterval = 23 * 60 * 60

  private let transport: GarminTransport
  private let apiKey: @Sendable () -> String?
  private let now: @Sendable () -> Date
  private var token: (value: String, expires: Date)?

  init(
    transport: GarminTransport = URLSessionGarminTransport(),
    apiKey: @escaping @Sendable () -> String? = { GarminCredentials.key },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.transport = transport
    self.apiKey = apiKey
    self.now = now
  }

  /// Forgets the token, e.g. after the key was replaced.
  func reset() { token = nil }

  /// Daily stress, Body Battery, HRV and heart rate for the inclusive local day range, plus
  /// Body Battery points, HRV sleep readings and the all-day heart rate series.
  func fetch(days: [String]) async throws -> GarminFetchResult {
    guard let first = days.first, let last = days.last else {
      return GarminFetchResult(days: [], samples: [])
    }
    let stress = try GarminDecoding.stressDays(
      from: await get("/usersummary-service/stats/stress/daily/\(first)/\(last)"))
    let battery = try GarminDecoding.bodyBattery(
      from: await get(
        "/wellness-service/wellness/bodyBattery/reports/daily",
        query: [("startDate", first), ("endDate", last)]))
    let hrv = try GarminDecoding.hrvDays(
      from: await get("/hrv-service/hrv/daily/\(first)/\(last)"))

    var samples = battery.samples
    // Readings only exist for nights the watch measured.
    for day in hrv where day.hrvLastNight != nil {
      let readings = try await get("/hrv-service/hrv/\(day.calendarDate)")
      samples += try GarminDecoding.hrvReadings(from: readings)
    }

    // Heart rate has no range endpoint, so it is one request per day.
    var heartRateDays: [GarminDay] = []
    for day in days {
      let heartRate = try GarminDecoding.heartRate(
        from: await get("/wellness-service/wellness/dailyHeartRate", query: [("date", day)]))
      if let summary = heartRate.day { heartRateDays.append(summary) }
      samples += heartRate.samples
    }
    return GarminFetchResult(
      days: GarminDecoding.merge(stress, battery.days, hrv, heartRateDays), samples: samples)
  }

  // MARK: - Requests

  private func get(_ path: String, query: [(String, String)] = []) async throws -> Data {
    var components = URLComponents(
      url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    if !query.isEmpty {
      components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
    }
    let url = components.url!

    // One retry with a fresh token when the old one was turned down.
    for attempt in 0..<2 {
      var request = URLRequest(url: url)
      request.setValue("Bearer \(try await bearerToken())", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      let (data, status) = try await transport.send(request)
      switch status {
      case 200..<300: return data
      case 401 where attempt == 0: token = nil
      default: throw GarminAPIError.http(status)
      }
    }
    throw GarminAPIError.http(401)
  }

  private func bearerToken() async throws -> String {
    if let token, token.expires > now() { return token.value }
    guard let key = apiKey() else { throw GarminAPIError.keyRejected }

    var request = URLRequest(url: Self.baseURL.appendingPathComponent(Self.tokenPath))
    request.httpMethod = "POST"
    request.setValue("ApiKey \(key)", forHTTPHeaderField: "Authorization")
    let (data, status) = try await transport.send(request)
    if status == 401 || status == 403 { throw GarminAPIError.keyRejected }
    guard (200..<300).contains(status) else { throw GarminAPIError.http(status) }
    guard let value = Self.tokenValue(from: data) else { throw GarminAPIError.badToken }
    token = (value, now().addingTimeInterval(Self.tokenLifetime))
    return value
  }

  /// The token endpoint answers with the bare JWT. Accept a JSON string or an object with
  /// `access_token` too, in case that changes.
  static func tokenValue(from data: Data) -> String? {
    if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
      if let string = object as? String { return string.isEmpty ? nil : string }
      if let dict = object as? [String: Any], let string = dict["access_token"] as? String {
        return string
      }
    }
    let text = String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty || text.contains(" ") ? nil : text
  }
}
