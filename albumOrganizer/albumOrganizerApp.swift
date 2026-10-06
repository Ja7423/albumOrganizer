//
//  albumOrganizerApp.swift
//  albumOrganizer
//
//  Created by 家瑋 on 2026/10/6.
//

import SwiftUI
import CoreData

@main
struct albumOrganizerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
