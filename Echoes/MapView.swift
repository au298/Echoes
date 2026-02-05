//
//  MapView.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/02/04.
//

import SwiftUI
import MapKit

enum MapSegment: String, CaseIterable, Identifiable {
    case `public` = "Public"
    case `private` = "Private"
    
    var id: String { self.rawValue }
}

struct MapView: View {
    @EnvironmentObject private var photoStore: PhotoStore
    @StateObject private var locationManager = LocationManager()
    
    @State private var selectedSegment: MapSegment = .public
    @State private var position = MapCameraPosition.automatic
    
    var body: some View {
        ZStack(alignment: .top) {
            
            if selectedSegment == .public {
                Map(position: $position) {
                    UserAnnotation()
                    
                    ForEach(photoStore.pins) { pin in
                                        Annotation(
                                            "Photo",
                                            coordinate: CLLocationCoordinate2D(
                                                latitude: pin.latitude,
                                                longitude: pin.longitude
                                            )
                                        ) {
                                            Image(systemName: "photo.circle.fill")
                                                .font(.title)
                                                .foregroundStyle(.blue)
                                        }
                                        .tag(pin)
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
                Map(position: $position)
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
    }
}

#Preview {
    MapView()
        .environmentObject(PhotoStore())
}
