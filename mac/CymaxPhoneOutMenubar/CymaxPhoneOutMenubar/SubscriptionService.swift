//
//  SubscriptionService.swift
//  CymaxPhoneOutMenubar
//
//  Verifies subscription status via the Cloudflare license-verification worker.
//  Mirrors the Windows LicenseService.cs implementation — no secrets are stored
//  in the app; all Shopify/Recharge checks happen server-side.
//

import Foundation

// MARK: - Result / Error Types

struct VerifyResult {
    let accessGranted: Bool
    let reason: String?
    let viewPlansUrl: String?
}

enum SubscriptionServiceError: LocalizedError {
    case invalidCredentials
    case inactiveSubscription(viewPlansUrl: String?)
    case noPurchase(viewPlansUrl: String?)
    case serverError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password."
        case .inactiveSubscription:
            return "Your subscription isn't active."
        case .noPurchase:
            return "No active subscription found."
        case .serverError(let msg):
            return "Server error: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}

// MARK: - Service

actor SubscriptionService {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Debug Logging

    private func log(_ message: String) {
        let line = "[SUB-SERVICE] \(message)\n"
        print(line, terminator: "")
        debugLogToFile(line)
    }

    // MARK: - Public API

    /// Verify credentials and subscription status via the Cloudflare Worker.
    /// Returns a `VerifyResult` with `accessGranted`, `reason`, and optional `viewPlansUrl`.
    func verifyLicense(email rawEmail: String, password: String) async throws -> VerifyResult {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        log("Starting license verification for email: \(email)")

        guard let url = URL(string: SubscriptionConfig.workerURL) else {
            throw SubscriptionServiceError.serverError("Invalid worker URL in config.")
        }

        // Build JSON payload matching the worker's expected format
        let payload: [String: String] = [
            "email": email,
            "password": password,
            "product_slug": SubscriptionConfig.productSlug
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            log("Network request failed: \(error.localizedDescription)")
            throw SubscriptionServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SubscriptionServiceError.networkError("No HTTP response.")
        }

        log("Worker HTTP \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            log("Worker error body: \(body)")
            throw SubscriptionServiceError.serverError("HTTP \(httpResponse.statusCode)")
        }

        // Parse response: { access_granted: bool, reason: string?, view_plans_url: string? }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubscriptionServiceError.serverError("Unexpected response format.")
        }

        let accessGranted = json["access_granted"] as? Bool ?? false
        let reason = json["reason"] as? String
        let viewPlansUrl = json["view_plans_url"] as? String

        log("Worker response — access_granted: \(accessGranted), reason: \(reason ?? "nil")")

        return VerifyResult(
            accessGranted: accessGranted,
            reason: reason,
            viewPlansUrl: viewPlansUrl
        )
    }
}
