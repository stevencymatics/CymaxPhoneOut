//
//  SubscriptionConfig.swift
//  CymaxPhoneOutMenubar
//
//  Per-app subscription checker configuration.
//  Replace the placeholder values below with your real credentials before building.
//

import Foundation

struct SubscriptionConfig {

    // MARK: - Shopify Storefront API

    /// Storefront GraphQL endpoint
    static let shopifyStorefrontURL = "https://cymatics-fm.myshopify.com/api/2024-01/graphql.json"

    /// Storefront public access token (used in X-Shopify-Storefront-Access-Token header)
    static let shopifyStorefrontToken = "90e0936879c7680b4bbe4a4f3e8b843e"

    // MARK: - Recharge API

    /// Recharge REST API base URL
    static let rechargeBaseURL = "https://api.rechargeapps.com"

    /// Recharge API token (with read_customers and read_subscriptions scopes)
    static let rechargeAPIToken = "sk_2x2_9597dbeaef75da7148e0539edf613f727119f7f75daacf5853917b7169de8ba6"

    // MARK: - Product Entitlement (Subscriptions)

    /// Shopify variant IDs for subscription products (checked via Recharge).
    /// A user with an active Recharge subscription containing any of these variants is allowed in.
    static let subscriptionVariantIDs: [String] = [
        "42152113307733"
    ]

    // MARK: - Product Entitlement (One-Time Purchases)

    /// Shopify variant IDs for one-time purchase products (checked via Shopify order history).
    /// A user who has successfully ordered any of these variants is allowed in.
    static let oneTimePurchaseVariantIDs: [String] = [
        "42152527265877"
    ]

    // MARK: - UI

    /// URL opened when the user taps "View Plans" on the subscription-inactive screen
    static let viewPlansURL = "https://cymatics.fm/pages/mix-link"

    /// Support email shown on the inactive screen
    static let supportEmail = "support@cymatics.fm"
}
