//
//  SubscriptionConfig.swift
//  CymaxPhoneOutMenubar
//
//  Per-app subscription checker configuration.
//

import Foundation

struct SubscriptionConfig {

    // MARK: - Cloudflare Worker (License Verification)

    /// License verification endpoint — all credential and subscription checks go through this worker.
    static let workerURL = "https://license-verification-worker.teamcymatics.workers.dev/verify-license"

    /// Product slug sent to the worker so it knows which product to check.
    static let productSlug = "mix-link"

    // MARK: - Grace Period

    /// How long (in seconds) a user can keep using the app after their subscription
    /// is found to be inactive. This covers scenarios like being offline on a plane.
    /// Default: 48 hours (172800 seconds).
    static let gracePeriodSeconds: TimeInterval = 48 * 60 * 60

    /// Set this to a shorter value (e.g. 120 for 2 minutes) to test the grace period.
    /// Set to `nil` to use the real `gracePeriodSeconds` value above.
    /// IMPORTANT: Set back to `nil` before shipping!
    static let debugGracePeriodOverride: TimeInterval? = nil

    /// The effective grace period (uses debug override if set).
    static var effectiveGracePeriod: TimeInterval {
        return debugGracePeriodOverride ?? gracePeriodSeconds
    }

    // MARK: - UI

    /// Default URL opened when the user taps "View Plans" on the subscription-inactive screen.
    /// The worker may return a different URL in the `view_plans_url` field.
    static let viewPlansURL = "https://cymatics.fm/pages/mix-link"

    /// Support email shown on the inactive screen
    static let supportEmail = "support@cymatics.fm"
}
