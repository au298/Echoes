//
//  RootView.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/02/04.
//

import SwiftUI
import CoreData

struct RootView: View {
    @State private var selectedTab: Tab = .map

    var body: some View {
        TabView(selection: $selectedTab) {
            CameraView()
                .tag(Tab.camera)
                .tabItem {
                    Label("カメラ", systemImage: "camera")
                }
            
            MapView()
                .tag(Tab.map)
                .tabItem {
                    Label("マップ", systemImage: "map")
                }

            ARBoardView()
                .tag(Tab.ar)
                .tabItem {
                    Label("AR", systemImage: "arkit")
                }
            
            SettingsView()
                .tag(Tab.settings)
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .camera {
                NotificationCenter.default.post(name: .cameraSessionStart, object: nil)
            } else {
                NotificationCenter.default.post(name: .cameraSessionStop, object: nil)
            }
        }
    }
}

enum Tab {
    case camera
    case map
    case ar
    case settings
}

extension Notification.Name {
    static let cameraSessionStart = Notification.Name("cameraSessionStart")
    static let cameraSessionStop = Notification.Name("cameraSessionStop")
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
