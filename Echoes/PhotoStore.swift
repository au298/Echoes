//
//  PhotoStore.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/02/05.
//

import Combine
import SwiftUI
import MapKit

final class PhotoStore: ObservableObject {
    @Published var pins: [PhotoPin] = []
    
    func add(imageData: Data, location: CLLocation) {
        let pin = PhotoPin(
            id: UUID(),
            imageData: imageData,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            createdAt: Date()
        )
        pins.append(pin)
    }
}
