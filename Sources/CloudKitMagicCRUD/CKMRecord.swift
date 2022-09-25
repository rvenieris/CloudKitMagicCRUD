//
//  Protocols.swift
//  CloudKitExample
//
//  Created by Ricardo Venieris on 28/07/20.
//  Copyright © 2020 Ricardo Venieris. All rights reserved.
//

import Foundation

public protocol CKMRecord: CKMCloudable, Hashable {
	
}

extension CKMRecord {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(recordName ?? UUID().uuidString)
	}
	
	public static func == (lhs: Self, rhs: Self) -> Bool {
		let lValues = Mirror(reflecting: lhs).children.compactMap{String(describing: $0.value)}
		let rValues = Mirror(reflecting: rhs).children.compactMap{String(describing: $0.value)}
		
		guard lValues.count == rValues.count else {return false}
		for i in 0..<lValues.count { guard lValues[i] == rValues[i] else {return false} }
		
		return true
	}
}
