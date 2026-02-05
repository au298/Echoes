//
//  EchoesApp.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/01/27.
//

import SwiftUI

@main
struct EchoesApp: App {
    @StateObject private var photoStore = PhotoStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(photoStore)
        }
    }
}
