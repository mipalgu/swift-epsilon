//
//  EVLParser.swift
//  EVL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL

/// Parsing of EVL source text.
public enum EVLSyntax {
    /// Parses an EVL module.
    ///
    /// - Parameters:
    ///   - text: The source text.
    ///   - document: The document identifier used in diagnostics.
    /// - Returns: The module, diagnostics, outline and tokens.
    public static func parse(_ text: String, document: String? = nil) -> EOLParseResult<EVLModule> {
        let scan = EOLLexer.scan(text, document: document)
        var parser = EOLParser(scan: scan, document: document)
        let module = parser.parseEVLModule()
        return EOLParseResult(
            module: module, diagnostics: parser.diagnostics, outline: parser.outline,
            tokens: EOLSyntax.sourceTokens(of: scan, keywords: EOLLanguage.Keyword.all.union(EVLLanguage.keywords)))
    }
}

extension EOLParser {
    /// Parses an EVL module up to the end of the input.
    ///
    /// - Returns: The module with every declaration that parsed correctly.
    mutating func parseEVLModule() -> EVLModule {
        var module = EVLModule(document: document)
        while !isAtEnd {
            let start = position
            do {
                if current.isWord(EOLLanguage.Keyword.import) {
                    module.imports.append(try parseImport())
                    continue
                }
                let annotations = try parseAnnotations()
                if current.isWord(EVLLanguage.context) {
                    module.contexts.append(try parseContext(annotations: annotations))
                } else if current.isWord(EVLLanguage.pre) || current.isWord(EVLLanguage.post) {
                    let isPre = current.isWord(EVLLanguage.pre)
                    let block = try parseNamedBlock()
                    if isPre { module.pre.append(block) } else { module.post.append(block) }
                } else if current.isWord(EOLLanguage.Keyword.operation) || current.isWord(EOLLanguage.Keyword.function) {
                    module.operations.append(try parseOperation(annotations: annotations))
                } else if current.isWord(EVLLanguage.constraint) || current.isWord(EVLLanguage.critique) {
                    throw error(
                        .unsupportedConstruct, "Constraints outside a context are not supported", at: current.range)
                } else {
                    throw unexpected("'context', 'pre', 'post', 'operation' or 'import'")
                }
            } catch let failure as EOLError {
                record(failure)
                skipDeclaration(from: start)
            } catch {
                skipDeclaration(from: start)
            }
        }
        return module
    }

    /// Parses `pre name? { … }` or `post name? { … }`.
    private mutating func parseNamedBlock() throws -> EVLNamedBlock {
        let keyword = advance()
        var name: String?
        if case .identifier(let word, _) = current.kind { name = word; advance() }
        let body = try parseBlock()
        let block = EVLNamedBlock(name: name, body: body, range: range(from: keyword.range))
        let kind = keyword.isWord(EVLLanguage.pre) ? EOLOutlineKind.pre : EOLOutlineKind.post
        outline.append(
            OutlineNode(
                id: "\(kind):\(outline.count)", kind: kind, name: name ?? kind, range: block.range,
                selectionRange: keyword.range))
        return block
    }

    /// Parses a context declaration.
    private mutating func parseContext(annotations: [EOLAnnotation]) throws -> EVLContext {
        let start = annotations.first?.range ?? current.range
        let keyword = advance()
        let type = try parseTypeReference()
        try expect(EOLLanguage.Symbol.openBrace)
        var guardCondition: EVLExpressionOrBlock?
        var constraints: [EVLConstraint] = []
        var children: [OutlineNode] = []
        while !current.isSymbol(EOLLanguage.Symbol.closeBrace), !isAtEnd {
            let memberStart = position
            do {
                if current.isWord(EVLLanguage.guard) {
                    advance()
                    guardCondition = try parseExpressionOrBlock()
                    continue
                }
                let memberAnnotations = try parseAnnotations()
                guard current.isWord(EVLLanguage.constraint) || current.isWord(EVLLanguage.critique) else {
                    throw unexpected("'guard', 'constraint' or 'critique'")
                }
                let constraint = try parseConstraint(annotations: memberAnnotations)
                constraints.append(constraint)
                children.append(
                    OutlineNode(
                        id: "\(type.description):\(constraint.name)",
                        kind: constraint.isCritique ? EOLOutlineKind.critique : EOLOutlineKind.constraint,
                        name: constraint.name, range: constraint.range, selectionRange: constraint.nameRange))
            } catch let failure as EOLError {
                record(failure)
                skipDeclaration(from: memberStart)
            }
        }
        try expect(EOLLanguage.Symbol.closeBrace)
        let isLazy = annotations.contains { $0.name == EVLLanguage.lazy }
        let context = EVLContext(
            type: type, isLazy: isLazy, guardCondition: guardCondition, constraints: constraints, range: range(from: start))
        outline.append(
            OutlineNode(
                id: "context:\(type.description):\(outline.count)", kind: EOLOutlineKind.context, name: type.description,
                range: context.range, selectionRange: keyword.range.union(type.range), children: children))
        return context
    }

    /// Parses a constraint or critique.
    private mutating func parseConstraint(annotations: [EOLAnnotation]) throws -> EVLConstraint {
        let start = annotations.first?.range ?? current.range
        let isCritique = advance().isWord(EVLLanguage.critique)
        let (name, nameRange) = try expectName()
        try expect(EOLLanguage.Symbol.openBrace)
        var constraint = EVLConstraint(
            name: name, isCritique: isCritique, isLazy: annotations.contains { $0.name == EVLLanguage.lazy },
            range: start, nameRange: nameRange)
        while !current.isSymbol(EOLLanguage.Symbol.closeBrace), !isAtEnd {
            if acceptWord(EVLLanguage.guard) {
                constraint.guardCondition = try parseExpressionOrBlock()
            } else if acceptWord(EVLLanguage.check) {
                constraint.check = try parseExpressionOrBlock()
            } else if acceptWord(EVLLanguage.message) {
                constraint.message = try parseExpressionOrBlock()
            } else if current.isWord(EVLLanguage.fix) {
                constraint.fixes.append(try parseFix())
            } else {
                throw unexpected("'guard', 'check', 'message' or 'fix'")
            }
        }
        try expect(EOLLanguage.Symbol.closeBrace)
        constraint.range = range(from: start)
        return constraint
    }

    /// Parses a fix.
    private mutating func parseFix() throws -> EVLFix {
        let start = advance().range
        try expect(EOLLanguage.Symbol.openBrace)
        var guardCondition: EVLExpressionOrBlock?
        var title: EVLExpressionOrBlock?
        var body: EOLBlock = []
        while !current.isSymbol(EOLLanguage.Symbol.closeBrace), !isAtEnd {
            if acceptWord(EVLLanguage.guard) {
                guardCondition = try parseExpressionOrBlock()
            } else if acceptWord(EVLLanguage.title) {
                title = try parseExpressionOrBlock()
            } else if acceptWord(EVLLanguage.do) {
                body = try parseBlock()
            } else {
                throw unexpected("'guard', 'title' or 'do'")
            }
        }
        try expect(EOLLanguage.Symbol.closeBrace)
        return EVLFix(guardCondition: guardCondition, title: title, body: body, range: range(from: start))
    }

    /// Parses `: expression` (with an optional semicolon) or a block.
    private mutating func parseExpressionOrBlock() throws -> EVLExpressionOrBlock {
        if accept(EOLLanguage.Symbol.colon) {
            let expression = try parseExpression()
            accept(EOLLanguage.Symbol.semicolon)
            return .expression(expression)
        }
        if current.isSymbol(EOLLanguage.Symbol.openBrace) { return .block(try parseBlock()) }
        throw unexpected("':' or '{'")
    }
}
