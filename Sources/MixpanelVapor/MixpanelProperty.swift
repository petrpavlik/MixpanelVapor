//
//  File.swift
//
//
//  Created by Petr Pavlik on 01.05.2024.
//

import Vapor

public struct ProfilePropertyKey: RawRepresentable, Hashable, Codable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let email = ProfilePropertyKey(rawValue: "$email")
    static let firstName = ProfilePropertyKey(rawValue: "$first_name")
    static let lastName = ProfilePropertyKey(rawValue: "$last_name")
    static let name = ProfilePropertyKey(rawValue: "$name")
    static let phone = ProfilePropertyKey(rawValue: "$phone")
    static let avatar = ProfilePropertyKey(rawValue: "$avatar")
    static let created = ProfilePropertyKey(rawValue: "$created")
    static let userId = ProfilePropertyKey(rawValue: "$user_id")
}

public enum MixpanelProperty {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case array([MixpanelProperty])
    case dictionary([String: MixpanelProperty])
}

extension MixpanelProperty: Content {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .date(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Date.self) {
            self = .date(value)
        } else if let value = try? container.decode([MixpanelProperty].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: MixpanelProperty].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid mixpanel property")
        }
    }
}

extension MixpanelProperty: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension MixpanelProperty: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .int(value)
    }
}

extension MixpanelProperty: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .double(value)
    }
}

extension MixpanelProperty: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension MixpanelProperty: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: MixpanelProperty...) {
        self = .array(elements)
    }
}

extension MixpanelProperty: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, MixpanelProperty)...) {
        let dictionary = Dictionary(uniqueKeysWithValues: elements)
        self = .dictionary(dictionary)
    }
}
