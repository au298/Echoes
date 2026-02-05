//
//  MapView.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/02/04.
//

import SwiftUI
import MapKit
import CoreData
import QuickLook

enum MapSegment: String, CaseIterable, Identifiable {
    case `public` = "Public"
    case `private` = "Private"
    
    var id: String { self.rawValue }
}

struct MapView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Echo.createdAt, ascending: false)]
    )
    private var echoes: FetchedResults<Echo>
    @StateObject private var locationManager = LocationManager()
    
    @State private var selectedSegment: MapSegment = .public
    @State private var position = MapCameraPosition.automatic
    @State private var selectedEcho: Echo?
    
    var body: some View {
        ZStack(alignment: .top) {
            
            if selectedSegment == .public {
                Map(position: $position) {
                    UserAnnotation()
                    
                    ForEach(echoes, id: \.id) { echo in
                        Annotation(
                            "Photo",
                            coordinate: CLLocationCoordinate2D(
                                latitude: echo.latitude,
                                longitude: echo.longitude
                            )
                        ) {
                            Button {
                                selectedEcho = echo
                            } label: {
                                Image(systemName: "photo.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .tag(echo)
                    }
                }
                    .mapControls {
                        MapUserLocationButton()
                    }
                    .onAppear {
                        locationManager.requestLocation()
                    }
                    .onChange(of: locationManager.location) { _, location in
                        guard let location else { return }
                        
                        position = .region(
                            MKCoordinateRegion(
                                center: location.coordinate,
                                span: MKCoordinateSpan(
                                    latitudeDelta: 0.01,
                                    longitudeDelta: 0.01
                                )
                            )
                        )
                    }
                
            } else if selectedSegment == .private {
                Map(position: $position) {
                    UserAnnotation()
                }
            }
            
            Picker("画面切替", selection: $selectedSegment) {
                ForEach(MapSegment.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .background(.ultraThinMaterial)
//            .clipShape(RoundedRectangle(cornerRadius: 1))
//            .padding(.top, 8)
        }
        .sheet(item: $selectedEcho) { echo in
            EchoDetailView(echo: echo)
        }
    }
}

#if DEBUG
private struct EchoDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let echo: Echo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let scanPath = echo.scanLocalURL {
                    QuickLookPreview(url: URL(fileURLWithPath: scanPath))
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let data = echo.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.gray.opacity(0.2))
                        .frame(height: 200)
                        .overlay(
                            Text("画像がありません")
                                .foregroundStyle(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("撮影時間") {
                        Text(dateText(echo.createdAt))
                    }
                    LabeledContent("緯度") {
                        Text(String(format: "%.6f", echo.latitude))
                    }
                    LabeledContent("経度") {
                        Text(String(format: "%.6f", echo.longitude))
                    }
                    if let text = echo.text, !text.isEmpty {
                        LabeledContent("テキスト") {
                            Text(text)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    if let note = echo.note, !note.isEmpty {
                        LabeledContent("メモ") {
                            Text(note)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    if let scanRemoteURL = echo.scanRemoteURL, !scanRemoteURL.isEmpty {
                        LabeledContent("共有URL") {
                            Text(scanRemoteURL)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }

                Button(role: .destructive) {
                    viewContext.delete(echo)
                    do {
                        try viewContext.save()
                        dismiss()
                    } catch {
                        print("Failed to delete echo:", error.localizedDescription)
                    }
                } label: {
                    Label("ピンを削除", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .presentationDetents([.medium, .large])
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "不明" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif

#Preview {
    MapView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
