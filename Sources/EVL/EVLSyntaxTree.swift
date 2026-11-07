//
//  EVLSyntaxTree.swift
//  EVL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL

/// The reserved words of the Epsilon Validation Language, in addition to those of EOL.
public enum EVLLanguage {
    /// Introduces the constraints of a type.
    public static let context = "context"
    /// Introduces a constraint whose violation is an error.
    public static let constraint = "constraint"
    /// Introduces a constraint whose violation is a warning.
    public static let critique = "critique"
    /// Limits where a context, constraint or fix applies.
    public static let `guard` = "guard"
    /// The condition a constraint checks.
    public static let check = "check"
    /// The message reported when a constraint does not hold.
    public static let message = "message"
    /// Introduces a fix.
    public static let fix = "fix"
    /// The title of a fix.
    public static let title = "title"
    /// The statements of a fix.
    public static let `do` = "do"
    /// A block that runs before validation.
    public static let pre = "pre"
    /// A block that runs after validation.
    public static let post = "post"
    /// The annotation that makes a context or constraint run only on demand.
    public static let lazy = "lazy"

    /// The words that EVL adds to the EOL keywords for highlighting.
    public static let keywords: Set<String> = [context, constraint, critique, `guard`, check, message, fix, title, `do`, pre, post]

    /// The operation that tests whether an element satisfies a constraint.
    public static let satisfies = "satisfies"
    /// The operation that tests whether an element satisfies all of several constraints.
    public static let satisfiesAll = "satisfiesAll"
    /// The operation that tests whether an element satisfies at least one of several constraints.
    public static let satisfiesOne = "satisfiesOne"

    /// The diagnostic code of an unsatisfied constraint.
    public static let unsatisfiedConstraintCode = "evl.unsatisfiedConstraint"
    /// The diagnostic code of an unsatisfied critique.
    public static let unsatisfiedCritiqueCode = "evl.unsatisfiedCritique"
}

/// Either an expression (`check : expression`) or a block that returns a value (`check { … }`).
public enum EVLExpressionOrBlock: Sendable, Hashable {
    /// An expression.
    case expression(EOLExpression)
    /// A block whose `return` statement supplies the value.
    case block(EOLBlock)
}

/// A named `pre` or `post` block.
public struct EVLNamedBlock: Sendable, Hashable {
    /// The optional name of the block.
    public var name: String?
    /// The statements.
    public var body: EOLBlock
    /// The source range.
    public var range: SourceRange

    /// Creates a named block.
    ///
    /// - Parameters:
    ///   - name: The optional name.
    ///   - body: The statements.
    ///   - range: The source range.
    public init(name: String?, body: EOLBlock, range: SourceRange) {
        self.name = name
        self.body = body
        self.range = range
    }
}

/// A fix offered for an unsatisfied constraint.
public struct EVLFix: Sendable, Hashable {
    /// The condition under which the fix is offered.
    public var guardCondition: EVLExpressionOrBlock?
    /// The title shown to the user.
    public var title: EVLExpressionOrBlock?
    /// The statements that repair the model.
    public var body: EOLBlock
    /// The source range.
    public var range: SourceRange

    /// Creates a fix.
    ///
    /// - Parameters:
    ///   - guardCondition: The condition under which the fix is offered.
    ///   - title: The title.
    ///   - body: The repairing statements.
    ///   - range: The source range.
    public init(guardCondition: EVLExpressionOrBlock?, title: EVLExpressionOrBlock?, body: EOLBlock, range: SourceRange) {
        self.guardCondition = guardCondition
        self.title = title
        self.body = body
        self.range = range
    }
}

/// A constraint or critique.
public struct EVLConstraint: Sendable, Hashable {
    /// The name of the constraint.
    public var name: String
    /// Whether the constraint is a critique, whose violation is a warning.
    public var isCritique: Bool
    /// Whether the constraint is checked only when another constraint asks for it.
    public var isLazy: Bool
    /// The condition under which the constraint applies.
    public var guardCondition: EVLExpressionOrBlock?
    /// The condition the constraint checks; a constraint without one always holds.
    public var check: EVLExpressionOrBlock?
    /// The message reported when the constraint does not hold.
    public var message: EVLExpressionOrBlock?
    /// The fixes offered when the constraint does not hold.
    public var fixes: [EVLFix]
    /// The source range of the declaration.
    public var range: SourceRange
    /// The source range of the name.
    public var nameRange: SourceRange

    /// Creates a constraint.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - isCritique: Whether it is a critique.
    ///   - isLazy: Whether it is lazy.
    ///   - guardCondition: The guard.
    ///   - check: The check.
    ///   - message: The message.
    ///   - fixes: The fixes.
    ///   - range: The source range.
    ///   - nameRange: The source range of the name.
    public init(
        name: String, isCritique: Bool, isLazy: Bool, guardCondition: EVLExpressionOrBlock? = nil,
        check: EVLExpressionOrBlock? = nil, message: EVLExpressionOrBlock? = nil, fixes: [EVLFix] = [],
        range: SourceRange, nameRange: SourceRange
    ) {
        self.name = name
        self.isCritique = isCritique
        self.isLazy = isLazy
        self.guardCondition = guardCondition
        self.check = check
        self.message = message
        self.fixes = fixes
        self.range = range
        self.nameRange = nameRange
    }
}

/// The constraints of a type.
public struct EVLContext: Sendable, Hashable {
    /// The type whose instances the constraints apply to.
    public var type: EOLTypeReference
    /// Whether the context is checked only when a constraint of it is asked for.
    public var isLazy: Bool
    /// The condition under which the context applies to an instance.
    public var guardCondition: EVLExpressionOrBlock?
    /// The constraints and critiques, in source order.
    public var constraints: [EVLConstraint]
    /// The source range.
    public var range: SourceRange

    /// Creates a context.
    ///
    /// - Parameters:
    ///   - type: The type.
    ///   - isLazy: Whether the context is lazy.
    ///   - guardCondition: The guard.
    ///   - constraints: The constraints.
    ///   - range: The source range.
    public init(
        type: EOLTypeReference, isLazy: Bool, guardCondition: EVLExpressionOrBlock?, constraints: [EVLConstraint],
        range: SourceRange
    ) {
        self.type = type
        self.isLazy = isLazy
        self.guardCondition = guardCondition
        self.constraints = constraints
        self.range = range
    }
}

/// A parsed EVL module.
public struct EVLModule: Sendable, Hashable {
    /// The document the module was read from, if known.
    public var document: String?
    /// The imports.
    public var imports: [EOLImport] = []
    /// The operations.
    public var operations: [EOLOperation] = []
    /// The `pre` blocks, in source order.
    public var pre: [EVLNamedBlock] = []
    /// The contexts, in source order.
    public var contexts: [EVLContext] = []
    /// The `post` blocks, in source order.
    public var post: [EVLNamedBlock] = []

    /// Creates an empty module.
    ///
    /// - Parameter document: The source document.
    public init(document: String? = nil) {
        self.document = document
    }
}
