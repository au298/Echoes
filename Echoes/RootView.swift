//
//  RootView.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/02/04.
//

import SwiftUI
import ARKit
import CoreData

struct RootView: View {
    @State private var selectedTab: Tab = .map

    var body: some View {
        TabView(selection: $selectedTab) {
            ScanOrCameraView()
                .tag(Tab.camera)
                .tabItem {
                    Label("カメラ", systemImage: "camera")
                }
            
            MapView()
                .tag(Tab.map)
                .tabItem {
                    Label("マップ", systemImage: "map")
                }
            
            SettingsView()
                .tag(Tab.settings)
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
        }
    }
}

private struct ScanOrCameraView: View {
    var body: some View {
        if supportsLiDARScan() {
            LidarScanView()
        } else {
            CameraView()
        }
    }

    private func supportsLiDARScan() -> Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
}

enum Tab {
    case camera
    case map
    case settings
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
