//
//  File.swift
//
//
//  Created by Petr Pavlik on 01.05.2024.
//

import Vapor

/// Represents a property value that can be sent to Mixpanel.
///
/// This enum encapsulates different types of values that are supported by Mixpanel's tracking API:
/// - String values
/// - Integer values
/// - Double/Float values
/// - Boolean values
/// - Date values
/// - Arrays of MixpanelProperty
/// - Dictionaries with String keys and MixpanelProperty values
///
/// Example:
/// ```swift
/// let stringProperty = MixpanelProperty.string("value")
/// let numberProperty = MixpanelProperty.int(42)
/// let nestedProperty = MixpanelProperty.dictionary(["key": .string("value")])
/// ```
public enum MixpanelProperty {
    /// A string value.
    case string(String)
    /// An integer value.
    case int(Int)
    /// A double value.
    case double(Double)
    /// A boolean value.
    case bool(Bool)
    /// A date value.
    case date(Date)
    /// An array of MixpanelProperty values.
    case array([MixpanelProperty])
    /// A dictionary with String keys and MixpanelProperty values.
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

extension MixpanelProperty: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .date(let value):
            return String(describing: value)
        case .array(let value):
            return String(describing: value)
        case .dictionary(let value):
            return String(describing: value)
        }
    }
}

extension MixpanelProperty: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension MixpanelProperty: ExpressibleByStringInterpolation {
    public init(stringInterpolation: DefaultStringInterpolation) {
        self = .string(String(stringInterpolation: stringInterpolation))
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
