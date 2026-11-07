//
//  ETLSyntaxTests.swift
//  ETLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL
import Testing

@testable import ETL

@Suite("ETL parser")
struct ETLSyntaxTests {
    /// A module that uses every ETL construct.
    static let complete = """
        import 'helpers.eol';
        pre setup { var x = 1; }
        @abstract
        rule Base transform s : Tree!Tree to n : Graph!Node { n.leaf = false; }
        @primary @greedy
        rule Main
            transform t : Tree!Tree
            to n : Graph!Node, m : Graph!Node = null
            extends Base {
            guard : t.label.isDefined()
            n.name = t.label;
        }
        @lazy
        rule Later transform t : Tree!Leaf to n : Graph!Node {
            guard { return true; }
        }
        operation Tree!Tree size() : Integer { return 1; }
        post { 'done'.println(); }
        """

    @Test("All constructs of a module are read")
    func complete() throws {
        let result = ETLSyntax.parse(Self.complete, document: "complete.etl")
        let module = try result.get()
        #expect(module.imports.map(\.path) == ["helpers.eol"])
        #expect(module.pre.map(\.name) == ["setup"])
        #expect(module.post.count == 1)
        #expect(module.operations.map(\.name) == ["size"])
        #expect(module.rules.map(\.name) == ["Base", "Main", "Later"])
        let main = module.rules[1]
        #expect(main.isPrimary && main.isGreedy && !main.isLazy && !main.isAbstract)
        #expect(main.source.type?.description == "Tree!Tree")
        #expect(main.targets.map(\.name) == ["n", "m"])
        #expect(main.targets[1].initialiser != nil)
        #expect(main.extends.map(\.name) == ["Base"])
        guard case .expression? = main.guard else {
            Issue.record("expected an expression guard")
            return
        }
        guard case .block? = module.rules[2].guard else {
            Issue.record("expected a block guard")
            return
        }
        #expect(module.rules[0].isAbstract)
        #expect(module.rules[2].isLazy)
    }

    @Test("The outline lists imports, blocks, rules and operations in source order")
    func outline() {
        let outline = ETLSyntax.parse(Self.complete).outline
        #expect(outline.map(\.kind) == ["import", "pre", "rule", "rule", "rule", "operation", "post"])
        let main = outline[3]
        #expect(main.name == "Main")
        #expect(main.detail == "Tree!Tree -> Graph!Node, Graph!Node")
        #expect(main.selectionRange.start.line == 6)
        #expect(main.selectionRange.start.column == 6)
    }

    @Test("Highlighting treats ETL words as keywords")
    func highlighting() {
        let tokens = ETLSyntax.tokens(in: "rule R transform t : A to n : B { }")
        #expect(tokens.filter { $0.kind == .keyword }.count == 3)
    }

    @Test("An unknown super-rule is reported at its name")
    func unknownSuperRule() {
        let result = ETLSyntax.parse("rule R transform t : A to n : B\n  extends Missing { }")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].code == EOLDiagnosticCode.unknownDeclaration.rawValue)
        #expect(result.diagnostics[0].range?.start.line == 2)
        #expect(result.diagnostics[0].range?.start.column == 11)
    }

    @Test("Cycles of extends and duplicate rules are reported")
    func inconsistentRules() {
        let result = ETLSyntax.parse(
            """
            rule A transform t : X to n : Y extends B { }
            rule B transform t : X to n : Y extends A { }
            rule A transform t : X to n : Y { }
            """)
        let codes = result.diagnostics.map(\.code)
        #expect(codes.filter { $0 == EOLDiagnosticCode.invalidDeclaration.rawValue }.count == 3)
        #expect(result.diagnostics.contains { $0.message.contains("more than once") && $0.range?.start.line == 3 })
    }

    @Test("Syntax errors carry positions, and the following rules are still read")
    func recovery() {
        let result = ETLSyntax.parse(
            """
            rule Broken transform t : Tree!Tree n : Graph!Node { }
            rule Fine transform t : Tree!Tree to n : Graph!Node { n.name = 'x'; }
            """)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].range?.start.line == 1)
        #expect(result.diagnostics[0].range?.start.column == 37)
        #expect(result.module.rules.map(\.name) == ["Fine"])
    }

    @Test("Parameters without types are rejected", arguments: [
        "rule R transform t to n : B { }",
        "rule R transform t : A to n { }",
    ])
    func untypedParameters(source: String) {
        let result = ETLSyntax.parse(source)
        #expect(result.diagnostics.first?.code == EOLDiagnosticCode.invalidDeclaration.rawValue)
    }

    @Test("Statements outside rules and blocks are rejected")
    func strayStatement() {
        let result = ETLSyntax.parse("'hello'.println();\nrule R transform t : A to n : B { }")
        #expect(result.diagnostics.first?.code == EOLDiagnosticCode.unexpectedToken.rawValue)
        #expect(result.diagnostics.first?.range?.start.line == 1)
        #expect(result.module.rules.count == 1)
    }
}
