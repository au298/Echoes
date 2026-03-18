//
//  ARBoardView.swift
//  Echoes
//
//  Created by Codex on 2026/02/08.
//

import SwiftUI
import ARKit
import RealityKit
import CoreLocation
import CoreData
import UIKit

struct ARBoardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Echo.createdAt, ascending: false)]
    )
    private var echoes: FetchedResults<Echo>

    @StateObject private var locationManager = LocationManager()
    @State private var showUnsupportedAlert = false
    @State private var debugText: String = ""
    @State private var resetToken = 0
    @State private var saveToken = 0
    @State private var loadToken = 0
    @State private var mode: ARBoardMode = .geo

    var body: some View {
        ZStack {
            ARBoardContainer(
                echoes: Array(echoes),
                currentLocation: locationManager.location,
                resetToken: resetToken,
                saveToken: saveToken,
                loadToken: loadToken,
                onUnsupported: { showUnsupportedAlert = true },
                onDebug: { debugText = $0 },
                onModeChange: { mode = $0 },
                onPlace: { id, transform in saveTransform(id: id, transform: transform) }
            )
            .ignoresSafeArea()

            if locationManager.location == nil {
                VStack {
                    Text("位置情報を取得中…")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 24)
                    Spacer()
                }
            }

#if DEBUG
            if !debugText.isEmpty {
                VStack {
                    Spacer()
                    Text(debugText)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 20)
                }
            }
#endif

            if mode == .world {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("マップ保存") { saveToken += 1 }
                            .buttonStyle(.borderedProminent)
                        Button("マップ読込") { loadToken += 1 }
                            .buttonStyle(.bordered)
                    }

                    Text("画面をタップして写真を配置")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .onAppear {
            locationManager.startUpdating()
            NotificationCenter.default.post(name: .cameraSessionStop, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                resetToken += 1
            }
        }
        .onDisappear {
            locationManager.stopUpdating()
            resetToken += 1
        }
        .alert("AR掲示板が使えません", isPresented: $showUnsupportedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("このデバイスでは位置ベースのAR表示が利用できません。")
        }
    }

    private func saveTransform(id: UUID, transform: simd_float4x4) {
        let request = NSFetchRequest<Echo>(entityName: "Echo")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            if let echo = try viewContext.fetch(request).first {
                echo.arTransform = transform.toData()
                try viewContext.save()
            }
        } catch {
            print("Failed to save AR transform:", error.localizedDescription)
        }
    }
}

private enum ARBoardMode {
    case geo
    case world
}

private struct ARBoardContainer: UIViewRepresentable {
    let echoes: [Echo]
    let currentLocation: CLLocation?
    let resetToken: Int
    let saveToken: Int
    let loadToken: Int
    let onUnsupported: () -> Void
    let onDebug: (String) -> Void
    let onModeChange: (ARBoardMode) -> Void
    let onPlace: (UUID, simd_float4x4) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onUnsupported: onUnsupported, onModeChange: onModeChange, onPlace: onPlace)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false

        view.session.delegate = context.coordinator
        context.coordinator.arView = view

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        if ARGeoTrackingConfiguration.isSupported {
            let configuration = ARGeoTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            view.session.run(configuration)
            context.coordinator.useWorldFallback = false
            context.coordinator.onModeChange(.geo)
        } else if ARWorldTrackingConfiguration.isSupported {
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            view.session.run(configuration)
            context.coordinator.useWorldFallback = true
            context.coordinator.onModeChange(.world)
        } else {
            onUnsupported()
        }
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.resetToken = resetToken
        context.coordinator.saveToken = saveToken
        context.coordinator.loadToken = loadToken
        context.coordinator.resetIfNeeded()
        context.coordinator.saveIfNeeded()
        context.coordinator.loadIfNeeded()
        context.coordinator.latestEchoes = echoes
        context.coordinator.updateBoards(
            echoes: echoes,
            currentLocation: currentLocation,
            onDebug: onDebug
        )
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        var latestEchoes: [Echo] = []
        private var placedIDs = Set<UUID>()
        private let onUnsupported: () -> Void
        private var isGeoLocalized = false
        var useWorldFallback = false
        private var isWorldMapLoaded = false
        private var isRelocalized = false
        var resetToken: Int = 0
        private var lastResetToken: Int = 0
        var saveToken: Int = 0
        private var lastSaveToken: Int = 0
        var loadToken: Int = 0
        private var lastLoadToken: Int = 0
        let onModeChange: (ARBoardMode) -> Void
        let onPlace: (UUID, simd_float4x4) -> Void

        init(
            onUnsupported: @escaping () -> Void,
            onModeChange: @escaping (ARBoardMode) -> Void,
            onPlace: @escaping (UUID, simd_float4x4) -> Void
        ) {
            self.onUnsupported = onUnsupported
            self.onModeChange = onModeChange
            self.onPlace = onPlace
        }

        func resetIfNeeded() {
            guard resetToken != lastResetToken else { return }
            lastResetToken = resetToken
            placedIDs.removeAll()
            isGeoLocalized = false
            isRelocalized = false
            isWorldMapLoaded = false

            guard let arView else { return }
            arView.scene.anchors.removeAll()
            arView.session.pause()

            if ARGeoTrackingConfiguration.isSupported {
                let configuration = ARGeoTrackingConfiguration()
                configuration.planeDetection = [.horizontal, .vertical]
                arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                useWorldFallback = false
                setMode(.geo)
            } else if ARWorldTrackingConfiguration.isSupported {
                let configuration = ARWorldTrackingConfiguration()
                configuration.planeDetection = [.horizontal, .vertical]
                arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                useWorldFallback = true
                isWorldMapLoaded = false
                isRelocalized = false
                setMode(.world)
            }
        }

        func saveIfNeeded() {
            guard saveToken != lastSaveToken else { return }
            lastSaveToken = saveToken
            guard let arView else { return }
            guard useWorldFallback else { return }

            arView.session.getCurrentWorldMap { worldMap, error in
                if let worldMap {
                    do {
                        let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
                        let url = FileManager.default.worldMapURL()
                        try data.write(to: url, options: [.atomic])
                    } catch {
                        print("Failed to save world map:", error.localizedDescription)
                    }
                } else if let error {
                    print("WorldMap unavailable:", error.localizedDescription)
                }
            }
        }

        func loadIfNeeded() {
            guard loadToken != lastLoadToken else { return }
            lastLoadToken = loadToken
            guard let arView else { return }
            guard useWorldFallback else { return }

            do {
                let url = FileManager.default.worldMapURL()
                let data = try Data(contentsOf: url)
                if let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) {
                    let configuration = ARWorldTrackingConfiguration()
                    configuration.initialWorldMap = worldMap
                    configuration.planeDetection = [.horizontal, .vertical]
                    arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                    placedIDs.removeAll()
                    arView.scene.anchors.removeAll()
                    isWorldMapLoaded = true
                    isRelocalized = false
                }
            } catch {
                print("Failed to load world map:", error.localizedDescription)
            }
        }

        func updateBoards(echoes: [Echo], currentLocation: CLLocation?, onDebug: (String) -> Void) {
            guard let arView else { return }

            if useWorldFallback {
#if DEBUG
                onDebug("mode: world\nall: \(echoes.count) placed: \(placedIDs.count)\nmapLoaded: \(isWorldMapLoaded) relocalized: \(isRelocalized)")
#endif
                if isWorldMapLoaded && isRelocalized {
                    placeWorldAnchors(echoes: echoes, arView: arView)
                }
                return
            }

            guard let currentLocation else {
#if DEBUG
                onDebug("mode: geo\nlocation: nil\nall: \(echoes.count) placed: \(placedIDs.count)")
#endif
                return
            }

            let nearby = echoes.filter { echo in
                let location = CLLocation(latitude: echo.latitude, longitude: echo.longitude)
                return currentLocation.distance(from: location) <= 100
            }
#if DEBUG
            onDebug("mode: geo\nlocation: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)\nall: \(echoes.count) nearby: \(nearby.count) placed: \(placedIDs.count)\ngeoLocalized: \(isGeoLocalized)")
#endif

            guard isGeoLocalized else { return }

            for echo in nearby {
                guard let id = echo.id, !placedIDs.contains(id) else { continue }
                if arView.scene.anchors.contains(where: { $0.name == id.uuidString }) {
                    placedIDs.insert(id)
                    continue
                }
                guard let data = echo.imageData, let image = UIImage(data: data) else { continue }
                guard let cgImage = image.cgImage ?? image.toCGImage() else { continue }

                let geoLocation = CLLocationCoordinate2D(latitude: echo.latitude, longitude: echo.longitude)
                let anchor = ARGeoAnchor(coordinate: geoLocation)
                arView.session.add(anchor: anchor)

                let options = TextureResource.CreateOptions(semantic: .color)
                guard let texture = try? TextureResource(image: cgImage, options: options) else { continue }
                var material = UnlitMaterial()
                material.color = .init(texture: .init(texture))

                let aspect = image.size.width / max(image.size.height, 1)
                let height: Float = 1.0
                let width: Float = Float(aspect) * height

                let mesh = MeshResource.generatePlane(width: width, height: height)
                let entity = ModelEntity(mesh: mesh, materials: [material])
                entity.components[BillboardComponent.self] = BillboardComponent()
                entity.transform.rotation *= simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                entity.generateCollisionShapes(recursive: false)

                let anchorEntity = AnchorEntity(anchor: anchor)
                anchorEntity.name = id.uuidString
                let holder = Entity()
                holder.position = [0, 1.5, 0]
                holder.addChild(entity)
                anchorEntity.addChild(holder)
                arView.scene.addAnchor(anchorEntity)

                placedIDs.insert(id)
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            onUnsupported()
            session.pause()
        }

        func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
            switch geoTrackingStatus.state {
            case .localized:
                isGeoLocalized = true
                setMode(.geo)
            case .localizing:
                isGeoLocalized = false
            case .notAvailable:
                isGeoLocalized = false
                useWorldFallback = true
                setMode(.world)
                isWorldMapLoaded = false
                isRelocalized = false
                if let arView, ARWorldTrackingConfiguration.isSupported {
                    let configuration = ARWorldTrackingConfiguration()
                    configuration.planeDetection = [.horizontal, .vertical]
                    arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                }
            @unknown default:
                isGeoLocalized = false
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard useWorldFallback else { return }
            guard isWorldMapLoaded else { return }
            if case .normal = frame.camera.trackingState {
                if frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending {
                    isRelocalized = true
                }
            }
        }

        private func setMode(_ mode: ARBoardMode) {
            DispatchQueue.main.async {
                self.onModeChange(mode)
            }
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard useWorldFallback else { return }
            guard let arView else { return }
            let location = sender.location(in: arView)
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
            guard let result = results.first else { return }

            guard let echo = latestEchoes.first(where: { $0.imageData != nil && $0.arTransform == nil }) else { return }
            guard let id = echo.id else { return }
            placeWorldAnchor(id: id, echo: echo, transform: result.worldTransform, arView: arView)
            onPlace(id, result.worldTransform)
        }

        private func placeWorldAnchors(echoes: [Echo], arView: ARView) {
            for echo in echoes {
                guard let id = echo.id, !placedIDs.contains(id) else { continue }
                guard let transformData = echo.arTransform,
                      let transform = simd_float4x4.fromData(transformData) else { continue }
                placeWorldAnchor(id: id, echo: echo, transform: transform, arView: arView)
            }
        }

        private func placeWorldAnchor(id: UUID, echo: Echo, transform: simd_float4x4, arView: ARView) {
            if arView.scene.anchors.contains(where: { $0.name == id.uuidString }) {
                placedIDs.insert(id)
                return
            }

            guard let data = echo.imageData, let image = UIImage(data: data) else { return }
            guard let cgImage = image.cgImage ?? image.toCGImage() else { return }

            let options = TextureResource.CreateOptions(semantic: .color)
            guard let texture = try? TextureResource(image: cgImage, options: options) else { return }
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))

            let aspect = image.size.width / max(image.size.height, 1)
            let height: Float = 1.0
            let width: Float = Float(aspect) * height
            let mesh = MeshResource.generatePlane(width: width, height: height)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.components[BillboardComponent.self] = BillboardComponent()
            entity.transform.rotation *= simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

            let anchorEntity = AnchorEntity(world: transform)
            anchorEntity.name = id.uuidString
            anchorEntity.addChild(entity)
            arView.scene.addAnchor(anchorEntity)

            placedIDs.insert(id)
        }
    }
}

private extension UIImage {
    func toCGImage() -> CGImage? {
        guard let ciImage = self.ciImage ?? CIImage(image: self) else { return nil }
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

#Preview {
    ARBoardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

private extension simd_float4x4 {
    func toData() -> Data {
        var matrix = self
        return Data(bytes: &matrix, count: MemoryLayout<simd_float4x4>.size)
    }

    static func fromData(_ data: Data) -> simd_float4x4? {
        guard data.count == MemoryLayout<simd_float4x4>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: simd_float4x4.self) }
    }
}

private extension FileManager {
    func worldMapURL() -> URL {
        let documents = (try? url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? temporaryDirectory
        return documents.appendingPathComponent("arworldmap.dat")
    }
}
