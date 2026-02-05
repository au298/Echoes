//
//  RootView.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/02/04.
//

import SwiftUI

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
            
            SettingsView()
                .tag(Tab.settings)
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
        }
    }
}

enum Tab {
    case camera
    case map
    case settings
}

#Preview {
    RootView()
        .environmentObject(PhotoStore())
}
