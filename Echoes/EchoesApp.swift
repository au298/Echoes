//
//  EchoesApp.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/01/27.
//

import SwiftUI
import CoreData

@main
struct EchoesApp: App {
    private let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
