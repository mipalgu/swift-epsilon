//
//  EOLInterpreter+Models.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// The names of the reflective element operations that EOL offers in addition to
/// the features of a metamodel.
enum EOLElementOperation {
    /// The element that contains the receiver.
    static let eContainer = "eContainer"
    /// The elements that the receiver contains directly.
    static let eContents = "eContents"
    /// The elements that the receiver contains directly or indirectly.
    static let eAllContents = "eAllContents"
    /// The class of the receiver.
    static let eClass = "eClass"
}

extension EOLInterpreter {
    /// The current state of a model element.
    ///
    /// - Parameter element: The element reference.
    /// - Returns: The element, or `nil` if it no longer exists.
    public func object(of element: EOLElement) async -> (any EObject)? {
        await element.model.resource.resolve(element.id)
    }

    /// The class of a model element.
    ///
    /// - Parameter element: The element reference.
    /// - Returns: The class, or `nil` if the element no longer exists.
    func eClass(of element: EOLElement) async -> EClass? {
        await object(of: element)?.eClass as? EClass
    }

    /// The element value for an identifier, found in a preferred model or any other model.
    ///
    /// - Parameters:
    ///   - id: The element identifier.
    ///   - preferred: The model to look in first.
    /// - Returns: The element, or undefined if no model holds it.
    public func element(withID id: EUUID, preferring preferred: EOLModel?) async -> EOLValue {
        if let preferred, await preferred.resource.contains(id: id) { return .element(EOLElement(id: id, model: preferred)) }
        for model in models where model !== preferred {
            if await model.resource.contains(id: id) { return .element(EOLElement(id: id, model: model)) }
        }
        return .undefined
    }

    /// The model element for an object read from a resource.
    ///
    /// - Parameters:
    ///   - object: The object.
    ///   - model: The model to look in first.
    /// - Returns: The element value.
    public func element(for object: any EObject, preferring model: EOLModel?) async -> EOLValue {
        await element(withID: object.id, preferring: model)
    }

    // MARK: - Reading

    /// Reads a property of a value.
    ///
    /// - Parameters:
    ///   - receiver: The value; it must be defined.
    ///   - name: The property name.
    /// - Returns: The property value.
    /// - Throws: ``EOLError`` if the value has no such property.
    public func property(of receiver: EOLValue, _ name: String) async throws -> EOLValue {
        switch receiver {
        case .element(let element):
            return try await readFeature(name, of: element)
        case .type(let type):
            if let value = try await typeProperty(name, of: type) { return value }
        case .object(let reference):
            if let value = reference.object.property(name) { return value }
        case .collection(let collection):
            if let value = try await parameterlessOperation(name, on: receiver) { return value }
            let result = EOLCollection(collection.kind.isUnique ? .bag : .sequence)
            for item in collection.elements where item.isDefined {
                let value = try await property(of: item, name)
                if case .collection(let nested) = value {
                    for inner in nested.elements { result.append(inner) }
                } else {
                    result.append(value)
                }
            }
            return .collection(result)
        default:
            break
        }
        if let value = try await parameterlessOperation(name, on: receiver) { return value }
        throw EOLError(.unknownProperty, "Property '\(name)' not found on a value of type \(try await typeOf(receiver).name)")
    }

    /// Calls a built-in or dialect operation without arguments, as Epsilon does when a
    /// property name matches no property (so that `s.size` means `s.size()`).
    ///
    /// - Parameters:
    ///   - name: The property name.
    ///   - receiver: The receiver.
    /// - Returns: The result, or `nil` if there is no such operation.
    /// - Throws: ``EOLError`` if the operation fails.
    func parameterlessOperation(_ name: String, on receiver: EOLValue) async throws -> EOLValue? {
        for item in extensions {
            if let value = try await item.call(name, on: receiver, arguments: [], interpreter: self) { return value }
        }
        return try await builtin(name, on: receiver, arguments: [])
    }

    /// Reads a property of a type value, such as `all`.
    private func typeProperty(_ name: String, of type: EOLType) async throws -> EOLValue? {
        switch name {
        case EOLBuiltinName.all, EOLBuiltinName.allInstances:
            return try await allInstances(of: type, exact: false)
        case EOLBuiltinName.name:
            return .string(type.name)
        default:
            return nil
        }
    }

    /// Reads a feature of a model element.
    ///
    /// Unset attributes yield their default value, unset many-valued features an
    /// empty collection, and unset single-valued references undefined. A
    /// many-valued feature yields a collection that writes changes back to the model.
    ///
    /// - Parameters:
    ///   - name: The feature name.
    ///   - element: The element.
    /// - Returns: The value.
    /// - Throws: ``EOLError`` if the element no longer exists or has no such feature.
    public func readFeature(_ name: String, of element: EOLElement) async throws -> EOLValue {
        guard let object = await object(of: element) else {
            throw EOLError(.modelUpdate, "The element no longer exists in model '\(element.model.name)'")
        }
        let eClass = object.eClass as? EClass
        if let feature = eClass?.getStructuralFeature(name: name) {
            var raw = object.eGet(feature)
            if raw == nil, feature is EAttribute, let dynamic = object as? DynamicEObject { raw = dynamic.eGetWithDefault(feature) }
            return await value(of: raw, feature: feature, owner: element)
        }
        switch name {
        case EOLElementOperation.eContainer:
            guard let container = await element.model.resource.eContainer(of: object, scope: .anyResource) else { return .undefined }
            return await self.element(for: container, preferring: element.model)
        case EOLElementOperation.eContents:
            return try await contents(of: element, all: false)
        case EOLElementOperation.eAllContents:
            return try await contents(of: element, all: true)
        case EOLElementOperation.eClass:
            guard let eClass else { return .undefined }
            return .type(.modelClass(EOLModelClass(eClass: eClass, model: element.model)))
        default:
            break
        }
        if let dynamic = object as? DynamicEObject, dynamic.eIsSet(name) {
            return await value(of: dynamic.eGet(name), feature: nil, owner: element)
        }
        if let value = try await parameterlessOperation(name, on: .element(element)) { return value }
        throw EOLError(.unknownProperty, "Property '\(name)' not found on \(eClass?.name ?? "element")")
    }

    /// The contents of an element.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - all: Whether to include indirect contents.
    /// - Returns: A sequence of the contained elements.
    /// - Throws: ``EOLError`` if the element no longer exists.
    func contents(of element: EOLElement, all: Bool) async throws -> EOLValue {
        guard let object = await object(of: element) else {
            throw EOLError(.modelUpdate, "The element no longer exists in model '\(element.model.name)'")
        }
        let resource = element.model.resource
        let objects = all ? await resource.eAllContents(of: object) : await resource.eContents(of: object)
        let result = EOLCollection(.sequence)
        for child in objects { result.append(await self.element(for: child, preferring: element.model)) }
        return .collection(result)
    }

    /// Converts a stored feature value into an EOL value.
    ///
    /// - Parameters:
    ///   - raw: The stored value.
    ///   - feature: The feature, if known.
    ///   - owner: The element that holds the value.
    /// - Returns: The EOL value.
    func value(of raw: (any EcoreValue)?, feature: (any EStructuralFeature)?, owner: EOLElement) async -> EOLValue {
        let isMany = (feature as? EAttribute)?.isMany ?? (feature as? EReference)?.isMany ?? false
        let enumeration = (feature as? EAttribute)?.eType as? EEnum
        if isMany {
            let ordered = (feature as? EAttribute)?.ordered ?? (feature as? EReference)?.ordered ?? true
            let unique = (feature as? EAttribute)?.unique ?? (feature as? EReference)?.unique ?? false
            let collection = EOLCollection(EOLCollectionKind(ordered: ordered, unique: unique))
            for item in Self.items(of: raw) {
                collection.append(await scalar(item, enumeration: enumeration, owner: owner))
            }
            if let feature { collection.binding = EOLFeatureBinding(element: owner, feature: feature.name) }
            return .collection(collection)
        }
        guard let raw else { return .undefined }
        if Self.isArray(raw) {
            let collection = EOLCollection(.sequence)
            for item in Self.items(of: raw) { collection.append(await scalar(item, enumeration: enumeration, owner: owner)) }
            return .collection(collection)
        }
        return await scalar(raw, enumeration: enumeration, owner: owner)
    }

    /// Converts one stored value into an EOL value.
    private func scalar(_ raw: any EcoreValue, enumeration: EEnum?, owner: EOLElement) async -> EOLValue {
        switch raw {
        case let text as String:
            if let enumeration, let literal = enumeration.getLiteral(name: text) ?? enumeration.getLiteral(text: text) {
                return .enumerationLiteral(EOLEnumerationLiteral(enumeration: enumeration.name, name: literal.name, value: literal.value))
            }
            return .string(text)
        case let number as Int: return .integer(number)
        case let number as Int8: return .integer(Int(number))
        case let number as Int16: return .integer(Int(number))
        case let number as Int64: return .integer(Int(number))
        case let number as Double: return .real(number)
        case let number as Float: return .real(Double(number))
        case let number as Decimal: return .real(NSDecimalNumber(decimal: number).doubleValue)
        case let flag as Bool: return .boolean(flag)
        case let character as Character: return .string(String(character))
        case let id as EUUID: return await element(withID: id, preferring: owner.model)
        case let object as any EObject: return await element(withID: object.id, preferring: owner.model)
        case let proxy as ResourceProxy:
            guard let resourceSet = await owner.model.resource.resourceSet,
                let target = await resourceSet.resolveByURI(proxy.uri + "#" + proxy.fragment)
            else { return .undefined }
            return await element(withID: target.id, preferring: nil)
        default:
            return .string("\(raw)")
        }
    }

    /// Whether a stored value is an array.
    private static func isArray(_ raw: any EcoreValue) -> Bool {
        raw is EcoreValueArray || raw is [EUUID] || raw is [String] || raw is [Int] || raw is [Double] || raw is [Bool]
            || raw is [ResourceProxy]
    }

    /// The items of a stored many-valued value.
    private static func items(of raw: (any EcoreValue)?) -> [any EcoreValue] {
        switch raw {
        case nil: return []
        case let array as EcoreValueArray: return array.values
        case let ids as [EUUID]: return ids
        case let strings as [String]: return strings
        case let numbers as [Int]: return numbers
        case let numbers as [Double]: return numbers
        case let flags as [Bool]: return flags
        case let proxies as [ResourceProxy]: return proxies
        case let value?: return [value]
        }
    }

    // MARK: - Writing

    /// Sets a property of a value.
    ///
    /// - Parameters:
    ///   - receiver: The value.
    ///   - name: The property name.
    ///   - value: The new value.
    /// - Throws: ``EOLError`` if the property cannot be set.
    public func setProperty(of receiver: EOLValue, _ name: String, to value: EOLValue) async throws {
        guard case .element(let element) = receiver else {
            throw EOLError(.unknownProperty, "Cannot set property '\(name)' of a value of type \(try await typeOf(receiver).name)")
        }
        try await writeFeature(name, of: element, value)
    }

    /// Writes a feature of a model element.
    ///
    /// Integers assigned to real attributes become reals, enumeration literals are
    /// stored by name, and collections assigned to many-valued features replace their
    /// contents. Adding an element to a containment feature removes it from its
    /// previous container.
    ///
    /// - Parameters:
    ///   - name: The feature name.
    ///   - element: The element.
    ///   - value: The new value.
    /// - Throws: ``EOLError`` if the feature does not exist or the value does not fit it.
    public func writeFeature(_ name: String, of element: EOLElement, _ value: EOLValue) async throws {
        guard let object = await object(of: element), let eClass = object.eClass as? EClass else {
            throw EOLError(.modelUpdate, "The element no longer exists in model '\(element.model.name)'")
        }
        guard let feature = eClass.getStructuralFeature(name: name) else {
            throw EOLError(.unknownProperty, "Property '\(name)' not found on \(eClass.name)")
        }
        let stored: (any EcoreValue)?
        if let attribute = feature as? EAttribute {
            stored = try attributeValue(value, for: attribute)
        } else if let reference = feature as? EReference {
            stored = try await referenceValue(value, for: reference)
            if reference.containment { try await detachChildren(stored, from: element, feature: reference) }
        } else {
            stored = nil
        }
        guard await element.model.resource.eSet(objectId: element.id, feature: name, value: stored) else {
            throw EOLError(.modelUpdate, "Could not set property '\(name)' of \(eClass.name)")
        }
    }

    /// Writes a collection that mirrors a model feature back to the model.
    ///
    /// - Parameter collection: The collection.
    /// - Throws: ``EOLError`` if the model cannot be updated.
    public func writeBack(_ collection: EOLCollection) async throws {
        guard let binding = collection.binding else { return }
        try await writeFeature(binding.feature, of: binding.element, .collection(collection))
    }

    /// Converts a value for storing in an attribute.
    private func attributeValue(_ value: EOLValue, for attribute: EAttribute) throws -> (any EcoreValue)? {
        let typeName = attribute.eType.name
        let enumeration = attribute.eType as? EEnum
        /// Converts one value for the attribute's data type or enumeration.
        func convert(_ item: EOLValue) throws -> any EcoreValue {
            if let enumeration {
                let name: String?
                switch item {
                case .enumerationLiteral(let literal): name = literal.name
                case .string(let text): name = enumeration.getLiteral(name: text)?.name ?? enumeration.getLiteral(text: text)?.name
                case .integer(let number): name = enumeration.getLiteral(value: number)?.name
                default: name = nil
                }
                guard let name, enumeration.getLiteral(name: name) != nil else {
                    throw EOLError(.typeMismatch, "'\(item)' is not a literal of enumeration '\(enumeration.name)'")
                }
                return name
            }
            switch (EOLAttributeKind(typeName), item) {
            case (.real, .integer(let number)): return Double(number)
            case (.real, .real(let number)): return number
            case (.float, .integer(let number)): return Float(number)
            case (.float, .real(let number)): return Float(number)
            case (.integer, .integer(let number)): return number
            case (.boolean, .boolean(let flag)): return flag
            case (.string, .string(let text)): return text
            case (.string, .enumerationLiteral(let literal)): return literal.name
            case (.other, .string(let text)): return text
            case (.other, .integer(let number)): return number
            case (.other, .real(let number)): return number
            case (.other, .boolean(let flag)): return flag
            default:
                throw EOLError(.typeMismatch, "Cannot assign '\(item)' to attribute '\(attribute.name)' of type \(typeName)")
            }
        }
        if attribute.isMany {
            let values = try value.asElements.flatMap { $0.asElements }.map(convert)
            if let strings = values as? [String] { return strings }
            if let integers = values as? [Int] { return integers }
            if let reals = values as? [Double] { return reals }
            if let flags = values as? [Bool] { return flags }
            return EcoreValueArray(values)
        }
        guard value.isDefined else { return nil }
        return try convert(value)
    }

    /// Converts a value for storing in a reference.
    private func referenceValue(_ value: EOLValue, for reference: EReference) async throws -> (any EcoreValue)? {
        var ids: [EUUID] = []
        for item in value.asElements {
            guard case .element(let target) = item else {
                throw EOLError(.typeMismatch, "Cannot assign '\(item)' to reference '\(reference.name)'")
            }
            if let expected = reference.eType as? EClass, let actual = await eClass(of: target),
                !EOLTypes.conforms(actual, to: expected, byName: true)
            {
                throw EOLError(
                    .typeMismatch, "Cannot assign a \(actual.name) to reference '\(reference.name)' of type \(expected.name)")
            }
            if !ids.contains(target.id) { ids.append(target.id) }
        }
        if reference.isMany { return ids }
        if ids.count > 1 {
            throw EOLError(.typeMismatch, "Cannot assign a collection to single-valued reference '\(reference.name)'")
        }
        return ids.first
    }

    /// Removes newly contained elements from their previous containers.
    private func detachChildren(_ stored: (any EcoreValue)?, from owner: EOLElement, feature: EReference) async throws {
        let ids = Self.items(of: stored).compactMap { $0 as? EUUID }
        for id in ids {
            guard case .element(let child) = await element(withID: id, preferring: owner.model),
                let childObject = await object(of: child)
            else { continue }
            let resource = child.model.resource
            guard let container = await resource.eContainer(of: childObject, scope: .anyResource),
                let containing = await resource.eContainingFeature(of: childObject, scope: .anyResource)
            else { continue }
            if container.id == owner.id, containing.name == feature.name { continue }
            guard case .element(let previous) = await element(for: container, preferring: child.model) else { continue }
            try await removeReference(to: [id], from: previous, feature: containing.name)
        }
    }

    /// Removes identifiers from a reference of an element.
    private func removeReference(to ids: Set<EUUID>, from element: EOLElement, feature name: String) async throws {
        guard let object = await object(of: element), let eClass = object.eClass as? EClass,
            let feature = eClass.getStructuralFeature(name: name) as? EReference
        else { return }
        let current = Self.items(of: object.eGet(feature)).compactMap { $0 as? EUUID }
        guard current.contains(where: ids.contains) else { return }
        let remaining = current.filter { !ids.contains($0) }
        let value: (any EcoreValue)? = feature.isMany ? remaining : remaining.first
        _ = await element.model.resource.eSet(objectId: element.id, feature: name, value: value)
    }

    // MARK: - Creation and Deletion

    /// Creates an element of a class in a model.
    ///
    /// The new element is a root of the model's resource until it is added to a
    /// containment feature.
    ///
    /// - Parameters:
    ///   - eClass: The class.
    ///   - model: The model.
    /// - Returns: The new element.
    /// - Throws: ``EOLError`` if the class is abstract.
    public func createElement(of eClass: EClass, in model: EOLModel) async throws -> EOLElement {
        guard !eClass.isAbstract, !eClass.isInterface else {
            throw EOLError(.typeMismatch, "Cannot instantiate abstract class '\(eClass.name)'")
        }
        let object = DynamicEObject(eClass: eClass)
        _ = await model.resource.add(object)
        return EOLElement(id: object.id, model: model)
    }

    /// Deletes an element, its contents and all references to them.
    ///
    /// - Parameter element: The element.
    /// - Throws: ``EOLError`` if the model cannot be updated.
    public func delete(_ element: EOLElement) async throws {
        guard let object = await object(of: element) else { return }
        let resource = element.model.resource
        var doomed: Set<EUUID> = [element.id]
        for child in await resource.eAllContents(of: object) { doomed.insert(child.id) }
        if let container = await resource.eContainer(of: object, scope: .anyResource),
            let feature = await resource.eContainingFeature(of: object, scope: .anyResource),
            case .element(let owner) = await self.element(for: container, preferring: element.model)
        {
            try await removeReference(to: [element.id], from: owner, feature: feature.name)
        }
        for model in models {
            for candidate in await model.allElements() where !doomed.contains(candidate.id) {
                guard let eClass = candidate.eClass as? EClass else { continue }
                for reference in eClass.allReferences {
                    let ids = Self.items(of: candidate.eGet(reference)).compactMap { $0 as? EUUID }
                    if ids.contains(where: doomed.contains) {
                        try await removeReference(to: doomed, from: EOLElement(id: candidate.id, model: model), feature: reference.name)
                    }
                }
            }
        }
        for id in doomed { _ = await resource.remove(id: id) }
    }

    /// All instances of a model type.
    ///
    /// - Parameters:
    ///   - type: The type.
    ///   - exact: Whether to exclude instances of subtypes.
    /// - Returns: A sequence of the instances, in document order.
    /// - Throws: ``EOLError`` if the type is not a model class.
    public func allInstances(of type: EOLType, exact: Bool) async throws -> EOLValue {
        guard case .modelClass(let modelClass) = type else {
            throw EOLError(.typeMismatch, "Type '\(type.name)' has no instances")
        }
        let scope = modelClass.model.map { [$0] } ?? models
        let result = EOLCollection(.sequence)
        for model in scope {
            let byName = sameMetamodelForInstances(model, modelClass.model)
            for object in await model.allElements() {
                guard let eClass = object.eClass as? EClass else { continue }
                let matches =
                    exact
                    ? EOLTypes.same(eClass, modelClass.eClass, byName: byName)
                    : EOLTypes.conforms(eClass, to: modelClass.eClass, byName: byName)
                if matches { result.append(.element(EOLElement(id: object.id, model: model))) }
            }
        }
        return .collection(result)
    }

    /// Whether name-based matching applies when listing instances in a model.
    private func sameMetamodelForInstances(_ model: EOLModel, _ typeModel: EOLModel?) -> Bool {
        guard let typeModel else { return true }
        return model.sharesMetamodel(with: typeModel)
    }
}

/// The storage category of an attribute type.
enum EOLAttributeKind {
    /// Double-precision reals.
    case real
    /// Single-precision reals.
    case float
    /// Integers.
    case integer
    /// Truth values.
    case boolean
    /// Strings.
    case string
    /// Any other data type, stored as given.
    case other

    /// Classifies a data type name.
    ///
    /// - Parameter typeName: The name of the attribute's type.
    init(_ typeName: String) {
        switch typeName {
        case EcoreDataType.eDouble.rawValue, EcoreDataType.eDoubleObject.rawValue, EcoreDataType.eBigDecimal.rawValue:
            self = .real
        case EcoreDataType.eFloat.rawValue, EcoreDataType.eFloatObject.rawValue: self = .float
        case EcoreDataType.eInt.rawValue, EcoreDataType.eIntegerObject.rawValue, EcoreDataType.eLong.rawValue,
            EcoreDataType.eLongObject.rawValue, EcoreDataType.eBigInteger.rawValue:
            self = .integer
        case EcoreDataType.eBoolean.rawValue, EcoreDataType.eBooleanObject.rawValue: self = .boolean
        case EcoreDataType.eString.rawValue: self = .string
        default: self = .other
        }
    }
}

/// A model made available to a program as a value, as in `Library.allContents()`.
public final class EOLModelObject: EOLHostObject {
    /// The model.
    public let model: EOLModel

    /// Wraps a model.
    ///
    /// - Parameter model: The model.
    public init(model: EOLModel) { self.model = model }

    /// The type name shown for the object.
    public var typeName: String { "Model(\(model.name))" }

    /// Reads a property of the model: its `name`.
    ///
    /// - Parameter name: The property name.
    /// - Returns: The value, or `nil`.
    public func property(_ name: String) -> EOLValue? {
        name == EOLBuiltinName.name ? .string(model.name) : nil
    }

    /// Calls a model operation.
    ///
    /// Supported operations are `allContents()`, `getAllOfKind(typeName)`,
    /// `getAllOfType(typeName)`, `createInstance(typeName)` and `owns(element)`.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - arguments: The arguments.
    ///   - interpreter: The interpreter.
    /// - Returns: The result, or `nil` if the operation is unknown.
    /// - Throws: ``EOLError`` if a type name is unknown.
    public func call(_ name: String, arguments: [EOLValue], interpreter: EOLInterpreter) async throws -> EOLValue? {
        switch (name, arguments.first) {
        case (EOLBuiltinName.allContents, nil):
            let result = EOLCollection(.sequence)
            for object in await model.allElements() { result.append(.element(EOLElement(id: object.id, model: model))) }
            return .collection(result)
        case (EOLBuiltinName.getAllOfKind, .string(let typeName)?), (EOLBuiltinName.getAllOfType, .string(let typeName)?):
            let type = try interpreter.resolveType(EOLTypeReference(model: model.name, name: typeName, range: EOLBuiltinName.noRange))
            return try await interpreter.allInstances(of: type, exact: name == EOLBuiltinName.getAllOfType)
        case (EOLBuiltinName.createInstance, .string(let typeName)?):
            guard let eClass = model.classifier(named: typeName) as? EClass else {
                throw EOLError(.unresolvedType, "Model '\(model.name)' has no class '\(typeName)'")
            }
            return .element(try await interpreter.createElement(of: eClass, in: model))
        case (EOLBuiltinName.owns, .element(let element)?):
            return .boolean(await model.resource.contains(id: element.id))
        default:
            return nil
        }
    }
}
