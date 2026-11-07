//
//  EVLValidator.swift
//  EVL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import EOL

/// A fix offered for one unsatisfied constraint on one element.
public struct EVLFixOffer {
    /// The title shown to the user.
    public let title: String
    /// The fix declaration.
    public let fix: EVLFix
    /// The element the fix repairs.
    public let element: EOLValue
    /// The variables of the constraint's `check` block, visible to the fix.
    let variables: [String: EOLValue]
}

/// A constraint or critique that an element does not satisfy.
public struct EVLUnsatisfiedConstraint {
    /// The name of the constraint.
    public let constraint: String
    /// The type name of the context that declares it.
    public let context: String
    /// The element that does not satisfy the constraint.
    public let element: EOLValue
    /// The message, either from the constraint or a default one.
    public let message: String
    /// Whether the constraint is a critique.
    public let isCritique: Bool
    /// The fixes offered.
    public let fixes: [EVLFixOffer]
    /// The source range of the constraint declaration.
    public let range: SourceRange
    /// The document that declares the constraint.
    public let document: String?

    /// The severity: warning for a critique, error otherwise.
    public var severity: DiagnosticSeverity { isCritique ? .warning : .error }

    /// The result as a diagnostic located at the constraint declaration.
    public var diagnostic: SourceDiagnostic {
        SourceDiagnostic(
            severity: severity,
            code: isCritique ? EVLLanguage.unsatisfiedCritiqueCode : EVLLanguage.unsatisfiedConstraintCode,
            message: message, range: range, document: document)
    }
}

/// The outcome of validating models against an EVL module.
public struct EVLValidationResult {
    /// The unsatisfied constraints and critiques, in the order they were found.
    public let unsatisfied: [EVLUnsatisfiedConstraint]

    /// The results as diagnostics.
    public var diagnostics: [SourceDiagnostic] { unsatisfied.map(\.diagnostic) }

    /// The unsatisfied constraints that are errors.
    public var errors: [EVLUnsatisfiedConstraint] { unsatisfied.filter { !$0.isCritique } }

    /// The unsatisfied critiques, which are warnings.
    public var warnings: [EVLUnsatisfiedConstraint] { unsatisfied.filter(\.isCritique) }

    /// Whether every constraint holds; critiques do not count.
    public var isValid: Bool { errors.isEmpty }
}

/// Validates models against the constraints of an EVL module.
///
/// Validation runs in four steps, as in Epsilon: the `pre` blocks run (and the
/// variables they declare stay visible); every non-lazy constraint of every
/// non-lazy context is checked for every instance of the context type,
/// including instances of subtypes, unless the context or constraint guard
/// excludes it; unsatisfied constraints are recorded with their message and
/// fixes; finally the `post` blocks run. Results are cached per constraint and
/// element, so `satisfies` never checks a constraint twice. Fixes are offered
/// and can be applied with ``apply(_:)``.
///
/// ```swift
/// let module = try EVLSyntax.parse(source, document: "rules.evl").get()
/// let validator = EVLValidator(interpreter: EOLInterpreter(models: [library]))
/// let result = try await validator.validate(module)
/// ```
public final class EVLValidator: EOLExtension {
    /// The interpreter that evaluates the constraints.
    public let interpreter: EOLInterpreter

    /// The module being validated.
    private var module = EVLModule()

    /// The unsatisfied constraints found so far.
    private var unsatisfied: [EVLUnsatisfiedConstraint] = []

    /// The cached results by constraint position and element.
    private var results: [ResultKey: Bool] = [:]

    /// The key of a cached result.
    private struct ResultKey: Hashable {
        /// The position of the context.
        let context: Int
        /// The position of the constraint within its context.
        let constraint: Int
        /// The element.
        let element: EOLValue
    }

    /// Creates a validator.
    ///
    /// - Parameter interpreter: The interpreter that evaluates the constraints; the
    ///   validator registers itself as one of its extensions.
    public init(interpreter: EOLInterpreter) {
        self.interpreter = interpreter
        interpreter.extensions.append(self)
    }

    /// Validates the interpreter's models.
    ///
    /// - Parameter module: The EVL module.
    /// - Returns: The unsatisfied constraints and critiques.
    /// - Throws: `EOLError` if a type cannot be resolved, an import fails or a block fails.
    public func validate(_ module: EVLModule) async throws -> EVLValidationResult {
        self.module = module
        unsatisfied = []
        results = [:]
        interpreter.document = module.document
        try interpreter.register(operations: module.operations, imports: module.imports, document: module.document)
        for block in module.pre { try await interpreter.executeInGlobalScope(block.body) }
        for (contextIndex, context) in module.contexts.enumerated() where !context.isLazy {
            let type = try interpreter.resolveType(context.type)
            let instances = try await interpreter.allInstances(of: type, exact: false).asElements
            for element in instances {
                guard try await contextApplies(context, to: element) else { continue }
                for (constraintIndex, constraint) in context.constraints.enumerated() where !constraint.isLazy {
                    _ = try await check(contextIndex, constraintIndex, element)
                }
            }
        }
        for block in module.post { try await interpreter.executeInGlobalScope(block.body) }
        return EVLValidationResult(unsatisfied: unsatisfied)
    }

    /// Applies a fix.
    ///
    /// The fix runs with `self` bound to the element and with the variables of the
    /// constraint's `check` block in scope.
    ///
    /// - Parameter offer: The fix to apply.
    /// - Throws: `EOLError` if the fix fails.
    public func apply(_ offer: EVLFixOffer) async throws {
        var variables = offer.variables
        variables[EOLLanguage.Variable.receiver] = offer.element
        try await interpreter.execute(offer.fix.body, variables: variables)
        interpreter.clearCache()
    }

    // MARK: - Checking

    /// Whether a context's guard admits an element.
    private func contextApplies(_ context: EVLContext, to element: EOLValue) async throws -> Bool {
        guard let guardCondition = context.guardCondition else { return true }
        return try await condition(guardCondition, element: element, what: "guard of context \(context.type)")
    }

    /// Checks one constraint on one element, recording it if it does not hold.
    ///
    /// - Returns: Whether the constraint holds (or does not apply).
    private func check(_ contextIndex: Int, _ constraintIndex: Int, _ element: EOLValue) async throws -> Bool {
        let key = ResultKey(context: contextIndex, constraint: constraintIndex, element: element)
        if let cached = results[key] { return cached }
        let context = module.contexts[contextIndex]
        let constraint = context.constraints[constraintIndex]
        if let guardCondition = constraint.guardCondition,
            !(try await condition(guardCondition, element: element, what: "guard of \(constraint.name)"))
        {
            results[key] = true
            return true
        }
        guard let checkCondition = constraint.check else {
            results[key] = true
            return true
        }
        let holds: Bool = try await interpreter.withScope([EOLLanguage.Variable.receiver: element]) {
            let holds = try await value(of: checkCondition, what: "check of \(constraint.name)")
            results[key] = holds
            if !holds { try await record(constraint, of: context, for: element) }
            return holds
        }
        return holds
    }

    /// Records an unsatisfied constraint, evaluating its message and fixes in the check's scope.
    private func record(_ constraint: EVLConstraint, of context: EVLContext, for element: EOLValue) async throws {
        let label = await interpreter.string(of: element)
        var message: String
        if let messageExpression = constraint.message {
            message = await interpreter.string(of: try await evaluate(messageExpression))
        } else {
            let kind = constraint.isCritique ? EVLLanguage.critique.capitalised : EVLLanguage.constraint.capitalised
            message = "\(kind) \(constraint.name) is not satisfied for \(label)"
        }
        let variables = interpreter.innermostScopeVariables
        var offers: [EVLFixOffer] = []
        for fix in constraint.fixes {
            let offered: Bool = try await interpreter.withScope {
                guard let guardCondition = fix.guardCondition else { return true }
                return try await self.condition(guardCondition, element: element, what: "guard of a fix of \(constraint.name)")
            }
            guard offered else { continue }
            var title = "Fix \(constraint.name)"
            if let titleExpression = fix.title {
                title = await interpreter.string(of: try await interpreter.withScope { try await self.evaluate(titleExpression) })
            }
            offers.append(EVLFixOffer(title: title, fix: fix, element: element, variables: variables))
        }
        unsatisfied.append(
            EVLUnsatisfiedConstraint(
                constraint: constraint.name, context: context.type.description, element: element, message: message,
                isCritique: constraint.isCritique, fixes: offers, range: constraint.range, document: module.document))
    }

    /// Evaluates a guard in its own scope with `self` bound.
    private func condition(_ condition: EVLExpressionOrBlock, element: EOLValue, what: String) async throws -> Bool {
        try await interpreter.withScope([EOLLanguage.Variable.receiver: element]) {
            try await value(of: condition, what: what)
        }
    }

    /// Evaluates a Boolean expression or block in the current scope.
    private func value(of condition: EVLExpressionOrBlock, what: String) async throws -> Bool {
        let result = try await evaluate(condition)
        guard let flag = result.booleanValue else {
            throw EOLError(.typeMismatch, "The \(what) must be Boolean but is \(try await interpreter.typeOf(result).name)")
        }
        return flag
    }

    /// Evaluates an expression or a value-returning block in the current scope.
    private func evaluate(_ value: EVLExpressionOrBlock) async throws -> EOLValue {
        switch value {
        case .expression(let expression):
            return try await interpreter.evaluate(expression)
        case .block(let statements):
            for statement in statements {
                if case .returned(let result) = try await interpreter.execute(statement) { return result }
            }
            return .undefined
        }
    }

    // MARK: - EOLExtension

    /// Provides `satisfies`, `satisfiesAll` and `satisfiesOne` on elements.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - receiver: The receiver.
    ///   - arguments: The constraint names, as strings or one collection of strings.
    ///   - interpreter: The interpreter.
    /// - Returns: Whether the receiver satisfies the constraints, or `nil` for other operations.
    /// - Throws: `EOLError` if a constraint is unknown or fails.
    public func call(_ name: String, on receiver: EOLValue?, arguments: [EOLValue], interpreter: EOLInterpreter) async throws
        -> EOLValue?
    {
        guard [EVLLanguage.satisfies, EVLLanguage.satisfiesAll, EVLLanguage.satisfiesOne].contains(name),
            let receiver, receiver.isDefined
        else { return nil }
        let names = arguments.flatMap(\.asElements).compactMap(\.stringValue)
        var outcomes: [Bool] = []
        for constraintName in names {
            outcomes.append(try await satisfies(receiver, constraintName))
        }
        if name == EVLLanguage.satisfiesOne { return .boolean(outcomes.contains(true)) }
        return .boolean(!outcomes.contains(false))
    }

    /// Whether an element satisfies a named constraint, checking it on demand.
    private func satisfies(_ element: EOLValue, _ name: String) async throws -> Bool {
        var found = false
        for (contextIndex, context) in module.contexts.enumerated() {
            guard let constraintIndex = context.constraints.firstIndex(where: { $0.name == name }) else { continue }
            guard try await interpreter.isKind(element, of: try interpreter.resolveType(context.type)) else { continue }
            found = true
            guard try await contextApplies(context, to: element) else { continue }
            if !(try await check(contextIndex, constraintIndex, element)) { return false }
        }
        if !found {
            throw EOLError(.unknownDeclaration, "No constraint '\(name)' applies to \(await interpreter.string(of: element))")
        }
        return true
    }
}

extension String {
    /// The string with its first character in upper case.
    var capitalised: String { prefix(1).uppercased() + dropFirst() }
}
