//
//  File.swift
//
//
//  Created by Petr Pavlik on 01.05.2024.
//

import Vapor

struct AnyContent: Content {

    private let _encode: (Encoder) throws -> Void
    public init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }

    init(from decoder: Decoder) throws {
        fatalError("we don't need this")
    }
}
