//
//  MindCanvasApp.swift
//  MindCanvas
//
//  Created by elvis on 2025/12/10.
//

import SwiftUI
import SwiftData

@main
struct MindCanvasApp: App {
    @State private var authManager = AuthManager.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            Asset.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
