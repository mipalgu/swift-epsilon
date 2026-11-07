//
//  EOLInterpreter+Expressions.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

extension EOLInterpreter {
    /// Evaluates an expression.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The value.
    /// - Throws: ``EOLError`` located at the innermost failing sub-expression.
    public func evaluate(_ expression: EOLExpression) async throws -> EOLValue {
        do {
            switch expression.kind {
            case .literal(let literal):
                switch literal {
                case .string(let text): return .string(text)
                case .integer(let number): return .integer(number)
                case .real(let number): return .real(number)
                case .boolean(let flag): return .boolean(flag)
                case .undefined: return .undefined
                }
            case .name(let name):
                return try resolveName(name)
            case .type(let reference):
                return .type(try resolveType(reference))
            case .enumerationLiteral(let reference, let literal):
                return try enumerationLiteral(reference, literal)
            case .property(let targetExpression, let name, let navigation, let extended):
                let receiver = try await evaluate(targetExpression)
                if !receiver.isDefined {
                    if navigation == .safeDot { return .undefined }
                    throw EOLError(.undefinedReceiver, "Called feature '\(name)' on an undefined value")
                }
                if extended { return extendedProperties[receiver]?[name] ?? .undefined }
                return try await property(of: receiver, name)
            case .call(let targetExpression, let name, let argumentExpressions, let navigation):
                guard let targetExpression else {
                    return try await callGlobal(name, arguments: try await evaluateAll(argumentExpressions))
                }
                let receiver = try await evaluate(targetExpression)
                if !receiver.isDefined, navigation == .safeDot { return .undefined }
                let arguments = try await evaluateAll(argumentExpressions)
                return try await call(name, on: receiver, arguments: arguments, preferBuiltins: navigation == .arrow)
            case .firstOrder(let targetExpression, let name, let iterators, let bodies, let navigation):
                let receiver = try await evaluate(targetExpression)
                if !receiver.isDefined {
                    if navigation == .safeDot { return .undefined }
                    throw EOLError(.undefinedReceiver, "Called operation '\(name)' on an undefined value")
                }
                return try await firstOrder(name, on: receiver, iterator: iterators[0], bodies: bodies)
            case .binary(let op, let left, let right):
                return try await binary(op, left, right)
            case .unary(let op, let operandExpression):
                let operand = try await evaluate(operandExpression)
                switch (op, operand) {
                case (.not, .boolean(let flag)): return .boolean(!flag)
                case (.negate, .integer(let number)): return .integer(-number)
                case (.negate, .real(let number)): return .real(-number)
                default:
                    throw EOLError(.typeMismatch, "Operator '\(op.rawValue)' cannot be applied to \(try await typeOf(operand).name)")
                }
            case .conditional(let condition, let whenTrue, let whenFalse):
                return try await evaluateCondition(condition) ? try await evaluate(whenTrue) : try await evaluate(whenFalse)
            case .elvis(let value, let fallback):
                let primary = try await evaluate(value)
                return primary.isDefined ? primary : try await evaluate(fallback)
            case .collection(let reference, let items):
                return try await collectionLiteral(reference, items)
            case .map(_, let entries):
                let map = EOLMap()
                for entry in entries { map.put(try await evaluate(entry.key), try await evaluate(entry.value)) }
                return .map(map)
            case .new(let reference, let arguments):
                return try await instantiate(try resolveType(reference), reference: reference, arguments: arguments)
            case .item(let targetExpression, let indexExpression):
                return try await item(of: try await evaluate(targetExpression), at: try await evaluate(indexExpression))
            }
        } catch let error as EOLError {
            throw error.located(at: expression.range, document: document)
        }
    }

    /// Evaluates expressions in order.
    ///
    /// - Parameter expressions: The expressions.
    /// - Returns: Their values.
    /// - Throws: ``EOLError`` if one fails.
    func evaluateAll(_ expressions: [EOLExpression]) async throws -> [EOLValue] {
        var values: [EOLValue] = []
        values.reserveCapacity(expressions.count)
        for expression in expressions { values.append(try await evaluate(expression)) }
        return values
    }

    // MARK: - Names and Types

    /// Resolves a name to a variable, a type or a model, in that order.
    ///
    /// When a model and a type share a name, the name denotes the type, and model
    /// operations such as `allContents()` called on it are forwarded to the model.
    ///
    /// - Parameter name: The name.
    /// - Returns: The value.
    /// - Throws: ``EOLError`` if the name is unknown.
    func resolveName(_ name: String) throws -> EOLValue {
        if let value = variable(name) { return value }
        if let type = lookupType(name) { return .type(type) }
        if let model = model(named: name) { return .object(EOLHostObjectReference(EOLModelObject(model: model))) }
        throw EOLError(.unresolvedName, "Undefined variable, model or type '\(name)'")
    }

    /// Resolves a type reference.
    ///
    /// A model-qualified type is looked up in that model's metamodel. An
    /// unqualified name is a built-in type or, failing that, a type of the first
    /// model whose metamodel defines it.
    ///
    /// - Parameter reference: The type reference.
    /// - Returns: The type.
    /// - Throws: ``EOLError`` if the type or model is unknown.
    public func resolveType(_ reference: EOLTypeReference) throws -> EOLType {
        if let modelName = reference.model {
            guard let model = model(named: modelName) else {
                throw EOLError(.unresolvedType, "Undefined model '\(modelName)'", range: reference.range, document: document)
            }
            guard let type = modelType(reference.name, in: model) else {
                throw EOLError(
                    .unresolvedType, "Model '\(modelName)' has no type '\(reference.name)'", range: reference.range,
                    document: document)
            }
            return type
        }
        if let type = lookupType(reference.name) { return type }
        throw EOLError(.unresolvedType, "Undefined type '\(reference.name)'", range: reference.range, document: document)
    }

    /// Finds a built-in type, or a type of the first model whose metamodel defines it.
    ///
    /// - Parameter name: The unqualified (or package-qualified) type name.
    /// - Returns: The type, or `nil`.
    func lookupType(_ name: String) -> EOLType? {
        if let builtin = EOLType.builtin(named: name) { return builtin }
        for model in models {
            if let type = modelType(name, in: model) { return type }
        }
        return nil
    }

    /// Finds a class or enumeration in a model's metamodel.
    private func modelType(_ name: String, in model: EOLModel) -> EOLType? {
        switch model.classifier(named: name) {
        case let eClass as EClass: return .modelClass(EOLModelClass(eClass: eClass, model: model))
        case let eEnum as EEnum: return .enumeration(EOLModelEnumeration(eEnum: eEnum, model: model))
        default: return nil
        }
    }

    /// Resolves an enumeration literal.
    private func enumerationLiteral(_ reference: EOLTypeReference?, _ literal: String) throws -> EOLValue {
        if let reference {
            guard case .enumeration(let enumeration) = try resolveType(reference) else {
                throw EOLError(.unresolvedType, "'\(reference)' is not an enumeration")
            }
            guard let found = enumeration.eEnum.getLiteral(name: literal) else {
                throw EOLError(.unresolvedName, "Enumeration '\(enumeration.eEnum.name)' has no literal '\(literal)'")
            }
            return .enumerationLiteral(EOLEnumerationLiteral(enumeration: enumeration.eEnum.name, name: found.name, value: found.value))
        }
        for model in models {
            for package in model.packages {
                for case let eEnum as EEnum in allClassifiers(of: package) {
                    if let found = eEnum.getLiteral(name: literal) {
                        return .enumerationLiteral(EOLEnumerationLiteral(enumeration: eEnum.name, name: found.name, value: found.value))
                    }
                }
            }
        }
        throw EOLError(.unresolvedName, "Undefined enumeration literal '#\(literal)'")
    }

    /// The classifiers of a package and its subpackages.
    private func allClassifiers(of package: EPackage) -> [any EClassifier] {
        package.eClassifiers + package.eSubpackages.flatMap { allClassifiers(of: $0) }
    }

    /// Whether a value conforms to a type, including subtypes.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - type: The type.
    /// - Returns: Whether the value is an instance of the type or of one of its subtypes.
    /// - Throws: ``EOLError`` if an element cannot be read.
    public func isKind(_ value: EOLValue, of type: EOLType) async throws -> Bool {
        switch (type, value) {
        case (_, .undefined): return false
        case (.any, _): return true
        case (.real, .integer), (.real, .real), (.integer, .integer), (.string, .string), (.boolean, .boolean),
            (.map, .map):
            return true
        case (.collection(let kind), .collection(let collection)): return kind == nil || kind == collection.kind
        case (.modelClass(let modelClass), .element(let element)):
            guard let eClass = await eClass(of: element) else { return false }
            return EOLTypes.conforms(eClass, to: modelClass.eClass, byName: sameMetamodel(element.model, modelClass.model))
        case (.enumeration(let enumeration), .enumerationLiteral(let literal)):
            return enumeration.eEnum.name == literal.enumeration
        default: return false
        }
    }

    /// Whether a value is a direct instance of a type.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - type: The type.
    /// - Returns: Whether the value's own type is the type.
    /// - Throws: ``EOLError`` if an element cannot be read.
    public func isType(_ value: EOLValue, of type: EOLType) async throws -> Bool {
        switch (type, value) {
        case (_, .undefined): return false
        case (.any, _): return false
        case (.modelClass(let modelClass), .element(let element)):
            guard let eClass = await eClass(of: element) else { return false }
            return EOLTypes.same(eClass, modelClass.eClass, byName: sameMetamodel(element.model, modelClass.model))
        case (.real, .integer): return false
        case (.collection(let kind), .collection(let collection)): return kind == collection.kind
        default: return try await isKind(value, of: type)
        }
    }

    /// Whether name-based class matching is allowed between a model and the model of a type.
    private func sameMetamodel(_ model: EOLModel, _ typeModel: EOLModel?) -> Bool {
        guard let typeModel else { return true }
        return model.sharesMetamodel(with: typeModel)
    }

    /// The type of a value.
    ///
    /// - Parameter value: The value.
    /// - Returns: The most specific type of the value.
    /// - Throws: ``EOLError`` if an element cannot be read.
    public func typeOf(_ value: EOLValue) async throws -> EOLType {
        switch value {
        case .undefined, .object, .type: return .any
        case .boolean: return .boolean
        case .integer: return .integer
        case .real: return .real
        case .string: return .string
        case .collection(let collection): return .collection(collection.kind)
        case .map: return .map
        case .element(let element):
            guard let eClass = await eClass(of: element) else { return .any }
            return .modelClass(EOLModelClass(eClass: eClass, model: element.model))
        case .enumerationLiteral(let literal):
            for model in models {
                if case .enumeration(let enumeration)? = modelType(literal.enumeration, in: model) {
                    return .enumeration(enumeration)
                }
            }
            return .any
        }
    }

    // MARK: - Operators

    /// Evaluates a binary operation, short-circuiting the logical operators.
    private func binary(_ op: EOLBinaryOperator, _ leftExpression: EOLExpression, _ rightExpression: EOLExpression) async throws -> EOLValue {
        switch op {
        case .and, .or, .implies, .xor:
            let left = try await evaluateCondition(leftExpression)
            switch op {
            case .and where !left: return .boolean(false)
            case .or where left: return .boolean(true)
            case .implies where !left: return .boolean(true)
            default: break
            }
            let right = try await evaluateCondition(rightExpression)
            return .boolean(op == .xor ? left != right : right)
        case .equal:
            return .boolean(try await evaluate(leftExpression) == (try await evaluate(rightExpression)))
        case .notEqual:
            return .boolean(try await evaluate(leftExpression) != (try await evaluate(rightExpression)))
        case .less, .greater, .lessOrEqual, .greaterOrEqual:
            let left = try await evaluate(leftExpression)
            let right = try await evaluate(rightExpression)
            guard let order = compare(left, right) else {
                throw EOLError(
                    .typeMismatch,
                    "Operator '\(op.rawValue)' cannot compare \(try await typeOf(left).name) with \(try await typeOf(right).name)")
            }
            switch op {
            case .less: return .boolean(order == .orderedAscending)
            case .greater: return .boolean(order == .orderedDescending)
            case .lessOrEqual: return .boolean(order != .orderedDescending)
            default: return .boolean(order != .orderedAscending)
            }
        case .plus, .minus, .times, .divide:
            return try await arithmetic(op, try await evaluate(leftExpression), try await evaluate(rightExpression))
        }
    }

    /// Orders two numbers or two strings.
    ///
    /// - Parameters:
    ///   - left: The first value.
    ///   - right: The second value.
    /// - Returns: The order, or `nil` if the values cannot be compared.
    func compare(_ left: EOLValue, _ right: EOLValue) -> ComparisonResult? {
        if case .integer(let a) = left, case .integer(let b) = right {
            return a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
        }
        if let a = left.realValue, let b = right.realValue {
            return a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
        }
        if let a = left.stringValue, let b = right.stringValue {
            return a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
        }
        return nil
    }

    /// Applies an arithmetic operator.
    ///
    /// `+` concatenates when either operand is a string. Integer operations stay
    /// integral (division truncates towards zero); mixing in a real gives a real.
    ///
    /// - Parameters:
    ///   - op: The operator.
    ///   - left: The left operand.
    ///   - right: The right operand.
    /// - Returns: The result.
    /// - Throws: ``EOLError`` for incompatible operands, overflow or integer division by zero.
    func arithmetic(_ op: EOLBinaryOperator, _ left: EOLValue, _ right: EOLValue) async throws -> EOLValue {
        if op == .plus, left.stringValue != nil || right.stringValue != nil {
            return .string(await string(of: left) + (await string(of: right)))
        }
        if case .integer(let a) = left, case .integer(let b) = right {
            let (result, overflow): (Int64, Bool)
            switch op {
            case .plus: (result, overflow) = a.addingReportingOverflow(b)
            case .minus: (result, overflow) = a.subtractingReportingOverflow(b)
            case .times: (result, overflow) = a.multipliedReportingOverflow(by: b)
            default:
                guard b != 0 else { throw EOLError(.arithmetic, "Division by zero") }
                (result, overflow) = a.dividedReportingOverflow(by: b)
            }
            guard !overflow else { throw EOLError(.arithmetic, "Integer overflow in '\(op.rawValue)'") }
            return .integer(result)
        }
        if let a = left.realValue, let b = right.realValue {
            switch op {
            case .plus: return .real(a + b)
            case .minus: return .real(a - b)
            case .times: return .real(a * b)
            default: return .real(a / b)
            }
        }
        throw EOLError(
            .typeMismatch,
            "Operator '\(op.rawValue)' cannot be applied to \(try await typeOf(left).name) and \(try await typeOf(right).name)")
    }

    // MARK: - Literals and Instantiation

    /// Builds a collection literal.
    private func collectionLiteral(_ reference: EOLTypeReference, _ items: [EOLCollectionItem]) async throws -> EOLValue {
        guard case .collection(let kind) = try resolveType(reference) else {
            throw EOLError(.typeMismatch, "'\(reference.name)' is not a collection type")
        }
        let collection = EOLCollection(kind ?? .sequence)
        for item in items {
            switch item {
            case .element(let expression):
                collection.append(try await evaluate(expression))
            case .range(let startExpression, let endExpression):
                let start = try await evaluate(startExpression)
                let end = try await evaluate(endExpression)
                guard let first = start.integerValue, let last = end.integerValue else {
                    throw EOLError(.typeMismatch, "Range bounds must be integers")
                }
                let values = first <= last ? Array(first...last) : Array((last...first).reversed())
                for value in values { collection.append(.integer(value)) }
            }
        }
        return .collection(collection)
    }

    /// Creates an instance of a type.
    ///
    /// Model classes are instantiated in the model that names them (or the first
    /// model whose metamodel defines them). Arguments of the form `name = value`
    /// initialise properties of the new element.
    ///
    /// - Parameters:
    ///   - type: The type.
    ///   - reference: The type reference as written, for error messages.
    ///   - arguments: The constructor arguments.
    /// - Returns: The new instance.
    /// - Throws: ``EOLError`` if the type cannot be instantiated.
    func instantiate(_ type: EOLType, reference: EOLTypeReference, arguments: [EOLExpression]) async throws -> EOLValue {
        switch type {
        case .modelClass(let modelClass):
            guard let model = modelClass.model ?? models.first(where: { $0.classifier(named: modelClass.eClass.name) != nil }) else {
                throw EOLError(.unresolvedType, "No model can hold instances of '\(reference)'")
            }
            let element = try await createElement(of: modelClass.eClass, in: model)
            for argument in arguments {
                guard case .binary(.equal, let nameExpression, let valueExpression) = argument.kind,
                    case .name(let name) = nameExpression.kind
                else {
                    throw EOLError(.unsupportedConstruct, "Constructor arguments must have the form 'property = value'", range: argument.range, document: document)
                }
                try await setProperty(of: .element(element), name, to: try await evaluate(valueExpression))
            }
            return .element(element)
        case .collection, .map, .string, .integer, .real, .boolean:
            guard arguments.isEmpty else {
                throw EOLError(.unsupportedConstruct, "Built-in types take no constructor arguments")
            }
            return defaultValue(of: type)
        default:
            throw EOLError(.typeMismatch, "Type '\(reference)' cannot be instantiated")
        }
    }

    /// Selects an item of a collection, map or string.
    private func item(of receiver: EOLValue, at index: EOLValue) async throws -> EOLValue {
        switch receiver {
        case .collection(let collection):
            guard let position = index.integerValue else { throw EOLError(.typeMismatch, "Collection index must be an integer") }
            guard let offset = Int(exactly: position), collection.elements.indices.contains(offset) else {
                throw EOLError(.indexOutOfBounds, "Index \(position) is out of bounds for a collection of size \(collection.count)")
            }
            return collection.elements[offset]
        case .map(let map):
            return map[index] ?? .undefined
        case .string(let text):
            guard let position = index.integerValue else { throw EOLError(.typeMismatch, "String index must be an integer") }
            let characters = Array(text)
            guard let offset = Int(exactly: position), characters.indices.contains(offset) else {
                throw EOLError(.indexOutOfBounds, "Index \(position) is out of bounds for a string of length \(characters.count)")
            }
            return .string(String(characters[offset]))
        default:
            throw EOLError(.typeMismatch, "Values of type \(try await typeOf(receiver).name) have no items")
        }
    }

    // MARK: - Text

    /// Renders a value as text, labelling model elements.
    ///
    /// - Parameter value: The value.
    /// - Returns: The text that `println` would print.
    public func string(of value: EOLValue) async -> String {
        await EOLFormatter.string(of: value) { element in await element.model.label(of: element.id) }
    }
}
