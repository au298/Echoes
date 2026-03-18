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
        guard let modelURL = Bundle.main.url(forResource: "EchoesOfThePast", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Core Data model 'EchoesOfThePast.momd' が見つかりません。")
        }
        container = NSPersistentContainer(name: "EchoesOfThePast", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
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
