//
//  EOLInterpreter+Builtins.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// The names of the built-in operations and properties of EOL.
public enum EOLBuiltinName {
    // Any
    /// Prints the receiver followed by a line break.
    public static let println = "println"
    /// Prints the receiver.
    public static let print = "print"
    /// Prints the receiver and a line break to the error output.
    public static let errln = "errln"
    /// Prints the receiver to the error output.
    public static let err = "err"
    /// The textual representation.
    public static let asString = "asString"
    /// The textual representation (Java spelling).
    public static let toString = "toString"
    /// Whether the receiver is defined.
    public static let isDefined = "isDefined"
    /// Whether the receiver is undefined.
    public static let isUndefined = "isUndefined"
    /// The receiver, or an alternative if it is undefined.
    public static let ifUndefined = "ifUndefined"
    /// Whether the receiver conforms to a type.
    public static let isKindOf = "isKindOf"
    /// Whether the receiver conforms to a type (alias of `isKindOf`).
    public static let instanceOf = "instanceOf"
    /// Whether the receiver's own type is a type.
    public static let isTypeOf = "isTypeOf"
    /// The receiver's type.
    public static let type = "type"
    /// Whether the receiver has a property.
    public static let hasProperty = "hasProperty"
    /// The model that holds the receiver.
    public static let owningModel = "owningModel"
    /// Conversion to a Boolean.
    public static let asBoolean = "asBoolean"
    /// Conversion to an integer.
    public static let asInteger = "asInteger"
    /// Conversion to a real.
    public static let asReal = "asReal"
    /// Conversion to a real (alias).
    public static let asDouble = "asDouble"
    /// Conversion to a real (alias).
    public static let asFloat = "asFloat"
    /// Conversion to a sequence.
    public static let asSequence = "asSequence"
    /// Conversion to a set.
    public static let asSet = "asSet"
    /// Conversion to an ordered set.
    public static let asOrderedSet = "asOrderedSet"
    /// Conversion to a bag.
    public static let asBag = "asBag"
    // Types and models
    /// All instances of a type, including subtypes.
    public static let all = "all"
    /// All instances of a type, including subtypes.
    public static let allInstances = "allInstances"
    /// All instances of a type, including subtypes.
    public static let allOfKind = "allOfKind"
    /// All direct instances of a type.
    public static let allOfType = "allOfType"
    /// All instances of a type, including subtypes.
    public static let getAllOfKind = "getAllOfKind"
    /// All direct instances of a type.
    public static let getAllOfType = "getAllOfType"
    /// Creates an instance of a type.
    public static let createInstance = "createInstance"
    /// Whether a type can be instantiated.
    public static let isInstantiable = "isInstantiable"
    /// The name of a type or model.
    public static let name = "name"
    /// All elements of a model.
    public static let allContents = "allContents"
    /// Whether a model holds an element.
    public static let owns = "owns"
    /// An empty source range for references created by the interpreter.
    static let noRange = SourceRange(
        start: SourcePosition(utf8Offset: 0, line: 1, column: 1), end: SourcePosition(utf8Offset: 0, line: 1, column: 1))
    /// The variable bound to the running total in `aggregate`.
    public static let total = "total"
    /// The prefix of the parallel variants of first-order operations, which run sequentially.
    public static let parallelPrefix = "parallel"
}

extension EOLInterpreter {
    // MARK: - Dispatch

    /// Calls an operation on a receiver.
    ///
    /// With `.` navigation, user-defined operations take precedence over built-in
    /// ones; with `->`, built-in operations do. Dialect extensions are consulted
    /// before the built-in operations in both cases.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - receiver: The receiver.
    ///   - arguments: The evaluated arguments.
    ///   - preferBuiltins: Whether built-in operations take precedence.
    /// - Returns: The result.
    /// - Throws: ``EOLError`` if no operation applies or the operation fails.
    public func call(_ name: String, on receiver: EOLValue, arguments: [EOLValue], preferBuiltins: Bool = false) async throws
        -> EOLValue
    {
        if !preferBuiltins, let operation = try await findOperation(name, receiver: receiver, arguments: arguments) {
            return try await invoke(operation, receiver: receiver, arguments: arguments)
        }
        for item in extensions {
            if let value = try await item.call(name, on: receiver, arguments: arguments, interpreter: self) { return value }
        }
        if let value = try await builtin(name, on: receiver, arguments: arguments) { return value }
        if preferBuiltins, let operation = try await findOperation(name, receiver: receiver, arguments: arguments) {
            return try await invoke(operation, receiver: receiver, arguments: arguments)
        }
        if !receiver.isDefined {
            throw EOLError(.undefinedReceiver, "Called operation '\(name)' on an undefined value")
        }
        throw EOLError(
            .unknownOperation,
            "Operation '\(name)' with \(arguments.count) argument(s) not found on a value of type \(try await typeOf(receiver).name)")
    }

    /// Calls an operation without a receiver.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - arguments: The evaluated arguments.
    /// - Returns: The result.
    /// - Throws: ``EOLError`` if no operation applies or the operation fails.
    public func callGlobal(_ name: String, arguments: [EOLValue]) async throws -> EOLValue {
        if let operation = try await findOperation(name, receiver: nil, arguments: arguments) {
            return try await invoke(operation, receiver: .undefined, arguments: arguments)
        }
        for item in extensions {
            if let value = try await item.call(name, on: nil, arguments: arguments, interpreter: self) { return value }
        }
        if let receiver = variable(EOLLanguage.Variable.receiver),
            let operation = try await findOperation(name, receiver: receiver, arguments: arguments)
        {
            return try await invoke(operation, receiver: receiver, arguments: arguments)
        }
        throw EOLError(.unknownOperation, "Operation '\(name)' with \(arguments.count) argument(s) not found")
    }

    /// Calls a built-in operation.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - receiver: The receiver.
    ///   - arguments: The arguments.
    /// - Returns: The result, or `nil` if there is no such built-in operation.
    /// - Throws: ``EOLError`` if the operation fails.
    func builtin(_ name: String, on receiver: EOLValue, arguments: [EOLValue]) async throws -> EOLValue? {
        if case .object(let reference) = receiver,
            let value = try await reference.object.call(name, arguments: arguments, interpreter: self)
        {
            return value
        }
        if let value = try await anyOperation(name, on: receiver, arguments: arguments) { return value }
        switch receiver {
        case .string(let text): return try stringOperation(name, text, arguments)
        case .integer, .real: return try numberOperation(name, receiver, arguments)
        case .collection(let collection): return try await collectionOperation(name, collection, arguments)
        case .map(let map): return try await mapOperation(name, map, arguments)
        case .type(let type):
            if let value = try await typeOperation(name, type, arguments) { return value }
            guard let model = model(named: type.name) else { return nil }
            return try await EOLModelObject(model: model).call(name, arguments: arguments, interpreter: self)
        case .element(let element): return try await elementOperation(name, element, arguments)
        case .object: return nil
        default: return nil
        }
    }

    // MARK: - Any

    /// The operations that every value supports.
    private func anyOperation(_ name: String, on receiver: EOLValue, arguments: [EOLValue]) async throws -> EOLValue? {
        typealias B = EOLBuiltinName
        switch (name, arguments.count) {
        case (B.println, 0...1), (B.print, 0...1), (B.errln, 0...1), (B.err, 0...1):
            let prefix = arguments.isEmpty ? "" : await string(of: arguments[0])
            let lineBreak = name == B.println || name == B.errln ? "\n" : ""
            let stream = name == B.err || name == B.errln ? errorOutput : output
            stream.write(prefix + (await string(of: receiver)) + lineBreak)
            return receiver
        case (B.asString, 0), (B.toString, 0):
            return .string(await string(of: receiver))
        case (B.isDefined, 0): return .boolean(receiver.isDefined)
        case (B.isUndefined, 0): return .boolean(!receiver.isDefined)
        case (B.ifUndefined, 1): return receiver.isDefined ? receiver : arguments[0]
        case (B.isKindOf, 1), (B.instanceOf, 1), (B.isTypeOf, 1):
            guard case .type(let type) = arguments[0] else {
                throw EOLError(.typeMismatch, "'\(name)' expects a type argument")
            }
            return .boolean(name == B.isTypeOf ? try await isType(receiver, of: type) : try await isKind(receiver, of: type))
        case (B.type, 0):
            return .type(try await typeOf(receiver))
        case (B.hasProperty, 1):
            guard case .element(let element) = receiver, let property = arguments[0].stringValue else { return .boolean(false) }
            return .boolean(await eClass(of: element)?.getStructuralFeature(name: property) != nil)
        case (B.owningModel, 0):
            guard case .element(let element) = receiver else { return .undefined }
            return .object(EOLHostObjectReference(EOLModelObject(model: element.model)))
        case (B.asSequence, 0), (B.asSet, 0), (B.asOrderedSet, 0), (B.asBag, 0):
            let kind: EOLCollectionKind =
                name == B.asSequence ? .sequence : name == B.asSet ? .set : name == B.asOrderedSet ? .orderedSet : .bag
            if case .map(let map) = receiver { return .collection(EOLCollection(kind, map.values)) }
            return .collection(EOLCollection(kind, receiver.asElements))
        default:
            return nil
        }
    }

    // MARK: - Strings

    /// The operations of strings.
    private func stringOperation(_ name: String, _ text: String, _ arguments: [EOLValue]) throws -> EOLValue? {
        /// The string argument at a position, or a type error.
        func argumentString(_ index: Int) throws -> String {
            guard index < arguments.count, let value = arguments[index].stringValue else {
                throw EOLError(.typeMismatch, "'\(name)' expects a string argument")
            }
            return value
        }
        /// The integer argument at a position, or a type error.
        func argumentInteger(_ index: Int) throws -> Int {
            guard index < arguments.count, let value = arguments[index].integerValue else {
                throw EOLError(.typeMismatch, "'\(name)' expects an integer argument")
            }
            return value
        }
        let characters = Array(text)
        switch (name, arguments.count) {
        case ("length", 0), ("size", 0): return .integer(characters.count)
        case ("toUpperCase", 0): return .string(text.uppercased())
        case ("toLowerCase", 0): return .string(text.lowercased())
        case ("firstToUpperCase", 0), ("ftuc", 0):
            return .string(characters.first.map { String($0).uppercased() + String(characters.dropFirst()) } ?? "")
        case ("firstToLowerCase", 0), ("ftlc", 0):
            return .string(characters.first.map { String($0).lowercased() + String(characters.dropFirst()) } ?? "")
        case ("trim", 0): return .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case ("isEmpty", 0): return .boolean(text.isEmpty)
        case ("concat", 1): return .string(text + (try argumentString(0)))
        case ("startsWith", 1): return .boolean(text.hasPrefix(try argumentString(0)))
        case ("endsWith", 1): return .boolean(text.hasSuffix(try argumentString(0)))
        case ("contains", 1): return .boolean(text.contains(try argumentString(0)))
        case ("isSubstringOf", 1): return .boolean(try argumentString(0).contains(text))
        case ("equalsIgnoreCase", 1): return .boolean(text.lowercased() == (try argumentString(0)).lowercased())
        case ("indexOf", 1), ("lastIndexOf", 1):
            let needle = Array(try argumentString(0))
            return .integer(Self.index(of: needle, in: characters, last: name == "lastIndexOf"))
        case ("characterAt", 1), ("charAt", 1):
            let index = try argumentInteger(0)
            guard characters.indices.contains(index) else {
                throw EOLError(.indexOutOfBounds, "Index \(index) is out of bounds for a string of length \(characters.count)")
            }
            return .string(String(characters[index]))
        case ("substring", 1), ("substring", 2):
            let start = try argumentInteger(0)
            let end = arguments.count == 2 ? try argumentInteger(1) : characters.count
            guard start >= 0, end <= characters.count, start <= end else {
                throw EOLError(.indexOutOfBounds, "Substring range \(start)..<\(end) is out of bounds for length \(characters.count)")
            }
            return .string(String(characters[start..<end]))
        case ("split", 1):
            let parts = try Self.split(text, regex: try argumentString(0))
            return .collection(EOLCollection(.sequence, parts.map { .string($0) }))
        case ("matches", 1):
            let pattern = try Self.regex(try argumentString(0))
            let range = NSRange(text.startIndex..., in: text)
            let match = pattern.firstMatch(in: text, options: [.anchored], range: range)
            return .boolean(match.map { $0.range.length == range.length } ?? false)
        case ("replace", 2), ("replaceAll", 2):
            let pattern = try Self.regex(try argumentString(0))
            let template = Self.javaReplacementTemplate(try argumentString(1))
            return .string(pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template))
        case ("isInteger", 0): return .boolean(Int(text) != nil)
        case ("isReal", 0): return .boolean(Double(text) != nil)
        case ("asInteger", 0):
            guard let number = Int(text) else { throw EOLError(.typeMismatch, "'\(text)' is not an integer") }
            return .integer(number)
        case ("asReal", 0), ("asDouble", 0), ("asFloat", 0):
            guard let number = Double(text) else { throw EOLError(.typeMismatch, "'\(text)' is not a real") }
            return .real(number)
        case ("asBoolean", 0): return .boolean(text.lowercased() == EOLLanguage.Keyword.true)
        case ("toCharSequence", 0): return .collection(EOLCollection(.sequence, characters.map { .string(String($0)) }))
        case ("pad", 3):
            let length = try argumentInteger(0)
            let padding = try argumentString(1)
            guard let right = arguments[2].booleanValue else { throw EOLError(.typeMismatch, "'pad' expects a Boolean") }
            var result = text
            while result.count < length, !padding.isEmpty {
                result = right ? result + padding : padding + result
            }
            return .string(result)
        case ("escapeXml", 0):
            var result = ""
            for character in text {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                case "\"": result += "&quot;"
                case "'": result += "&apos;"
                default: result.append(character)
                }
            }
            return .string(result)
        default:
            return nil
        }
    }

    /// The position of a substring, or -1.
    private static func index(of needle: [Character], in haystack: [Character], last: Bool) -> Int {
        guard needle.count <= haystack.count else { return -1 }
        if needle.isEmpty { return last ? haystack.count : 0 }
        let positions = Array(0...(haystack.count - needle.count))
        for start in last ? positions.reversed() : positions where Array(haystack[start..<(start + needle.count)]) == needle {
            return start
        }
        return -1
    }

    /// Compiles a regular expression.
    private static func regex(_ pattern: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            throw EOLError(.typeMismatch, "Invalid regular expression '\(pattern)'")
        }
    }

    /// Converts a Java replacement string (`$1`) into a template for `NSRegularExpression`.
    private static func javaReplacementTemplate(_ replacement: String) -> String {
        var result = ""
        var escaped = false
        for character in replacement {
            if escaped {
                result += NSRegularExpression.escapedTemplate(for: String(character))
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Splits a string around regular expression matches as Java does, dropping trailing empty strings.
    private static func split(_ text: String, regex pattern: String) throws -> [String] {
        if pattern.isEmpty { return text.isEmpty ? [""] : text.map { String($0) } }
        let expression = try regex(pattern)
        var parts: [String] = []
        var start = text.startIndex
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), !range.isEmpty || range.lowerBound > start else { continue }
            if range.isEmpty, range.lowerBound == text.startIndex { continue }
            parts.append(String(text[start..<range.lowerBound]))
            start = range.upperBound
        }
        parts.append(String(text[start...]))
        while parts.count > 1, parts.last?.isEmpty == true { parts.removeLast() }
        if parts == [""], text.isEmpty { return [""] }
        return parts
    }

    // MARK: - Numbers

    /// The operations of integers and reals.
    private func numberOperation(_ name: String, _ receiver: EOLValue, _ arguments: [EOLValue]) throws -> EOLValue? {
        guard let real = receiver.realValue else { return nil }
        let integer = receiver.integerValue
        /// The numeric argument at a position, as a real, or a type error.
        func argumentReal(_ index: Int) throws -> Double {
            guard index < arguments.count, let value = arguments[index].realValue else {
                throw EOLError(.typeMismatch, "'\(name)' expects a numeric argument")
            }
            return value
        }
        switch (name, arguments.count) {
        case ("abs", 0): return integer.map { .integer(abs($0)) } ?? .real(abs(real))
        case ("floor", 0): return integer.map { .integer($0) } ?? .integer(Int(real.rounded(.down)))
        case ("ceiling", 0): return integer.map { .integer($0) } ?? .integer(Int(real.rounded(.up)))
        case ("round", 0): return integer.map { .integer($0) } ?? .integer(Int((real + 0.5).rounded(.down)))
        case ("log", 0): return .real(Foundation.log(real))
        case ("log10", 0): return .real(Foundation.log10(real))
        case ("sqrt", 0): return .real(real.squareRoot())
        case ("pow", 1): return .real(Foundation.pow(real, try argumentReal(0)))
        case ("max", 1), ("min", 1):
            let other = arguments[0]
            guard let otherReal = other.realValue else { throw EOLError(.typeMismatch, "'\(name)' expects a numeric argument") }
            let pickReceiver = name == "max" ? real >= otherReal : real <= otherReal
            if let integer, let otherInteger = other.integerValue { return .integer(pickReceiver ? integer : otherInteger) }
            return .real(pickReceiver ? real : otherReal)
        case ("mod", 1):
            if let integer, let divisor = arguments[0].integerValue {
                guard divisor != 0 else { throw EOLError(.arithmetic, "Division by zero") }
                return .integer(integer % divisor)
            }
            return .real(real.truncatingRemainder(dividingBy: try argumentReal(0)))
        case ("to", 1):
            guard let integer, let end = arguments[0].integerValue else { return nil }
            let values = integer <= end ? Array(integer...end) : Array((end...integer).reversed())
            return .collection(EOLCollection(.sequence, values.map { .integer($0) }))
        case ("iota", 2):
            guard let integer, let end = arguments[0].integerValue, let step = arguments[1].integerValue, step != 0 else {
                throw EOLError(.typeMismatch, "'iota' expects an integer end and a non-zero integer step")
            }
            return .collection(EOLCollection(.sequence, Array(stride(from: integer, through: end, by: step)).map { .integer($0) }))
        case ("toBinary", 0):
            guard let integer else { return nil }
            return .string(String(integer, radix: 2))
        case ("toHex", 0):
            guard let integer else { return nil }
            return .string(String(integer, radix: 16))
        case ("asInteger", 0): return .integer(integer ?? Int(real))
        case ("asReal", 0), ("asDouble", 0), ("asFloat", 0): return .real(real)
        default: return nil
        }
    }

    // MARK: - Collections

    /// The operations of collections that do not take an iterator.
    private func collectionOperation(_ name: String, _ collection: EOLCollection, _ arguments: [EOLValue]) async throws -> EOLValue? {
        let elements = collection.elements
        /// The integer argument at a position, or a type error.
        func argumentInteger(_ index: Int) throws -> Int {
            guard index < arguments.count, let value = arguments[index].integerValue else {
                throw EOLError(.typeMismatch, "'\(name)' expects an integer argument")
            }
            return value
        }
        /// The element at a position, or an index error.
        func positional(_ index: Int) throws -> EOLValue {
            guard elements.indices.contains(index) else {
                throw EOLError(.indexOutOfBounds, "Index \(index) is out of bounds for a collection of size \(elements.count)")
            }
            return elements[index]
        }
        switch (name, arguments.count) {
        case ("size", 0): return .integer(elements.count)
        case ("isEmpty", 0): return .boolean(elements.isEmpty)
        case ("notEmpty", 0): return .boolean(!elements.isEmpty)
        case ("includes", 1), ("contains", 1): return .boolean(collection.contains(arguments[0]))
        case ("excludes", 1): return .boolean(!collection.contains(arguments[0]))
        case ("includesAll", 1): return .boolean(arguments[0].asElements.allSatisfy(collection.contains))
        case ("excludesAll", 1): return .boolean(!arguments[0].asElements.contains(where: collection.contains))
        case ("count", 1): return .integer(elements.filter { $0 == arguments[0] }.count)
        case ("add", 1):
            let added = collection.append(arguments[0])
            try await writeBack(collection)
            return .boolean(added)
        case ("addAll", 1):
            var changed = false
            for item in arguments[0].asElements { changed = collection.append(item) || changed }
            try await writeBack(collection)
            return .boolean(changed)
        case ("remove", 1):
            let removed = collection.remove(arguments[0])
            try await writeBack(collection)
            return .boolean(removed)
        case ("removeAll", 1):
            var changed = false
            for item in arguments[0].asElements { while collection.remove(item) { changed = true } }
            try await writeBack(collection)
            return .boolean(changed)
        case ("removeAt", 1):
            let index = try argumentInteger(0)
            _ = try positional(index)
            let removed = collection.remove(at: index)
            try await writeBack(collection)
            return removed
        case ("clear", 0):
            collection.removeAll()
            try await writeBack(collection)
            return .undefined
        case ("including", 1):
            let copy = collection.copy()
            copy.append(arguments[0])
            return .collection(copy)
        case ("includingAll", 1):
            let copy = collection.copy()
            for item in arguments[0].asElements { copy.append(item) }
            return .collection(copy)
        case ("excluding", 1):
            return .collection(EOLCollection(collection.kind, elements.filter { $0 != arguments[0] }))
        case ("excludingAll", 1):
            let excluded = arguments[0].asElements
            return .collection(EOLCollection(collection.kind, elements.filter { !excluded.contains($0) }))
        case ("clone", 0): return .collection(collection.copy())
        case ("flatten", 0):
            return .collection(EOLCollection(collection.kind, Self.flatten(elements)))
        case ("concat", 0), ("concat", 1):
            let separator = arguments.first.map { $0.stringValue ?? "" } ?? ""
            var parts: [String] = []
            for item in elements { parts.append(await string(of: item)) }
            return .string(parts.joined(separator: separator))
        case ("sum", 0), ("product", 0):
            var total: EOLValue = .integer(name == "sum" ? 0 : 1)
            for item in elements { total = try await arithmetic(name == "sum" ? .plus : .times, total, item) }
            return total
        case ("max", 0), ("min", 0), ("max", 1), ("min", 1):
            guard var best = elements.first else { return arguments.first ?? .undefined }
            for item in elements.dropFirst() {
                guard let order = compare(item, best) else { throw EOLError(.typeMismatch, "'\(name)' needs comparable elements") }
                if (name == "max" && order == .orderedDescending) || (name == "min" && order == .orderedAscending) { best = item }
            }
            return best
        case ("first", 0): return elements.first ?? .undefined
        case ("second", 0): return elements.count > 1 ? elements[1] : .undefined
        case ("third", 0): return elements.count > 2 ? elements[2] : .undefined
        case ("fourth", 0): return elements.count > 3 ? elements[3] : .undefined
        case ("last", 0): return elements.last ?? .undefined
        case ("at", 1), ("get", 1): return try positional(try argumentInteger(0))
        case ("indexOf", 1): return .integer(elements.firstIndex(of: arguments[0]) ?? -1)
        case ("invert", 0), ("reverse", 0): return .collection(EOLCollection(collection.kind, elements.reversed()))
        case ("random", 0): return elements.randomElement() ?? .undefined
        case ("sort", 0):
            return .collection(EOLCollection(collection.kind, try sorted(elements.map { ($0, $0) })))
        case ("selectByKind", 1), ("selectByType", 1):
            guard case .type(let type) = arguments[0] else { throw EOLError(.typeMismatch, "'\(name)' expects a type") }
            var selected: [EOLValue] = []
            for item in elements where name == "selectByKind" ? try await isKind(item, of: type) : try await isType(item, of: type) {
                selected.append(item)
            }
            return .collection(EOLCollection(collection.kind, selected))
        default:
            return nil
        }
    }

    /// Flattens nested collections completely.
    private static func flatten(_ elements: [EOLValue]) -> [EOLValue] {
        elements.flatMap { item -> [EOLValue] in
            if case .collection(let nested) = item { return flatten(nested.elements) }
            return [item]
        }
    }

    /// Sorts values by their keys, keeping the order of equal keys.
    private func sorted(_ pairs: [(value: EOLValue, key: EOLValue)]) throws -> [EOLValue] {
        var failure: EOLError?
        let ordered = pairs.enumerated().sorted { lhs, rhs in
            guard let order = compare(lhs.element.key, rhs.element.key) else {
                failure = EOLError(.typeMismatch, "Sort keys must be numbers or strings")
                return lhs.offset < rhs.offset
            }
            return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
        }
        if let failure { throw failure }
        return ordered.map(\.element.value)
    }

    /// Evaluates a first-order operation.
    ///
    /// - Parameters:
    ///   - name: The operation name; `parallel` variants run sequentially.
    ///   - receiver: The receiver; a single value is treated as a one-element sequence.
    ///   - iterator: The iterator variable.
    ///   - bodies: The body expressions.
    /// - Returns: The result.
    /// - Throws: ``EOLError`` if the operation is unknown or a body fails.
    func firstOrder(_ name: String, on receiver: EOLValue, iterator: EOLParameter, bodies: [EOLExpression]) async throws -> EOLValue {
        var operation = name
        if operation.hasPrefix(EOLBuiltinName.parallelPrefix), operation.count > EOLBuiltinName.parallelPrefix.count {
            let rest = operation.dropFirst(EOLBuiltinName.parallelPrefix.count)
            operation = rest.prefix(1).lowercased() + rest.dropFirst()
        }
        let source: EOLCollection
        if case .collection(let collection) = receiver {
            source = collection
        } else if case .map(let map) = receiver {
            source = EOLCollection(.sequence, map.keys)
        } else {
            source = EOLCollection(.sequence, [receiver])
        }
        let filter = try iterator.type.map { try resolveType($0) }
        var items: [EOLValue] = []
        for item in source.elements {
            if let filter, !(try await isKind(item, of: filter)) { continue }
            items.append(item)
        }
        let body = bodies[0]
        /// Evaluates a body with the iterator (and any extra variables) bound to an item.
        func apply(_ item: EOLValue, _ expression: EOLExpression = body, extra: [String: EOLValue] = [:]) async throws -> EOLValue {
            var variables = extra
            variables[iterator.name] = item
            return try await withScope(variables) { try await evaluate(expression) }
        }
        /// Evaluates the Boolean body for an item.
        func test(_ item: EOLValue) async throws -> Bool {
            let value = try await apply(item)
            guard let flag = value.booleanValue else {
                throw EOLError(.typeMismatch, "The body of '\(name)' must be Boolean", range: body.range, document: document)
            }
            return flag
        }
        /// Counts the items for which the body holds, stopping once the count exceeds a limit.
        func matches(limit: Int? = nil) async throws -> Int {
            var count = 0
            for item in items where try await test(item) {
                count += 1
                if let limit, count > limit { break }
            }
            return count
        }
        let resultKind = source.kind
        switch (operation, bodies.count) {
        case ("select", 1), ("reject", 1):
            var selected: [EOLValue] = []
            for item in items where try await test(item) == (operation == "select") { selected.append(item) }
            return .collection(EOLCollection(resultKind, selected))
        case ("selectOne", 1), ("rejectOne", 1):
            for item in items where try await test(item) {
                if operation == "selectOne" { return item }
                var remaining = source.elements
                if let index = remaining.firstIndex(of: item) { remaining.remove(at: index) }
                return .collection(EOLCollection(resultKind, remaining))
            }
            return operation == "selectOne" ? .undefined : .collection(source.copy())
        case ("collect", 1):
            var collected: [EOLValue] = []
            for item in items { collected.append(try await apply(item)) }
            return .collection(EOLCollection(resultKind.isOrdered ? .sequence : .bag, collected))
        case ("exists", 1):
            for item in items where try await test(item) { return .boolean(true) }
            return .boolean(false)
        case ("forAll", 1):
            for item in items where !(try await test(item)) { return .boolean(false) }
            return .boolean(true)
        case ("none", 1):
            for item in items where try await test(item) { return .boolean(false) }
            return .boolean(true)
        case ("one", 1): return .boolean(try await matches(limit: 1) == 1)
        case ("count", 1): return .integer(try await matches())
        case ("nMatch", 2), ("atLeastNMatch", 2), ("atMostNMatch", 2):
            guard let limit = try await evaluate(bodies[1]).integerValue else {
                throw EOLError(.typeMismatch, "'\(name)' expects an integer count")
            }
            let count = try await matches(limit: limit)
            switch operation {
            case "nMatch": return .boolean(count == limit)
            case "atLeastNMatch": return .boolean(count >= limit)
            default: return .boolean(count <= limit)
            }
        case ("sortBy", 1):
            var pairs: [(value: EOLValue, key: EOLValue)] = []
            for item in items { pairs.append((item, try await apply(item))) }
            return .collection(EOLCollection(.sequence, try sorted(pairs)))
        case ("mapBy", 1):
            let map = EOLMap()
            for item in items {
                let key = try await apply(item)
                if case .collection(let group)? = map[key] {
                    group.append(item)
                } else {
                    map.put(key, .collection(EOLCollection(.sequence, [item])))
                }
            }
            return .map(map)
        case ("aggregate", 2), ("aggregate", 3):
            let map = EOLMap()
            let initial: EOLValue = bodies.count == 3 ? try await evaluate(bodies[2]) : .undefined
            for item in items {
                let key = try await apply(item)
                let total = map[key] ?? initial
                map.put(key, try await apply(item, bodies[1], extra: [EOLBuiltinName.total: total]))
            }
            return .map(map)
        case ("closure", 1):
            let result = EOLCollection(.orderedSet)
            var pending = items
            while !pending.isEmpty {
                let item = pending.removeFirst()
                for next in try await apply(item).asElements where next.isDefined && result.append(next) {
                    pending.append(next)
                }
            }
            return .collection(result)
        default:
            throw EOLError(.unknownOperation, "First-order operation '\(name)' with \(bodies.count) expression(s) is not supported")
        }
    }

    // MARK: - Maps

    /// The operations of maps.
    private func mapOperation(_ name: String, _ map: EOLMap, _ arguments: [EOLValue]) async throws -> EOLValue? {
        switch (name, arguments.count) {
        case ("put", 2):
            map.put(arguments[0], arguments[1])
            return .undefined
        case ("putAll", 1):
            guard case .map(let other) = arguments[0] else { throw EOLError(.typeMismatch, "'putAll' expects a map") }
            for key in other.keys { map.put(key, other[key] ?? .undefined) }
            return .undefined
        case ("get", 1): return map[arguments[0]] ?? .undefined
        case ("containsKey", 1): return .boolean(map[arguments[0]] != nil)
        case ("containsValue", 1): return .boolean(map.values.contains(arguments[0]))
        case ("keySet", 0): return .collection(EOLCollection(.set, map.keys))
        case ("values", 0): return .collection(EOLCollection(.bag, map.values))
        case ("size", 0): return .integer(map.count)
        case ("isEmpty", 0): return .boolean(map.count == 0)
        case ("notEmpty", 0): return .boolean(map.count > 0)
        case ("remove", 1): return map.remove(arguments[0]) ?? .undefined
        case ("clear", 0):
            map.removeAll()
            return .undefined
        default: return nil
        }
    }

    // MARK: - Types and Elements

    /// The operations of type values.
    private func typeOperation(_ name: String, _ type: EOLType, _ arguments: [EOLValue]) async throws -> EOLValue? {
        typealias B = EOLBuiltinName
        switch (name, arguments.count) {
        case (B.all, 0), (B.allInstances, 0), (B.allOfKind, 0), (B.getAllOfKind, 0):
            return try await allInstances(of: type, exact: false)
        case (B.allOfType, 0), (B.getAllOfType, 0):
            return try await allInstances(of: type, exact: true)
        case (B.createInstance, 0):
            return try await instantiate(type, reference: EOLTypeReference(name: type.name, range: B.noRange), arguments: [])
        case (B.isInstantiable, 0):
            if case .modelClass(let modelClass) = type { return .boolean(!modelClass.eClass.isAbstract && !modelClass.eClass.isInterface) }
            return .boolean(true)
        default: return nil
        }
    }

    /// The reflective operations of model elements.
    private func elementOperation(_ name: String, _ element: EOLElement, _ arguments: [EOLValue]) async throws -> EOLValue? {
        guard arguments.isEmpty else { return nil }
        switch name {
        case EOLElementOperation.eContainer, EOLElementOperation.eContents, EOLElementOperation.eAllContents,
            EOLElementOperation.eClass:
            return try await readFeature(name, of: element)
        default:
            return nil
        }
    }
}
