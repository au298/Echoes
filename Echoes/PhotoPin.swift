//
//  PhotoPin.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/02/05.
//


import Foundation
import CoreLocation

struct PhotoPin: Identifiable, Hashable {
    let id: UUID
    let imageData: Data
    let latitude: Double
    let longitude: Double
    let createdAt: Date
}