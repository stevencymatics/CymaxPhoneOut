//
//  SubscriptionService.swift
//  CymaxPhoneOutMenubar
//
//  Handles Shopify Storefront login and Recharge subscription verification.
//

import Foundation

// MARK: - Error types

enum SubscriptionServiceError: LocalizedError {
    case invalidCredentials
    case networkError(String)
    case shopifyError(String)
    case rechargeError(String)
    case noSubscriptionFound

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .shopifyError(let msg):
            return "Login error: \(msg)"
        case .rechargeError(let msg):
            return "Subscription check error: \(msg)"
        case .noSubscriptionFound:
            return "No active subscription found."
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

    /// Full check: login via Shopify, then verify access via Recharge subscription OR Shopify one-time purchase.
    /// Returns `true` when the customer has either an active subscription or a completed one-time purchase.
    func checkSubscription(email: String, password: String) async throws -> Bool {
        log("Starting subscription check for email: \(email)")

        // Step 1: Verify Shopify credentials and get access token
        let accessToken = try await shopifyCreateAccessToken(email: email, password: password)
        log("Shopify login succeeded")

        // Step 2: Check Recharge subscriptions
        if !SubscriptionConfig.subscriptionVariantIDs.isEmpty {
            let hasSubscription = try await rechargeHasActiveVariant(
                email: email,
                allowedVariantIDs: SubscriptionConfig.subscriptionVariantIDs
            )
            if hasSubscription {
                log("Access granted via active subscription")
                return true
            }
            log("No matching active subscription found")
        }

        // Step 3: Check Shopify order history for one-time purchases
        if !SubscriptionConfig.oneTimePurchaseVariantIDs.isEmpty {
            let hasPurchase = try await shopifyHasOneTimePurchase(
                accessToken: accessToken,
                allowedVariantIDs: SubscriptionConfig.oneTimePurchaseVariantIDs
            )
            if hasPurchase {
                log("Access granted via one-time purchase")
                return true
            }
            log("No matching one-time purchase found")
        }

        log("No valid subscription or purchase found")
        return false
    }

    // MARK: - Shopify Storefront

    /// Mutation: customerAccessTokenCreate
    private func shopifyCreateAccessToken(email: String, password: String) async throws -> String {
        let query = """
        mutation customerAccessTokenCreate($input: CustomerAccessTokenCreateInput!) {
          customerAccessTokenCreate(input: $input) {
            customerAccessToken {
              accessToken
            }
            customerUserErrors {
              message
            }
          }
        }
        """

        let variables: [String: Any] = [
            "input": [
                "email": email,
                "password": password
            ]
        ]

        let body: [String: Any] = ["query": query, "variables": variables]
        let data = try await shopifyRequest(body: body, customerAccessToken: nil)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let mutation = dataObj["customerAccessTokenCreate"] as? [String: Any] else {
            throw SubscriptionServiceError.shopifyError("Unexpected response format.")
        }

        if let errors = mutation["customerUserErrors"] as? [[String: Any]], !errors.isEmpty {
            throw SubscriptionServiceError.invalidCredentials
        }

        guard let tokenObj = mutation["customerAccessToken"] as? [String: Any],
              let accessToken = tokenObj["accessToken"] as? String else {
            throw SubscriptionServiceError.invalidCredentials
        }

        return accessToken
    }

    /// Query: customer { id }  — returns the numeric part of the GID
    private func shopifyGetCustomerId(accessToken: String) async throws -> String {
        let query = """
        {
          customer(customerAccessToken: "\(accessToken)") {
            id
          }
        }
        """

        let body: [String: Any] = ["query": query]
        let data = try await shopifyRequest(body: body, customerAccessToken: accessToken)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let customer = dataObj["customer"] as? [String: Any],
              let gid = customer["id"] as? String else {
            throw SubscriptionServiceError.shopifyError("Could not retrieve customer ID.")
        }

        // gid looks like "gid://shopify/Customer/12345" — extract the numeric tail
        log("Shopify customer GID: \(gid)")
        let numericId = gid.components(separatedBy: "/").last ?? gid
        log("Extracted numeric customer ID: \(numericId)")
        return numericId
    }

    /// Low-level Shopify Storefront GraphQL request.
    private func shopifyRequest(body: [String: Any], customerAccessToken: String?) async throws -> Data {
        guard let url = URL(string: SubscriptionConfig.shopifyStorefrontURL) else {
            throw SubscriptionServiceError.shopifyError("Invalid Storefront URL in config.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SubscriptionConfig.shopifyStorefrontToken, forHTTPHeaderField: "X-Shopify-Storefront-Access-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SubscriptionServiceError.networkError("No HTTP response.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SubscriptionServiceError.shopifyError("HTTP \(httpResponse.statusCode)")
        }

        return data
    }

    // MARK: - Shopify One-Time Purchase Check

    /// Queries the customer's Shopify order history for completed orders containing allowed variant IDs.
    private func shopifyHasOneTimePurchase(accessToken: String, allowedVariantIDs: [String]) async throws -> Bool {
        log("Checking Shopify orders for one-time purchase variants: \(allowedVariantIDs)")

        let query = """
        {
          customer(customerAccessToken: "\(accessToken)") {
            orders(first: 100) {
              edges {
                node {
                  financialStatus
                  lineItems(first: 50) {
                    edges {
                      node {
                        variant {
                          id
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

        let body: [String: Any] = ["query": query]
        let data = try await shopifyRequest(body: body, customerAccessToken: accessToken)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let customer = dataObj["customer"] as? [String: Any],
              let orders = customer["orders"] as? [String: Any],
              let edges = orders["edges"] as? [[String: Any]] else {
            log("Could not parse orders response")
            return false
        }

        log("Found \(edges.count) orders in Shopify")

        let allowedSet = Set(allowedVariantIDs)
        let validStatuses: Set<String> = ["PAID", "PARTIALLY_REFUNDED", "PARTIALLY_PAID"]

        for (orderIndex, edge) in edges.enumerated() {
            guard let node = edge["node"] as? [String: Any] else { continue }
            let financialStatus = node["financialStatus"] as? String ?? "UNKNOWN"

            guard validStatuses.contains(financialStatus) else {
                log("Order[\(orderIndex)] skipped — financialStatus: \(financialStatus)")
                continue
            }

            guard let lineItems = node["lineItems"] as? [String: Any],
                  let lineEdges = lineItems["edges"] as? [[String: Any]] else { continue }

            for lineEdge in lineEdges {
                guard let lineNode = lineEdge["node"] as? [String: Any],
                      let variant = lineNode["variant"] as? [String: Any],
                      let variantGid = variant["id"] as? String else { continue }

                // Extract numeric ID from "gid://shopify/ProductVariant/42152527265877"
                let numericId = variantGid.components(separatedBy: "/").last ?? variantGid

                if allowedSet.contains(numericId) {
                    log("Order[\(orderIndex)] MATCH — variant \(numericId) found with status \(financialStatus)")
                    return true
                }
            }
        }

        log("No matching one-time purchase variant found in any order")
        return false
    }

    // MARK: - Recharge

    /// Returns `true` if the customer has at least one active Recharge subscription
    /// whose variant ID is in `allowedVariantIDs`.
    private func rechargeHasActiveVariant(email: String, allowedVariantIDs: [String]) async throws -> Bool {
        guard let rechargeCustomerId = try await rechargeGetCustomerIdByEmail(email: email) else {
            log("No Recharge customer found for email: \(email)")
            return false
        }

        let variantIds = try await rechargeActiveVariantIds(rechargeCustomerId: rechargeCustomerId)

        let allowedSet = Set(allowedVariantIDs)
        let match = variantIds.contains(where: { allowedSet.contains($0) })
        log("Variant match result: \(match) — found: \(variantIds), allowed: \(Array(allowedSet))")
        return match
    }

    /// Look up the Recharge customer by email address.
    private func rechargeGetCustomerIdByEmail(email: String) async throws -> Int? {
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        let urlString = "\(SubscriptionConfig.rechargeBaseURL)/customers?email=\(encodedEmail)"
        log("Recharge customer lookup URL: \(urlString)")
        let data = try await rechargeRequest(urlString: urlString)

        let rawResponse = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        log("Recharge customer raw response (first 500 chars): \(String(rawResponse.prefix(500)))")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubscriptionServiceError.rechargeError("Response is not a JSON object.")
        }

        guard let customers = json["customers"] as? [[String: Any]] else {
            log("No 'customers' array in response. Keys: \(Array(json.keys))")
            throw SubscriptionServiceError.rechargeError("Unexpected customer response.")
        }

        log("Recharge customers found for email '\(email)': \(customers.count)")

        guard let first = customers.first else {
            log("Customers array is empty — no Recharge customer for email \(email)")
            return nil
        }

        let customerEmail = first["email"] as? String ?? "unknown"
        log("First Recharge customer email: \(customerEmail)")

        guard let id = first["id"] as? Int else {
            log("Could not extract 'id' as Int from customer")
            return nil
        }

        log("Recharge customer ID: \(id)")
        return id
    }

    /// List active subscriptions for a Recharge customer and return their Shopify variant IDs.
    private func rechargeActiveVariantIds(rechargeCustomerId: Int) async throws -> [String] {
        let urlString = "\(SubscriptionConfig.rechargeBaseURL)/subscriptions?customer_id=\(rechargeCustomerId)&status=active"
        log("Recharge subscriptions URL: \(urlString)")
        let data = try await rechargeRequest(urlString: urlString)

        let rawResponse = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        log("Recharge subscriptions raw response: \(rawResponse)")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subscriptions = json["subscriptions"] as? [[String: Any]] else {
            throw SubscriptionServiceError.rechargeError("Unexpected subscription response.")
        }

        log("Active subscriptions found: \(subscriptions.count)")

        var variantIds: [String] = []
        for (index, sub) in subscriptions.enumerated() {
            let status = sub["status"] as? String ?? "unknown"
            let productTitle = sub["product_title"] as? String ?? "unknown"
            log("Subscription[\(index)]: '\(productTitle)' status=\(status)")

            // Recharge 2021-11 API uses nested external_variant_id.ecommerce
            if let extVariant = sub["external_variant_id"] as? [String: Any],
               let ecommerceId = extVariant["ecommerce"] as? String {
                log("Subscription[\(index)] external_variant_id.ecommerce: \(ecommerceId)")
                variantIds.append(ecommerceId)
            } else if let extVariant = sub["external_variant_id"] as? [String: Any],
                      let ecommerceId = extVariant["ecommerce"] as? Int {
                let idStr = String(ecommerceId)
                log("Subscription[\(index)] external_variant_id.ecommerce (Int): \(idStr)")
                variantIds.append(idStr)
            }
            // Fallback: older API format with flat shopify_variant_id
            else if let vid = sub["shopify_variant_id"] as? Int {
                let idStr = String(vid)
                log("Subscription[\(index)] shopify_variant_id (Int): \(idStr)")
                variantIds.append(idStr)
            } else if let vid = sub["shopify_variant_id"] as? String {
                log("Subscription[\(index)] shopify_variant_id (String): \(vid)")
                variantIds.append(vid)
            } else {
                log("Subscription[\(index)] could not extract variant ID. external_variant_id=\(sub["external_variant_id"] ?? "nil")")
            }
        }

        log("Extracted variant IDs from subscriptions: \(variantIds)")
        log("Allowed subscription variant IDs: \(SubscriptionConfig.subscriptionVariantIDs)")

        return variantIds
    }

    /// Low-level GET request to Recharge.
    private func rechargeRequest(urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw SubscriptionServiceError.rechargeError("Invalid Recharge URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(SubscriptionConfig.rechargeAPIToken, forHTTPHeaderField: "X-Recharge-Access-Token")
        request.setValue("2021-11", forHTTPHeaderField: "X-Recharge-Version")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SubscriptionServiceError.networkError("No HTTP response from Recharge.")
        }

        log("Recharge HTTP \(httpResponse.statusCode) for \(urlString)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            log("Recharge error body: \(body)")
            throw SubscriptionServiceError.rechargeError("HTTP \(httpResponse.statusCode)")
        }

        return data
    }
}
