//
//  PersistenceController.swift
//  Echoes
//
//  Created by Codex on 2026/02/05.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    static let preview = PersistenceController(inMemory: true)

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "EchoesOfThePast")

        if let description = container.persistentStoreDescriptions.first {
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Unresolved error \(error)")
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
