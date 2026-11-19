import Foundation

/// Deliberately excludes raw response bodies, URLs, headers and underlying error descriptions.
public enum StormglassError: Error, Equatable, Sendable, LocalizedError {
  case missingAPIKey
  case invalidAPIKey
  case invalidSource
  case authentication
  case quotaExceeded
  case rateLimited(retryAfterSeconds: Double?)
  case http(status: Int)
  case invalidResponse
  case invalidPayload
  case emptyWeather
  case transport(code: Int?)

  public var errorDescription: String? {
    switch self {
    case .missingAPIKey: "Supply your own Stormglass API key."
    case .invalidAPIKey: "The Stormglass API key contains invalid header characters."
    case .invalidSource: "Supply one Stormglass weather source identifier."
    case .authentication: "Stormglass rejected the supplied credentials."
    case .quotaExceeded: "The Stormglass account quota is exhausted. Check your plan."
    case .rateLimited: "Stormglass has limited requests. Wait before trying again."
    case .http(let status): "Stormglass returned HTTP \(status)."
    case .invalidResponse: "Stormglass returned an unexpected response."
    case .invalidPayload: "Stormglass returned data in an unsupported format."
    case .emptyWeather: "No weather measurements are available in this forecast window."
    case .transport: "Could not connect to Stormglass."
    }
  }
}
