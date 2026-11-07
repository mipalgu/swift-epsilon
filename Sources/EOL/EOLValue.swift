//
//  EOLValue.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// A run-time value of an Epsilon program.
///
/// Primitive values are held directly. Collections and maps are reference types,
/// as in Epsilon, so that `s.add(x)` changes the collection that every variable
/// bound to `s` sees. Model elements are referred to by identifier and model,
/// so that each access reads the current state of the model.
public enum EOLValue: Hashable, CustomStringConvertible {
    /// The undefined value (`null`).
    case undefined
    /// A truth value.
    case boolean(Bool)
    /// A whole number.
    case integer(Int)
    /// A real number.
    case real(Double)
    /// A character string.
    case string(String)
    /// A collection.
    case collection(EOLCollection)
    /// A map.
    case map(EOLMap)
    /// A model element.
    case element(EOLElement)
    /// An enumeration literal.
    case enumerationLiteral(EOLEnumerationLiteral)
    /// A type.
    case type(EOLType)
    /// An object provided by the host, such as the template output buffer.
    case object(EOLHostObjectReference)

    /// Whether the value is defined.
    public var isDefined: Bool {
        if case .undefined = self { return false }
        return true
    }

    /// The truth value, if the value is a Boolean.
    public var booleanValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    /// The integer, if the value is an integer.
    public var integerValue: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    /// The number as a real, if the value is an integer or a real.
    public var realValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .real(let value): return value
        default: return nil
        }
    }

    /// The string, if the value is a string.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The collection, if the value is a collection.
    public var collectionValue: EOLCollection? {
        if case .collection(let value) = self { return value }
        return nil
    }

    /// The map, if the value is a map.
    public var mapValue: EOLMap? {
        if case .map(let value) = self { return value }
        return nil
    }

    /// The model element, if the value is one.
    public var elementValue: EOLElement? {
        if case .element(let value) = self { return value }
        return nil
    }

    /// The type, if the value is one.
    public var typeValue: EOLType? {
        if case .type(let value) = self { return value }
        return nil
    }

    /// The value's elements if it is a collection, or the value itself otherwise.
    ///
    /// The undefined value contributes no elements.
    public var asElements: [EOLValue] {
        switch self {
        case .collection(let collection): return collection.elements
        case .undefined: return []
        default: return [self]
        }
    }

    /// Compares two values with EOL equality.
    ///
    /// Numbers compare by numeric value, so `1 = 1.0`. Collections of the same
    /// kind compare by contents (unordered kinds ignore order), maps by contents, and
    /// model elements by identity.
    ///
    /// - Parameters:
    ///   - lhs: The first value.
    ///   - rhs: The second value.
    /// - Returns: Whether the values are equal.
    public static func == (lhs: EOLValue, rhs: EOLValue) -> Bool {
        switch (lhs, rhs) {
        case (.undefined, .undefined): return true
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.integer(let a), .integer(let b)): return a == b
        case (.integer, .real), (.real, .integer), (.real, .real): return lhs.realValue == rhs.realValue
        case (.string(let a), .string(let b)): return a == b
        case (.collection(let a), .collection(let b)): return a === b || a.hasSameContents(as: b)
        case (.map(let a), .map(let b)): return a === b || a.hasSameContents(as: b)
        case (.element(let a), .element(let b)): return a == b
        case (.enumerationLiteral(let a), .enumerationLiteral(let b)): return a == b
        case (.enumerationLiteral(let a), .string(let b)), (.string(let b), .enumerationLiteral(let a)):
            return a.name == b
        case (.type(let a), .type(let b)): return a == b
        case (.object(let a), .object(let b)): return a == b
        default: return false
        }
    }

    /// Hashes the value consistently with ``==(_:_:)``.
    ///
    /// - Parameter hasher: The hasher.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .undefined: hasher.combine(0)
        case .boolean(let value): hasher.combine(value)
        case .integer(let value): hasher.combine(Double(value))
        case .real(let value): hasher.combine(value)
        case .string(let value): hasher.combine(value)
        case .collection(let value): hasher.combine(value.elements.count)
        case .map(let value): hasher.combine(value.count)
        case .element(let value): hasher.combine(value)
        case .enumerationLiteral(let value): hasher.combine(value.name)
        case .type(let value): hasher.combine(value)
        case .object(let value): hasher.combine(value)
        }
    }

    /// The text that `println` and `asString` produce for the value.
    public var description: String { EOLFormatter.string(of: self) }
}

/// The kinds of EOL collection.
public enum EOLCollectionKind: String, Sendable, Hashable, CaseIterable {
    /// Ordered, with duplicates.
    case sequence = "Sequence"
    /// Unordered, without duplicates.
    case set = "Set"
    /// Ordered, without duplicates.
    case orderedSet = "OrderedSet"
    /// Unordered, with duplicates.
    case bag = "Bag"

    /// Whether the kind keeps insertion order.
    public var isOrdered: Bool { self == .sequence || self == .orderedSet }

    /// Whether the kind rejects duplicates.
    public var isUnique: Bool { self == .set || self == .orderedSet }

    /// The kind that matches the `ordered` and `unique` properties of a feature.
    ///
    /// - Parameters:
    ///   - ordered: Whether the feature is ordered.
    ///   - unique: Whether the feature is unique.
    public init(ordered: Bool, unique: Bool) {
        switch (ordered, unique) {
        case (true, true): self = .orderedSet
        case (true, false): self = .sequence
        case (false, true): self = .set
        case (false, false): self = .bag
        }
    }
}

/// The feature of a model element that a collection mirrors.
///
/// A collection read from a many-valued feature remembers where it came from,
/// so that changing the collection (for example with `add`) updates the model.
public struct EOLFeatureBinding: Hashable {
    /// The element that owns the feature.
    public var element: EOLElement
    /// The name of the feature.
    public var feature: String
}

/// A mutable EOL collection with reference semantics.
public final class EOLCollection: Hashable {
    /// The kind of collection.
    public let kind: EOLCollectionKind

    /// The elements in order (the insertion order for unordered kinds).
    public private(set) var elements: [EOLValue]

    /// The membership index of a unique collection.
    private var members: Set<EOLValue>

    /// The model feature that the collection mirrors, if any.
    public var binding: EOLFeatureBinding?

    /// Creates a collection.
    ///
    /// Duplicates are dropped for unique kinds.
    ///
    /// - Parameters:
    ///   - kind: The kind of collection.
    ///   - elements: The initial elements.
    public init(_ kind: EOLCollectionKind, _ elements: [EOLValue] = []) {
        self.kind = kind
        self.elements = []
        members = []
        for element in elements { _ = append(element) }
    }

    /// The number of elements.
    public var count: Int { elements.count }

    /// Whether the collection contains a value.
    ///
    /// - Parameter value: The value to look for.
    /// - Returns: `true` if an equal element is present.
    public func contains(_ value: EOLValue) -> Bool {
        kind.isUnique ? members.contains(value) : elements.contains(value)
    }

    /// Adds a value at the end.
    ///
    /// - Parameter value: The value to add.
    /// - Returns: `true` if the value was added (it was not already in a unique collection).
    @discardableResult
    public func append(_ value: EOLValue) -> Bool {
        if kind.isUnique {
            guard members.insert(value).inserted else { return false }
        }
        elements.append(value)
        return true
    }

    /// Inserts a value at a position.
    ///
    /// - Parameters:
    ///   - value: The value to insert.
    ///   - index: The position.
    /// - Returns: `true` if the value was inserted.
    @discardableResult
    public func insert(_ value: EOLValue, at index: Int) -> Bool {
        if kind.isUnique {
            guard members.insert(value).inserted else { return false }
        }
        elements.insert(value, at: min(max(0, index), elements.count))
        return true
    }

    /// Removes the first element equal to a value.
    ///
    /// - Parameter value: The value to remove.
    /// - Returns: `true` if an element was removed.
    @discardableResult
    public func remove(_ value: EOLValue) -> Bool {
        guard let index = elements.firstIndex(of: value) else { return false }
        elements.remove(at: index)
        if kind.isUnique { members.remove(value) }
        return true
    }

    /// Removes the element at a position.
    ///
    /// - Parameter index: The position.
    /// - Returns: The removed element.
    @discardableResult
    public func remove(at index: Int) -> EOLValue {
        let value = elements.remove(at: index)
        if kind.isUnique { members.remove(value) }
        return value
    }

    /// Replaces the element at a position.
    ///
    /// - Parameters:
    ///   - index: The position.
    ///   - value: The new element.
    public func replace(at index: Int, with value: EOLValue) {
        if kind.isUnique {
            members.remove(elements[index])
            members.insert(value)
        }
        elements[index] = value
    }

    /// Removes all elements.
    public func removeAll() {
        elements.removeAll()
        members.removeAll()
    }

    /// Creates an independent copy without a binding.
    ///
    /// - Parameter kind: The kind of the copy, by default the same kind.
    /// - Returns: The copy.
    public func copy(as kind: EOLCollectionKind? = nil) -> EOLCollection {
        EOLCollection(kind ?? self.kind, elements)
    }

    /// Whether another collection has the same kind and contents.
    ///
    /// - Parameter other: The other collection.
    /// - Returns: `true` if both have the same kind and are either ordered and equal
    ///   element by element, or unordered and contain equal elements equally often.
    public func hasSameContents(as other: EOLCollection) -> Bool {
        guard kind == other.kind, elements.count == other.elements.count else { return false }
        if kind.isOrdered { return elements == other.elements }
        var remaining = other.elements
        for element in elements {
            guard let index = remaining.firstIndex(of: element) else { return false }
            remaining.remove(at: index)
        }
        return true
    }

    /// Compares collections by identity or contents.
    ///
    /// - Parameters:
    ///   - lhs: The first collection.
    ///   - rhs: The second collection.
    /// - Returns: Whether they are equal.
    public static func == (lhs: EOLCollection, rhs: EOLCollection) -> Bool {
        lhs === rhs || lhs.hasSameContents(as: rhs)
    }

    /// Hashes the size of the collection.
    ///
    /// - Parameter hasher: The hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(elements.count) }
}

/// A mutable EOL map with reference semantics that keeps insertion order.
public final class EOLMap: Hashable {
    /// The keys in insertion order.
    public private(set) var keys: [EOLValue] = []

    /// The values by key.
    private var storage: [EOLValue: EOLValue] = [:]

    /// Creates an empty map.
    public init() {}

    /// The number of entries.
    public var count: Int { keys.count }

    /// The value for a key.
    ///
    /// - Parameter key: The key.
    /// - Returns: The value, or `nil` if the key is absent.
    public subscript(key: EOLValue) -> EOLValue? { storage[key] }

    /// Sets the value for a key.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - value: The value.
    public func put(_ key: EOLValue, _ value: EOLValue) {
        if storage.updateValue(value, forKey: key) == nil { keys.append(key) }
    }

    /// Removes a key.
    ///
    /// - Parameter key: The key.
    /// - Returns: The removed value, if any.
    @discardableResult
    public func remove(_ key: EOLValue) -> EOLValue? {
        guard let value = storage.removeValue(forKey: key) else { return nil }
        keys.removeAll { $0 == key }
        return value
    }

    /// Removes all entries.
    public func removeAll() {
        keys.removeAll()
        storage.removeAll()
    }

    /// The values in key order.
    public var values: [EOLValue] { keys.compactMap { storage[$0] } }

    /// Whether another map has equal entries.
    ///
    /// - Parameter other: The other map.
    /// - Returns: `true` if both maps hold the same keys with equal values.
    public func hasSameContents(as other: EOLMap) -> Bool {
        guard count == other.count else { return false }
        return keys.allSatisfy { other.storage[$0] == storage[$0] }
    }

    /// Compares maps by identity or contents.
    ///
    /// - Parameters:
    ///   - lhs: The first map.
    ///   - rhs: The second map.
    /// - Returns: Whether they are equal.
    public static func == (lhs: EOLMap, rhs: EOLMap) -> Bool { lhs === rhs || lhs.hasSameContents(as: rhs) }

    /// Hashes the size of the map.
    ///
    /// - Parameter hasher: The hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(count) }
}

/// A reference to a model element.
public struct EOLElement: Hashable, CustomStringConvertible {
    /// The identifier of the element.
    public let id: EUUID

    /// The model that holds the element.
    public let model: EOLModel

    /// Creates an element reference.
    ///
    /// - Parameters:
    ///   - id: The element identifier.
    ///   - model: The model that holds the element.
    public init(id: EUUID, model: EOLModel) {
        self.id = id
        self.model = model
    }

    /// Compares element references by identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first reference.
    ///   - rhs: The second reference.
    /// - Returns: Whether both refer to the same element.
    public static func == (lhs: EOLElement, rhs: EOLElement) -> Bool { lhs.id == rhs.id }

    /// Hashes the identifier.
    ///
    /// - Parameter hasher: The hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The model name and identifier.
    public var description: String { "\(model.name)#\(id)" }
}

/// An enumeration literal value.
public struct EOLEnumerationLiteral: Sendable, Hashable {
    /// The name of the enumeration.
    public var enumeration: String
    /// The literal name.
    public var name: String
    /// The literal's integer value.
    public var value: Int

    /// Creates an enumeration literal value.
    ///
    /// - Parameters:
    ///   - enumeration: The enumeration name.
    ///   - name: The literal name.
    ///   - value: The literal's integer value.
    public init(enumeration: String, name: String, value: Int) {
        self.enumeration = enumeration
        self.name = name
        self.value = value
    }
}

/// An object that the host makes available to a program, such as an output buffer.
///
/// Host objects answer property reads and operation calls that the interpreter
/// does not handle itself.
public protocol EOLHostObject: AnyObject {
    /// The type name shown for the object.
    var typeName: String { get }

    /// Calls an operation on the object.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - arguments: The evaluated arguments.
    ///   - interpreter: The interpreter making the call.
    /// - Returns: The result, or `nil` if the object has no such operation.
    /// - Throws: ``EOLError`` if the operation fails.
    func call(_ name: String, arguments: [EOLValue], interpreter: EOLInterpreter) async throws -> EOLValue?

    /// Reads a property of the object.
    ///
    /// - Parameter name: The property name.
    /// - Returns: The value, or `nil` if the object has no such property.
    func property(_ name: String) -> EOLValue?
}

/// A hashable wrapper around a host object.
public struct EOLHostObjectReference: Hashable {
    /// The wrapped object.
    public let object: any EOLHostObject

    /// Wraps a host object.
    ///
    /// - Parameter object: The object.
    public init(_ object: any EOLHostObject) { self.object = object }

    /// Compares by identity.
    ///
    /// - Parameters:
    ///   - lhs: The first reference.
    ///   - rhs: The second reference.
    /// - Returns: Whether both wrap the same object.
    public static func == (lhs: EOLHostObjectReference, rhs: EOLHostObjectReference) -> Bool {
        lhs.object === rhs.object
    }

    /// Hashes the object identity.
    ///
    /// - Parameter hasher: The hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(object)) }
}

/// Text rendering of values for `println`, `asString` and string concatenation.
public enum EOLFormatter {
    /// Renders a value.
    ///
    /// Collections render as `Sequence {1, 2}`, maps as `Map {a=1, b=2}`, reals as
    /// Java does (`2.0`, `1.5E10`), model elements as their class name followed by
    /// their `name` attribute in parentheses when they have one, and undefined as
    /// `null`.
    ///
    /// - Parameter value: The value.
    /// - Returns: The text.
    public static func string(of value: EOLValue) -> String {
        switch value {
        case .undefined: return EOLLanguage.Keyword.null
        case .boolean(let flag): return flag ? EOLLanguage.Keyword.true : EOLLanguage.Keyword.false
        case .integer(let number): return String(number)
        case .real(let number): return real(number)
        case .string(let text): return text
        case .collection(let collection):
            return collection.kind.rawValue + " {" + collection.elements.map(string(of:)).joined(separator: ", ") + "}"
        case .map(let map):
            let entries = map.keys.map { string(of: $0) + "=" + string(of: map[$0] ?? .undefined) }
            return EOLLanguage.TypeName.map + " {" + entries.joined(separator: ", ") + "}"
        case .element(let element): return element.description
        case .enumerationLiteral(let literal): return literal.name
        case .type(let type): return type.name
        case .object(let reference): return reference.object.typeName
        }
    }

    /// Renders a value, asking for the label of each model element.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - label: Produces the text of a model element.
    /// - Returns: The text.
    public static func string(of value: EOLValue, label: (EOLElement) async -> String) async -> String {
        switch value {
        case .element(let element): return await label(element)
        case .collection(let collection):
            var parts: [String] = []
            for element in collection.elements { parts.append(await string(of: element, label: label)) }
            return collection.kind.rawValue + " {" + parts.joined(separator: ", ") + "}"
        case .map(let map):
            var parts: [String] = []
            for key in map.keys {
                let keyText = await string(of: key, label: label)
                parts.append(keyText + "=" + (await string(of: map[key] ?? .undefined, label: label)))
            }
            return EOLLanguage.TypeName.map + " {" + parts.joined(separator: ", ") + "}"
        default: return string(of: value)
        }
    }

    /// Renders a real number as Java's `Double.toString` does.
    ///
    /// - Parameter number: The number.
    /// - Returns: The text.
    public static func real(_ number: Double) -> String {
        if number.isNaN { return "NaN" }
        if number.isInfinite { return number < 0 ? "-Infinity" : "Infinity" }
        let magnitude = abs(number)
        if magnitude == 0 || (magnitude >= 1e-3 && magnitude < 1e7) {
            if number == number.rounded() { return String(format: "%.1f", number) }
            return "\(number)"
        }
        return (number < 0 ? "-" : "") + scientific(magnitude)
    }

    /// Renders a positive real in Java's computerised scientific notation, such as `1.5E10`.
    ///
    /// - Parameter magnitude: The positive number.
    /// - Returns: The text.
    private static func scientific(_ magnitude: Double) -> String {
        let text = "\(magnitude)"
        var digits: String
        var exponent: Int
        if let marker = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            let mantissa = text[..<marker].split(separator: ".", omittingEmptySubsequences: false)
            exponent = Int(text[text.index(after: marker)...].replacingOccurrences(of: "+", with: "")) ?? 0
            digits = String(mantissa[0]) + (mantissa.count > 1 ? String(mantissa[1]) : "")
            exponent += mantissa[0].count - 1
        } else {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            let integral = String(parts[0])
            let fraction = parts.count > 1 ? String(parts[1]) : ""
            if integral != "0" {
                digits = integral + fraction
                exponent = integral.count - 1
            } else {
                let leading = fraction.prefix { $0 == "0" }.count
                digits = String(fraction.dropFirst(leading))
                exponent = -(leading + 1)
            }
        }
        digits = String(digits.drop { $0 == "0" })
        while digits.count > 1, digits.hasSuffix("0") { digits.removeLast() }
        if digits.isEmpty { digits = "0" }
        let rest = digits.dropFirst()
        return "\(digits.prefix(1)).\(rest.isEmpty ? "0" : String(rest))E\(exponent)"
    }
}
