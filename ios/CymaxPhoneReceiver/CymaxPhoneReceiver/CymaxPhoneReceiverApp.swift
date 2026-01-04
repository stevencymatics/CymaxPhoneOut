//
//  CymaxPhoneReceiverApp.swift
//  CymaxPhoneReceiver
//
//  iOS audio receiver for Cymax Phone Out
//

import SwiftUI

@main
struct CymaxPhoneReceiverApp: App {
    @StateObject private var receiverState = ReceiverState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(receiverState)
        }
    }
}

