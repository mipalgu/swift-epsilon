//
//  EOLType.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase

/// A type that a program can name, test against and instantiate.
public enum EOLType: Hashable, CustomStringConvertible {
    /// The supertype of every value.
    case any
    /// Strings.
    case string
    /// Integers.
    case integer
    /// Reals; integers conform to it as well.
    case real
    /// Truth values.
    case boolean
    /// Collections of one kind, or of any kind when the kind is `nil`.
    case collection(EOLCollectionKind?)
    /// Maps.
    case map
    /// A class of a metamodel.
    case modelClass(EOLModelClass)
    /// An enumeration of a metamodel.
    case enumeration(EOLModelEnumeration)

    /// The name of the type as EOL writes it.
    public var name: String {
        typealias T = EOLLanguage.TypeName
        switch self {
        case .any: return T.any
        case .string: return T.string
        case .integer: return T.integer
        case .real: return T.real
        case .boolean: return T.boolean
        case .collection(let kind): return kind?.rawValue ?? T.collection
        case .map: return T.map
        case .modelClass(let type): return type.eClass.name
        case .enumeration(let type): return type.eEnum.name
        }
    }

    /// The name of the type, qualified with its model where it has one.
    public var description: String {
        switch self {
        case .modelClass(let type): return (type.model.map { $0.name + EOLLanguage.Symbol.bang } ?? "") + name
        case .enumeration(let type): return (type.model.map { $0.name + EOLLanguage.Symbol.bang } ?? "") + name
        default: return name
        }
    }

    /// The built-in type with a name.
    ///
    /// - Parameter name: The type name.
    /// - Returns: The type, or `nil` if the name is not a built-in type.
    public static func builtin(named name: String) -> EOLType? {
        typealias T = EOLLanguage.TypeName
        switch name {
        case T.any: return .any
        case T.string: return .string
        case T.integer, T.long: return .integer
        case T.real, T.double, T.float: return .real
        case T.boolean: return .boolean
        case T.collection: return .collection(nil)
        case T.sequence, T.list: return .collection(.sequence)
        case T.set: return .collection(.set)
        case T.orderedSet: return .collection(.orderedSet)
        case T.bag: return .collection(.bag)
        case T.map: return .map
        default: return nil
        }
    }
}

/// A metamodel class seen from a model.
public struct EOLModelClass: Hashable {
    /// The class.
    public let eClass: EClass

    /// The model through which the class was named, if any.
    public let model: EOLModel?

    /// Creates a model class reference.
    ///
    /// - Parameters:
    ///   - eClass: The class.
    ///   - model: The model through which it was named.
    public init(eClass: EClass, model: EOLModel?) {
        self.eClass = eClass
        self.model = model
    }

    /// Compares by class identifier and model.
    ///
    /// - Parameters:
    ///   - lhs: The first reference.
    ///   - rhs: The second reference.
    /// - Returns: Whether both name the same class.
    public static func == (lhs: EOLModelClass, rhs: EOLModelClass) -> Bool {
        lhs.eClass.id == rhs.eClass.id || (lhs.eClass.name == rhs.eClass.name && lhs.model === rhs.model)
    }

    /// Hashes the class name.
    ///
    /// - Parameter hasher: The hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(eClass.name) }
}

/// A metamodel enumeration seen from a model.
public struct EOLModelEnumeration: Hashable {
    /// The enumeration.
    public let eEnum: EEnum

    /// The model through which the enumeration was named, if any.
    public let model: EOLModel?

    /// Creates an enumeration reference.
    ///
    /// - Parameters:
    ///   - eEnum: The enumeration.
    ///   - model: The model through which it was named.
    public init(eEnum: EEnum, model: EOLModel?) {
        self.eEnum = eEnum
        self.model = model
    }

    /// Compares by enumeration name.
    ///
    /// - Parameters:
    ///   - lhs: The first reference.
    ///   - rhs: The second reference.
    /// - Returns: Whether both name the same enumeration.
    public static func == (lhs: EOLModelEnumeration, rhs: EOLModelEnumeration) -> Bool {
        lhs.eEnum.id == rhs.eEnum.id || lhs.eEnum.name == rhs.eEnum.name
    }

    /// Hashes the enumeration name.
    ///
    /// - Parameter hasher: The hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(eEnum.name) }
}

/// Helpers that classify type names during parsing.
enum EOLTypes {
    /// Whether a type name takes type arguments.
    ///
    /// - Parameter name: The type name.
    /// - Returns: `true` for the collection types and `Map`.
    static func isParameterisable(_ name: String) -> Bool {
        typealias T = EOLLanguage.TypeName
        return [T.collection, T.sequence, T.list, T.set, T.orderedSet, T.bag, T.map].contains(name)
    }

    /// Whether a type name can start a collection or map literal.
    ///
    /// - Parameter name: The type name.
    /// - Returns: `true` for the concrete collection types and `Map`.
    static func isCollectionLiteralType(_ name: String) -> Bool {
        typealias T = EOLLanguage.TypeName
        return [T.sequence, T.list, T.set, T.orderedSet, T.bag, T.map, T.collection].contains(name)
    }

    /// Whether a class is the given class or one of its subclasses.
    ///
    /// Classes match by identifier. Within one metamodel, where identifiers can
    /// differ (for example after the metamodel was loaded twice), they also match
    /// by name.
    ///
    /// - Parameters:
    ///   - eClass: The class to test.
    ///   - other: The expected class.
    ///   - byName: Whether classes with equal names match.
    /// - Returns: Whether `eClass` conforms to `other`.
    static func conforms(_ eClass: EClass, to other: EClass, byName: Bool) -> Bool {
        if same(eClass, other, byName: byName) { return true }
        return eClass.allSuperTypes.contains { same($0, other, byName: byName) }
    }

    /// Whether two classes are the same class.
    ///
    /// - Parameters:
    ///   - lhs: The first class.
    ///   - rhs: The second class.
    ///   - byName: Whether classes with equal names match.
    /// - Returns: Whether they have the same identifier, or the same name if allowed.
    static func same(_ lhs: EClass, _ rhs: EClass, byName: Bool) -> Bool {
        lhs.id == rhs.id || (byName && lhs.name == rhs.name)
    }
}
