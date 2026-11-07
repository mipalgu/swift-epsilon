//
//  ETLParser.swift
//  ETL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL

/// Parsing of ETL source text.
public enum ETLSyntax {
    /// Parses an ETL module.
    ///
    /// Besides syntax errors, the diagnostics report rules that extend an unknown
    /// rule, cycles of `extends` and rules declared twice.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - document: The document identifier (for example a URI) used in diagnostics.
    /// - Returns: The module, diagnostics, outline and tokens.
    public static func parse(_ text: String, document: String? = nil) -> EOLParseResult<ETLModule> {
        let scan = EOLLexer.scan(text, document: document)
        var parser = EOLParser(scan: scan, document: document)
        let module = parser.parseETLModule()
        let diagnostics = parser.diagnostics + ETLValidation.diagnostics(for: module)
        return EOLParseResult(
            module: module, diagnostics: diagnostics, outline: parser.outline,
            tokens: EOLSyntax.sourceTokens(of: scan, keywords: ETLLanguage.highlightedKeywords))
    }

    /// Classifies the tokens of ETL source text for syntax highlighting.
    ///
    /// - Parameter text: The source text.
    /// - Returns: The tokens, including comments, in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        EOLSyntax.sourceTokens(of: EOLLexer.scan(text), keywords: ETLLanguage.highlightedKeywords)
    }
}

extension EOLParser {
    /// Parses an ETL module up to the end of the input.
    ///
    /// Each failing declaration is recorded as a diagnostic and skipped, so that
    /// the remaining rules, operations and blocks are still read.
    ///
    /// - Returns: The module.
    package mutating func parseETLModule() -> ETLModule {
        var module = ETLModule(document: document)
        while !isAtEnd {
            let start = position
            do {
                try parseETLMember(into: &module)
            } catch let failure as EOLError {
                record(failure)
                skipDeclaration(from: start)
            } catch {
                skipDeclaration(from: start)
            }
        }
        return module
    }

    /// Parses one import, rule, operation, `pre` or `post` block.
    ///
    /// - Parameter module: The module that receives the member.
    /// - Throws: `EOLError` on a syntax error.
    private mutating func parseETLMember(into module: inout ETLModule) throws {
        if current.isWord(EOLLanguage.Keyword.import) {
            module.imports.append(try parseImport())
            return
        }
        let start = current.range
        var annotations = try parseAnnotations()
        while let word = current.bareName, ETLLanguage.Annotation.all.contains(word), isRuleModifierFollowed {
            annotations.append(EOLAnnotation(name: word, range: advance().range))
        }
        if current.isWord(ETLLanguage.Keyword.rule) {
            module.rules.append(try parseRule(annotations: annotations, start: start))
        } else if current.isWord(ETLLanguage.Keyword.pre) || current.isWord(ETLLanguage.Keyword.post) {
            if let first = annotations.first {
                throw error(.unexpectedToken, "Annotations are not allowed on pre and post blocks", at: first.range)
            }
            let isPre = current.isWord(ETLLanguage.Keyword.pre)
            let block = try parseNamedBlock()
            if isPre { module.pre.append(block) } else { module.post.append(block) }
        } else if current.isWord(EOLLanguage.Keyword.operation) || current.isWord(EOLLanguage.Keyword.function) {
            module.operations.append(try parseOperation(annotations: annotations))
        } else {
            throw unexpected("'rule', 'operation', 'pre', 'post' or 'import'")
        }
    }

    /// Whether the word after the current modifier word is `rule` or another modifier.
    private var isRuleModifierFollowed: Bool {
        guard let next = peek(1).bareName else { return false }
        return next == ETLLanguage.Keyword.rule || ETLLanguage.Annotation.all.contains(next)
    }

    /// Parses `pre name? { … }` or `post name? { … }`.
    ///
    /// - Returns: The block.
    /// - Throws: `EOLError` on a syntax error.
    package mutating func parseNamedBlock() throws -> ETLNamedBlock {
        let keyword = advance()
        var name: String?
        if !current.isSymbol(EOLLanguage.Symbol.openBrace) { name = try expectName().0 }
        let body = try parseBlock()
        let block = ETLNamedBlock(name: name, body: body, range: range(from: keyword.range))
        let kind = keyword.isWord(ETLLanguage.Keyword.pre) ? EOLOutlineKind.pre : EOLOutlineKind.post
        outline.append(
            OutlineNode(
                id: "\(kind):\(name ?? ""):\(outline.count)", kind: kind, name: name ?? kind, range: block.range,
                selectionRange: keyword.range))
        return block
    }

    /// Parses a rule after its annotations.
    ///
    /// - Parameters:
    ///   - annotations: The annotations and modifier words before `rule`.
    ///   - start: The range at which the declaration starts.
    /// - Returns: The rule.
    /// - Throws: `EOLError` on a syntax error.
    private mutating func parseRule(annotations: [EOLAnnotation], start: SourceRange) throws -> ETLRule {
        typealias K = ETLLanguage.Keyword
        advance()
        let (name, nameRange) = try expectName()
        try expectWord(K.transform)
        let source = try parseParameter()
        guard source.type != nil else {
            throw error(.invalidDeclaration, "The source parameter of rule '\(name)' needs a type", at: source.range)
        }
        try expectWord(K.to)
        var targets: [ETLTargetParameter] = []
        repeat {
            let parameter = try parseParameter()
            guard parameter.type != nil else {
                throw error(.invalidDeclaration, "Target parameter '\(parameter.name)' of rule '\(name)' needs a type", at: parameter.range)
            }
            var initialiser: EOLExpression?
            if accept(EOLLanguage.Symbol.equals) { initialiser = try parseExpression() }
            targets.append(ETLTargetParameter(parameter: parameter, initialiser: initialiser))
        } while accept(EOLLanguage.Symbol.comma)
        var extends: [ETLRuleReference] = []
        if acceptWord(K.extends) {
            repeat {
                let (superName, superRange) = try expectName()
                extends.append(ETLRuleReference(name: superName, range: superRange))
            } while accept(EOLLanguage.Symbol.comma)
        }
        try expect(EOLLanguage.Symbol.openBrace)
        var ruleGuard: ETLGuard?
        if acceptWord(K.guard) {
            if accept(EOLLanguage.Symbol.colon) {
                ruleGuard = .expression(try parseExpression())
                accept(EOLLanguage.Symbol.semicolon)
            } else {
                ruleGuard = .block(try parseBlock())
            }
        }
        let body = parseStatements(until: EOLLanguage.Symbol.closeBrace)
        try expect(EOLLanguage.Symbol.closeBrace)
        let rule = ETLRule(
            name: name, nameRange: nameRange, source: source, targets: targets, extends: extends, guard: ruleGuard,
            body: body, annotations: annotations, range: range(from: start), document: document)
        let detail = ([source.type?.description ?? ""] + targets.map { $0.parameter.type?.description ?? "" })
        outline.append(
            OutlineNode(
                id: "rule:\(name):\(outline.count)", kind: EOLOutlineKind.rule, name: name,
                detail: detail[0] + " -> " + detail.dropFirst().joined(separator: ", "), range: rule.range,
                selectionRange: nameRange))
        return rule
    }
}

/// Static checks of an ETL module that need the whole module.
enum ETLValidation {
    /// Reports rules declared twice, references to unknown rules and cycles of `extends`.
    ///
    /// - Parameter module: The module.
    /// - Returns: The diagnostics, in rule order.
    static func diagnostics(for module: ETLModule) -> [SourceDiagnostic] {
        var diagnostics: [SourceDiagnostic] = []
        var seen: Set<String> = []
        let names = Set(module.rules.map(\.name))
        for rule in module.rules {
            let isFirstDeclaration = seen.insert(rule.name).inserted
            if !isFirstDeclaration {
                diagnostics.append(
                    EOLError(
                        .invalidDeclaration, "Rule '\(rule.name)' is declared more than once", range: rule.nameRange,
                        document: rule.document
                    ).diagnostic)
            }
            for reference in rule.extends where !names.contains(reference.name) {
                diagnostics.append(
                    EOLError(
                        .unknownDeclaration, "Rule '\(rule.name)' extends unknown rule '\(reference.name)'",
                        range: reference.range, document: rule.document
                    ).diagnostic)
            }
            if isFirstDeclaration, extendsCycle(from: rule.name, in: module) {
                diagnostics.append(
                    EOLError(
                        .invalidDeclaration, "Rule '\(rule.name)' extends itself through a cycle", range: rule.nameRange,
                        document: rule.document
                    ).diagnostic)
            }
        }
        return diagnostics
    }

    /// Whether following `extends` from a rule leads back to it.
    ///
    /// - Parameters:
    ///   - name: The rule name.
    ///   - module: The module.
    /// - Returns: `true` if the rule is its own (indirect) super-rule.
    static func extendsCycle(from name: String, in module: ETLModule) -> Bool {
        var visited: Set<String> = []
        var pending = module.rule(named: name)?.extends.map(\.name) ?? []
        while let next = pending.popLast() {
            if next == name { return true }
            guard visited.insert(next).inserted else { continue }
            pending += module.rule(named: next)?.extends.map(\.name) ?? []
        }
        return false
    }
}
