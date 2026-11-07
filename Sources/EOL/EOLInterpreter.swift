//
//  EOLInterpreter.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// An interpreter for the Epsilon Object Language.
///
/// The interpreter holds the models a program works on, the operations it
/// declares and imports, and the variable scopes of the running program. The
/// dialect engines (EVL, ETL, EGL) drive an interpreter of their own and add
/// operations to it through ``EOLExtension``.
///
/// An interpreter is not thread-safe: it is created, used and discarded within
/// one task. Model access goes through the `Resource` actors of its models.
///
/// ```swift
/// let library = try await EOLModel.load(
///     name: "Library", url: modelURL, metamodels: [metamodelURL], resourceSet: ResourceSet())
/// let output = EOLStringOutput()
/// let interpreter = EOLInterpreter(models: [library], output: output)
/// try await interpreter.run(EOLSyntax.parse("Book.all.size().println();").get())
/// ```
public final class EOLInterpreter {
    /// The models the program can access, in lookup order.
    public private(set) var models: [EOLModel]

    /// Where `print` and `println` write.
    public var output: any EOLOutputStream

    /// Where `err` and `errln` write.
    public var errorOutput: any EOLOutputStream

    /// The dialect behaviour consulted before the built-in operations.
    public var extensions: [any EOLExtension] = []

    /// How imported modules are read.
    public var moduleLoader: any EOLModuleLoading

    /// The destination of template text and output sections, when running a template.
    public var templateOutput: (any EOLOutputStream)?

    /// The maximum depth of nested operation calls before execution stops.
    public var maximumCallDepth = 1_000

    /// The operations available to the program, in dispatch order.
    public private(set) var operations: [EOLOperation] = []

    /// The positions in ``operations`` by operation name.
    private var operationIndex: [String: [Int]] = [:]

    /// The documents whose operations have been registered.
    private var registeredDocuments: Set<String> = []

    /// The variable scopes; the first is the global scope.
    package var frames: [EOLFrame] = [EOLFrame(isProtected: true)]

    /// The results of `@cached` operations.
    private var cache: [CacheKey: EOLValue] = [:]

    /// The extended properties (`x.~name`) of values.
    package var extendedProperties: [EOLValue: [String: EOLValue]] = [:]

    /// The current depth of nested operation calls.
    private var callDepth = 0

    /// The number of loops enclosing the current statement within the current operation.
    private var loopDepth = 0

    /// The document of the module being executed, used to locate errors.
    public var document: String?

    /// The key of a cached operation result.
    private struct CacheKey: Hashable {
        /// The position of the operation.
        let operation: Int
        /// The receiver.
        let receiver: EOLValue
    }

    /// Creates an interpreter.
    ///
    /// - Parameters:
    ///   - models: The models the program can access.
    ///   - output: Where `print` and `println` write (standard output by default).
    ///   - errorOutput: Where `err` and `errln` write (standard error by default).
    ///   - moduleLoader: How imported modules are read (from files by default).
    public init(
        models: [EOLModel] = [], output: any EOLOutputStream = EOLStandardOutput(),
        errorOutput: any EOLOutputStream = EOLStandardOutput(error: true),
        moduleLoader: any EOLModuleLoading = EOLFileModuleLoader()
    ) {
        self.models = models
        self.output = output
        self.errorOutput = errorOutput
        self.moduleLoader = moduleLoader
    }

    /// Adds a model.
    ///
    /// - Parameter model: The model.
    public func addModel(_ model: EOLModel) { models.append(model) }

    /// Finds a model by name or alias.
    ///
    /// - Parameter name: The name.
    /// - Returns: The model, or `nil`.
    public func model(named name: String) -> EOLModel? { models.first { $0.answers(to: name) } }

    // MARK: - Running

    /// Runs the main program of a module.
    ///
    /// The module's imports are resolved and its operations registered first.
    ///
    /// - Parameter module: The module.
    /// - Returns: The value of a top-level `return`, or undefined.
    /// - Throws: ``EOLError`` if an import fails or the program raises an error.
    @discardableResult
    public func run(_ module: EOLModule) async throws -> EOLValue {
        try register(module)
        document = module.document
        return try await evaluateBlock(module.statements)
    }

    /// Executes statements directly in the global scope, so that the variables they
    /// declare stay visible to everything that runs afterwards.
    ///
    /// The dialects use this for `pre` blocks.
    ///
    /// - Parameter statements: The statements.
    /// - Throws: ``EOLError`` if a statement fails.
    public func executeInGlobalScope(_ statements: EOLBlock) async throws {
        let saved = frames
        frames = [frames[0]]
        defer { frames = saved }
        _ = try await executeStatements(statements)
    }

    /// Registers the operations of a module and of the modules it imports.
    ///
    /// Operations of the module come before those it imports, so that an
    /// importing module can override an imported operation.
    ///
    /// - Parameter module: The module.
    /// - Throws: ``EOLError`` if an imported module cannot be read or parsed.
    public func register(_ module: EOLModule) throws {
        try register(operations: module.operations, imports: module.imports, document: module.document)
    }

    /// Registers operations and the operations of imported modules.
    ///
    /// - Parameters:
    ///   - operations: The operations declared by the importing module.
    ///   - imports: Its imports.
    ///   - document: The importing document.
    /// - Throws: ``EOLError`` if an imported module cannot be read or parsed.
    public func register(operations: [EOLOperation], imports: [EOLImport], document: String?) throws {
        if let document {
            guard registeredDocuments.insert(document).inserted else { return }
        }
        for operation in operations { add(operation) }
        for declaration in imports {
            let loaded: (text: String, document: String)
            do {
                loaded = try moduleLoader.load(declaration.path, relativeTo: document)
            } catch {
                throw EOLError(
                    .importFailed, "Cannot import '\(declaration.path)': \(error.localizedDescription)",
                    range: declaration.range, document: document)
            }
            guard !registeredDocuments.contains(loaded.document) else { continue }
            let parsed = EOLImportParsing.parse(loaded.text, document: loaded.document)
            if let failure = parsed.diagnostics.first(where: { $0.severity == .error }) {
                throw EOLError(
                    .importFailed, "Imported module '\(declaration.path)' has errors: \(EOLError(diagnostic: failure))",
                    range: declaration.range, document: document)
            }
            try register(operations: parsed.operations, imports: parsed.imports, document: loaded.document)
        }
    }

    /// Adds one operation to the dispatch table.
    ///
    /// - Parameter operation: The operation.
    public func add(_ operation: EOLOperation) {
        operationIndex[operation.name, default: []].append(operations.count)
        operations.append(operation)
    }

    // MARK: - Variables

    /// Declares or replaces a global variable.
    ///
    /// - Parameters:
    ///   - name: The variable name.
    ///   - value: The value.
    public func setGlobal(_ name: String, _ value: EOLValue) { frames[0].variables[name] = value }

    /// Reads a variable visible from the current scope.
    ///
    /// - Parameter name: The variable name.
    /// - Returns: The value, or `nil` if no visible scope declares it.
    public func variable(_ name: String) -> EOLValue? {
        guard let index = frameIndex(declaring: name) else { return nil }
        return frames[index].variables[name]
    }

    /// The variables declared in the innermost scope.
    ///
    /// Dialects use this to keep the variables of a block, such as the `check`
    /// block of an EVL constraint, for code that runs later.
    public var innermostScopeVariables: [String: EOLValue] { frames[frames.count - 1].variables }

    /// Declares a variable in the innermost scope.
    ///
    /// - Parameters:
    ///   - name: The variable name.
    ///   - value: The value.
    public func declare(_ name: String, _ value: EOLValue) { frames[frames.count - 1].variables[name] = value }

    /// Finds the innermost visible frame that declares a variable.
    ///
    /// - Parameter name: The variable name.
    /// - Returns: The frame index, or `nil`.
    private func frameIndex(declaring name: String) -> Int? {
        var index = frames.count - 1
        while index > 0 {
            if frames[index].variables[name] != nil { return index }
            if frames[index].isProtected { break }
            index -= 1
        }
        return frames[0].variables[name] != nil ? 0 : nil
    }

    /// Assigns a declared variable.
    ///
    /// - Parameters:
    ///   - name: The variable name.
    ///   - value: The value.
    /// - Throws: ``EOLError`` if no visible scope declares the variable.
    func assignVariable(_ name: String, _ value: EOLValue) throws {
        guard let index = frameIndex(declaring: name) else {
            throw EOLError(.unresolvedName, "Undefined variable '\(name)'")
        }
        frames[index].variables[name] = value
    }

    /// Runs code in a new scope.
    ///
    /// - Parameters:
    ///   - variables: The variables of the new scope.
    ///   - isProtected: Whether the scope hides the caller's variables.
    ///   - body: The code to run.
    /// - Returns: The result of the code.
    /// - Throws: Whatever the code throws.
    public func withScope<T>(
        _ variables: [String: EOLValue] = [:], isProtected: Bool = false, _ body: () async throws -> T
    ) async throws -> T {
        frames.append(EOLFrame(variables: variables, isProtected: isProtected))
        defer { frames.removeLast() }
        return try await body()
    }

    // MARK: - Statements

    /// Executes statements in a new scope.
    ///
    /// - Parameter statements: The statements.
    /// - Returns: The control flow outcome.
    /// - Throws: ``EOLError`` if a statement fails.
    package func executeBlock(_ statements: EOLBlock) async throws -> EOLFlow {
        try await withScope { try await executeStatements(statements) }
    }

    /// Executes statements in the current scope.
    ///
    /// - Parameter statements: The statements.
    /// - Returns: The control flow outcome.
    /// - Throws: ``EOLError`` if a statement fails.
    package func executeStatements(_ statements: EOLBlock) async throws -> EOLFlow {
        for statement in statements {
            let flow = try await execute(statement)
            if case .normal = flow { continue }
            return flow
        }
        return .normal
    }

    /// Executes a block as the body of a rule or annotation-like construct and returns its value.
    ///
    /// The value is the operand of a `return` statement, or undefined.
    ///
    /// - Parameters:
    ///   - statements: The statements.
    ///   - variables: The variables to declare in the new scope.
    /// - Returns: The returned value.
    /// - Throws: ``EOLError`` if a statement fails.
    public func evaluateBlock(_ statements: EOLBlock, variables: [String: EOLValue] = [:]) async throws -> EOLValue {
        try await withScope(variables) {
            if case .returned(let value) = try await executeStatements(statements) { return value }
            return .undefined
        }
    }

    /// Executes statements in a new scope, ignoring their control flow outcome.
    ///
    /// - Parameters:
    ///   - statements: The statements.
    ///   - variables: The variables to declare in the new scope.
    /// - Throws: ``EOLError`` if a statement fails.
    public func execute(_ statements: EOLBlock, variables: [String: EOLValue] = [:]) async throws {
        _ = try await withScope(variables) { try await executeStatements(statements) }
    }

    /// Executes one statement.
    ///
    /// - Parameter statement: The statement.
    /// - Returns: The control flow outcome.
    /// - Throws: ``EOLError`` located at the failing construct.
    package func execute(_ statement: EOLStatement) async throws -> EOLFlow {
        do {
            return try await executeUnlocated(statement)
        } catch let error as EOLError {
            throw error.located(at: statement.range, document: document)
        }
    }

    /// Executes one statement without locating its errors.
    private func executeUnlocated(_ statement: EOLStatement) async throws -> EOLFlow {
        switch statement.kind {
        case .variable(let name, let type, let creates, let arguments, let initialiser, let special):
            try await declareVariable(
                name, type: type, creates: creates, arguments: arguments, initialiser: initialiser, special: special)
            return .normal
        case .assignment(let target, let op, let value):
            try await assign(target, op, value)
            return .normal
        case .expression(let expression):
            _ = try await evaluate(expression)
            return .normal
        case .if(let condition, let then, let otherwise):
            if try await evaluateCondition(condition) { return try await executeBlock(then) }
            if let otherwise { return try await executeBlock(otherwise) }
            return .normal
        case .while(let condition, let body):
            return try await executeWhile(condition, body)
        case .for(let iterator, let collection, let body):
            return try await executeFor(iterator, collection, body)
        case .switch(let subject, let cases, let fallback):
            return try await executeSwitch(subject, cases, fallback)
        case .return(let value):
            guard let value else { return .returned(.undefined) }
            return .returned(try await evaluate(value))
        case .break: return .breakLoop
        case .breakAll: return .breakAll
        case .continue: return .continueLoop
        case .throw(let value):
            var thrown: EOLValue = .undefined
            if let value { thrown = try await evaluate(value) }
            throw EOLError(.userError, await string(of: thrown), range: statement.range, document: document)
        case .delete(let target):
            for value in try await evaluate(target).asElements {
                guard case .element(let element) = value else {
                    throw EOLError(.typeMismatch, "Only model elements can be deleted")
                }
                try await delete(element)
            }
            return .normal
        case .block(let statements):
            return try await executeBlock(statements)
        case .templateText(let text):
            try templateSink().write(text)
            return .normal
        case .templateOutput(let expression):
            let value = try await evaluate(expression)
            try templateSink().write(await string(of: value))
            return .normal
        }
    }

    /// The destination of template output.
    private func templateSink() throws -> any EOLOutputStream {
        guard let templateOutput else {
            throw EOLError(.unsupportedConstruct, "Template output is only available when running a template")
        }
        return templateOutput
    }

    /// Declares a variable.
    private func declareVariable(
        _ name: String, type: EOLTypeReference?, creates: Bool, arguments: [EOLExpression], initialiser: EOLExpression?,
        special: Bool
    ) async throws {
        if frames[frames.count - 1].variables[name] != nil {
            throw EOLError(.invalidDeclaration, "Variable '\(name)' is already declared in this scope")
        }
        let declaredType = try type.map { try resolveType($0) }
        var value: EOLValue = .undefined
        if creates, let declaredType, let type {
            value = try await instantiate(declaredType, reference: type, arguments: arguments)
        } else if let initialiser {
            value = try await evaluate(initialiser)
            if special { value = try await specialAssignmentValue(value) }
            if let declaredType {
                value = try await coerce(value, to: declaredType, context: "variable '\(name)'")
            }
        } else if let declaredType {
            value = defaultValue(of: declaredType)
        }
        declare(name, value)
    }

    /// Converts a value for a declared type, or fails if it does not conform.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - type: The declared type.
    ///   - context: What the value is assigned to, for the error message.
    /// - Returns: The value, with integers widened for `Real`.
    /// - Throws: ``EOLError`` if the value does not conform to the type.
    func coerce(_ value: EOLValue, to type: EOLType, context: String) async throws -> EOLValue {
        guard value.isDefined else { return value }
        if case .real = type, case .integer(let number) = value { return .real(Double(number)) }
        guard try await isKind(value, of: type) else {
            throw EOLError(
                .typeMismatch, "Cannot assign a value of type \(try await typeOf(value).name) to \(context) of type \(type.name)")
        }
        return value
    }

    /// The value of an uninitialised variable of a type.
    ///
    /// - Parameter type: The type.
    /// - Returns: The empty string, zero, false, an empty collection or map, or undefined.
    func defaultValue(of type: EOLType) -> EOLValue {
        switch type {
        case .string: return .string("")
        case .integer: return .integer(0)
        case .real: return .real(0)
        case .boolean: return .boolean(false)
        case .collection(let kind): return .collection(EOLCollection(kind ?? .sequence))
        case .map: return .map(EOLMap())
        default: return .undefined
        }
    }

    /// Executes an assignment.
    private func assign(_ target: EOLExpression, _ op: EOLAssignmentOperator, _ valueExpression: EOLExpression) async throws {
        if op == .ifUndefined, try await evaluate(target).isDefined { return }
        var value = try await evaluate(valueExpression)
        switch op {
        case .special:
            value = try await specialAssignmentValue(value)
        case .add, .subtract, .multiply, .divide:
            let current = try await evaluate(target)
            let binary: EOLBinaryOperator = op == .add ? .plus : op == .subtract ? .minus : op == .multiply ? .times : .divide
            value = try await arithmetic(binary, current, value)
        case .assign, .ifUndefined: break
        }
        try await store(value, into: target)
    }

    /// Converts the value of a special assignment (`::=`) with the first extension that handles it.
    ///
    /// - Parameter value: The value of the right-hand side.
    /// - Returns: The converted value, or the value itself when no extension converts it.
    /// - Throws: ``EOLError`` if a conversion fails.
    func specialAssignmentValue(_ value: EOLValue) async throws -> EOLValue {
        for item in extensions {
            if let converted = try await item.specialAssignment(value, interpreter: self) { return converted }
        }
        return value
    }

    /// Stores a value into an assignable expression.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - target: A variable, property or item expression.
    /// - Throws: ``EOLError`` if the target cannot be assigned.
    package func store(_ value: EOLValue, into target: EOLExpression) async throws {
        switch target.kind {
        case .name(let name):
            try assignVariable(name, value)
        case .property(let receiverExpression, let name, _, let extended):
            let receiver = try await evaluate(receiverExpression)
            guard receiver.isDefined else {
                throw EOLError(.undefinedReceiver, "Cannot set property '\(name)' of an undefined value")
            }
            if extended {
                extendedProperties[receiver, default: [:]][name] = value
            } else {
                try await setProperty(of: receiver, name, to: value)
            }
        case .item(let receiverExpression, let indexExpression):
            let receiver = try await evaluate(receiverExpression)
            let index = try await evaluate(indexExpression)
            switch receiver {
            case .collection(let collection):
                guard let position = index.integerValue.flatMap({ Int(exactly: $0) }),
                    collection.elements.indices.contains(position)
                else {
                    throw EOLError(.indexOutOfBounds, "Index \(index) is out of bounds for a collection of size \(collection.count)")
                }
                collection.replace(at: position, with: value)
                try await writeBack(collection)
            case .map(let map):
                map.put(index, value)
            default:
                throw EOLError(.typeMismatch, "Only collections and maps support item assignment")
            }
        default:
            throw EOLError(.unexpectedToken, "The left-hand side of an assignment must be a variable, property or item")
        }
    }

    /// Evaluates a condition that must be Boolean.
    ///
    /// - Parameter expression: The condition.
    /// - Returns: The truth value.
    /// - Throws: ``EOLError`` if the value is not a Boolean.
    public func evaluateCondition(_ expression: EOLExpression) async throws -> Bool {
        let value = try await evaluate(expression)
        guard let flag = value.booleanValue else {
            throw EOLError(.typeMismatch, "Condition must be Boolean but is \(try await typeOf(value).name)", range: expression.range, document: document)
        }
        return flag
    }

    /// Executes a `while` loop.
    private func executeWhile(_ condition: EOLExpression, _ body: EOLBlock) async throws -> EOLFlow {
        var count: Int64 = 1
        loopDepth += 1
        defer { loopDepth -= 1 }
        while try await evaluateCondition(condition) {
            try checkCancellation()
            let flow = try await withScope([EOLLanguage.Variable.loopCount: .integer(count)]) {
                try await executeStatements(body)
            }
            count += 1
            switch flow {
            case .normal, .continueLoop: continue
            case .breakLoop: return .normal
            case .breakAll: return loopDepth == 1 ? .normal : flow
            case .returned: return flow
            }
        }
        return .normal
    }

    /// Executes a `for` loop.
    private func executeFor(_ iterator: EOLParameter, _ collectionExpression: EOLExpression, _ body: EOLBlock) async throws -> EOLFlow {
        let source = try await evaluate(collectionExpression)
        let items: [EOLValue]
        if case .map(let map) = source { items = map.keys } else { items = source.asElements }
        let filter = try iterator.type.map { try resolveType($0) }
        var count: Int64 = 1
        loopDepth += 1
        defer { loopDepth -= 1 }
        for (position, item) in items.enumerated() {
            try checkCancellation()
            if let filter, !(try await isKind(item, of: filter)) { continue }
            let variables: [String: EOLValue] = [
                iterator.name: item, EOLLanguage.Variable.loopCount: .integer(count),
                EOLLanguage.Variable.hasMore: .boolean(position < items.count - 1),
            ]
            let flow = try await withScope(variables) { try await executeStatements(body) }
            count += 1
            switch flow {
            case .normal, .continueLoop: continue
            case .breakLoop: return .normal
            case .breakAll: return loopDepth == 1 ? .normal : flow
            case .returned: return flow
            }
        }
        return .normal
    }

    /// Executes a `switch` statement.
    ///
    /// Cases do not fall through, except when a case ends with `continue`.
    private func executeSwitch(_ subject: EOLExpression, _ cases: [EOLSwitchCase], _ fallback: EOLBlock?) async throws -> EOLFlow {
        let value = try await evaluate(subject)
        var matched = false
        for candidate in cases {
            if !matched { matched = try await evaluate(candidate.value) == value }
            guard matched else { continue }
            let flow = try await executeBlock(candidate.body)
            if case .continueLoop = flow { continue }
            return flow
        }
        if let fallback {
            let flow = try await executeBlock(fallback)
            if case .continueLoop = flow { return .normal }
            return flow
        }
        return .normal
    }

    // MARK: - Operations

    /// Finds the user-defined operation for a call.
    ///
    /// An operation whose context and parameter types are exactly the types of the
    /// receiver and arguments is preferred. Otherwise the first operation in
    /// dispatch order whose types the receiver and arguments conform to is chosen.
    /// An operation without a context type accepts any receiver.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - receiver: The receiver, or `nil` for a call without a receiver.
    ///   - arguments: The arguments.
    /// - Returns: The operation, or `nil` if none applies.
    /// - Throws: ``EOLError`` if a declared type cannot be resolved.
    public func findOperation(_ name: String, receiver: EOLValue?, arguments: [EOLValue]) async throws -> EOLOperation? {
        guard let positions = operationIndex[name] else { return nil }
        let candidates = positions.map { operations[$0] }.filter { $0.parameters.count == arguments.count }
        for exact in [true, false] {
            for operation in candidates {
                if try await applies(operation, receiver: receiver, arguments: arguments, exact: exact) { return operation }
            }
        }
        return nil
    }

    /// Whether an operation applies to a receiver and arguments.
    private func applies(_ operation: EOLOperation, receiver: EOLValue?, arguments: [EOLValue], exact: Bool) async throws -> Bool {
        if let contextType = operation.contextType {
            guard let receiver, receiver.isDefined else { return false }
            let type = try resolveType(contextType)
            let matches = exact ? try await isType(receiver, of: type) : try await isKind(receiver, of: type)
            guard matches else { return false }
        } else if exact, receiver?.isDefined == true {
            return false
        }
        for (parameter, argument) in zip(operation.parameters, arguments) {
            guard let declared = parameter.type, argument.isDefined else { continue }
            let type = try resolveType(declared)
            let matches = exact ? try await isType(argument, of: type) : try await isKind(argument, of: type)
            if !matches { return false }
        }
        return true
    }

    /// Invokes a user-defined operation.
    ///
    /// - Parameters:
    ///   - operation: The operation.
    ///   - receiver: The receiver bound to `self`.
    ///   - arguments: The arguments.
    /// - Returns: The result.
    /// - Throws: ``EOLError`` if the operation fails or a contract does not hold.
    public func invoke(_ operation: EOLOperation, receiver: EOLValue, arguments: [EOLValue]) async throws -> EOLValue {
        let position = operationIndex[operation.name]?.first {
            operations[$0].range == operation.range && operations[$0].document == operation.document
        }
        let cacheKey = position.map { CacheKey(operation: $0, receiver: receiver) }
        let cached = operation.hasAnnotation(EOLLanguage.Annotation.cached) && operation.parameters.isEmpty
        if cached, let cacheKey, let value = cache[cacheKey] { return value }
        try checkCancellation()
        guard callDepth < maximumCallDepth else {
            throw EOLError(.arithmetic, "Operation calls are nested more than \(maximumCallDepth) levels deep")
        }
        callDepth += 1
        let savedLoopDepth = loopDepth
        loopDepth = 0
        defer {
            callDepth -= 1
            loopDepth = savedLoopDepth
        }
        var variables: [String: EOLValue] = [EOLLanguage.Variable.receiver: receiver]
        for (parameter, argument) in zip(operation.parameters, arguments) {
            var value = argument
            if let declared = parameter.type, case .real = try resolveType(declared), case .integer(let number) = argument {
                value = .real(Double(number))
            }
            variables[parameter.name] = value
        }
        let savedDocument = document
        document = operation.document ?? document
        defer { document = savedDocument }
        let result: EOLValue = try await withScope(variables, isProtected: true) {
            for annotation in operation.annotations where annotation.name == EOLLanguage.Annotation.precondition {
                guard let expression = annotation.expression else { continue }
                guard try await evaluateCondition(expression) else {
                    throw EOLError(
                        .contractViolation, "Precondition of operation '\(operation.name)' does not hold",
                        range: annotation.range, document: document)
                }
            }
            var value: EOLValue = .undefined
            if case .returned(let returned) = try await executeStatements(operation.body) { value = returned }
            if let returnType = operation.returnType {
                value = try await coerce(value, to: try resolveType(returnType), context: "the result of operation '\(operation.name)'")
            }
            declare(EOLLanguage.Variable.result, value)
            for annotation in operation.annotations where annotation.name == EOLLanguage.Annotation.postcondition {
                guard let expression = annotation.expression else { continue }
                guard try await evaluateCondition(expression) else {
                    throw EOLError(
                        .contractViolation, "Postcondition of operation '\(operation.name)' does not hold",
                        range: annotation.range, document: document)
                }
            }
            return value
        }
        if cached, let cacheKey { cache[cacheKey] = result }
        return result
    }

    /// Stops execution if the running task has been cancelled.
    ///
    /// - Throws: ``EOLError`` when the task is cancelled.
    func checkCancellation() throws {
        if Task.isCancelled { throw EOLError(.cancelled, "Execution was cancelled") }
    }

    /// Clears the results of `@cached` operations, for example after the models changed.
    public func clearCache() { cache.removeAll() }
}

/// Parsing of imported modules, which may be written in any dialect that the
/// registered parsers understand.
public enum EOLImportParsing {
    /// The operations and imports of a parsed imported module.
    public struct Parsed: Sendable {
        /// The operations the module declares.
        public var operations: [EOLOperation]
        /// The modules it imports.
        public var imports: [EOLImport]
        /// The problems found while parsing.
        public var diagnostics: [SourceDiagnostic]
    }

    /// Parses an imported module as EOL.
    ///
    /// Dialect modules (EVL, ETL, EGX) that import other dialect modules contribute
    /// only their operations; their rules and constraints are ignored by this parser.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - document: The document identifier.
    /// - Returns: The operations, imports and diagnostics.
    public static func parse(_ text: String, document: String) -> Parsed {
        let result = EOLSyntax.parse(text, document: document)
        return Parsed(operations: result.module.operations, imports: result.module.imports, diagnostics: result.diagnostics)
    }
}
