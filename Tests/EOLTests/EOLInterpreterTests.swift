//
//  EOLInterpreterTests.swift
//  EOLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EpsilonTestSupport
import Testing

@testable import EOL

/// One program and the text it should print.
struct GoldenCase: Sendable, CustomTestStringConvertible {
    /// The program.
    let source: String
    /// The expected output.
    let expected: String
    /// A short label for the test report.
    let testDescription: String

    init(_ label: String, _ source: String, _ expected: String) {
        self.source = source
        self.expected = expected
        testDescription = label
    }
}

@Suite("EOL expressions and statements")
struct EOLInterpreterTests {
    static let expressionsCases: [GoldenCase] = [
        GoldenCase("integer arithmetic", "(1 + 2 * 3).println(); (7 / 2).println(); (-7 / 2).println();", "7\n3\n-3\n"),
        GoldenCase("real arithmetic", "(1 + 0.5).println(); (3.0 * 2).println(); (1 / 4.0).println();", "1.5\n6.0\n0.25\n"),
        GoldenCase("string concatenation", "('a' + 1 + 2).println(); (1 + 2 + 'a').println();", "a12\n3a\n"),
        GoldenCase("equality", "(1 = 1.0).println(); ('a' == 'a').println(); (1 <> 2).println(); (null = null).println();", "true\ntrue\ntrue\ntrue\n"),
        GoldenCase("logic", "(true and false or true).println(); (false implies false).println(); (true xor true).println(); (not true).println();", "true\ntrue\nfalse\nfalse\n"),
        GoldenCase("short circuit", "var s : Sequence; (s.isEmpty() or s.first() > 0).println();", "true\n"),
        GoldenCase("ternary and elvis", "(1 > 2 ? 'a' : 'b').println(); (true ? 1 else 2).println(); (null ?: 'x').println();", "b\n1\nx\n"),
        GoldenCase("safe navigation", "var n = null; n?.foo.println(); (n?.size()).isDefined().println();", "null\nfalse\n"),
        GoldenCase("comparison of strings", "('apple' < 'banana').println();", "true\n"),
        GoldenCase("collection literal with range", "Sequence{1..4}.println(); Sequence{3..1}.println();", "Sequence {1, 2, 3, 4}\nSequence {3, 2, 1}\n"),
        GoldenCase("set semantics", "Set{1, 2, 2, 3}.size().println(); OrderedSet{3, 1, 3}.println();", "3\nOrderedSet {3, 1}\n"),
        GoldenCase("map literal", "var m = Map{'a' = 1, 'b' = 2}; m.get('b').println(); m.println(); m['a'].println();", "2\nMap {a=1, b=2}\n1\n"),
        GoldenCase("item selector", "var s = Sequence{'x', 'y'}; s[1].println(); s[0] = 'z'; s.println();", "y\nSequence {z, y}\n"),
        GoldenCase("reals print as Java does", "2.0.println(); 1.5E10.println(); 0.0001.println();", "2.0\n1.5E10\n1.0E-4\n"),
        GoldenCase("type tests", "1.isKindOf(Real).println(); 1.isTypeOf(Real).println(); 'a'.type().name.println(); Sequence{}.isKindOf(Collection).println();", "true\nfalse\nString\ntrue\n"),
        GoldenCase("conversions", "'42'.asInteger().println(); '2.5'.asReal().println(); 3.asString().length().println(); 3.7.floor().println();", "42\n2.5\n1\n3\n"),
    ]

    @Test("Expressions evaluate as in Epsilon", arguments: expressionsCases)
    func expressions(test: GoldenCase) async throws {
        #expect(try await EpsilonFixtures.run(test.source) == test.expected)
    }

    static let stringsCases: [GoldenCase] = [
        GoldenCase("case", "'hello'.toUpperCase().println(); 'Hello'.firstToLowerCase().println(); 'abc'.ftuc().println();", "HELLO\nhello\nAbc\n"),
        GoldenCase("zero-based substring", "'library'.substring(1, 4).println(); 'library'.substring(3).println(); 'abc'.characterAt(2).println();", "ibr\nrary\nc\n"),
        GoldenCase("search", "'banana'.indexOf('an').println(); 'banana'.lastIndexOf('an').println(); 'ana'.isSubstringOf('banana').println();", "1\n3\ntrue\n"),
        GoldenCase("split and regex", "'a, b,c'.split(',\\\\s*').println(); 'abc123'.matches('[a-z]+[0-9]+').println(); 'a-b-c'.replace('-', '+').println();", "Sequence {a, b, c}\ntrue\na+b+c\n"),
        GoldenCase("pad and trim", "'foo'.pad(5, '*', true).println(); '  x '.trim().println();", "foo**\nx\n"),
    ]

    @Test("String operations", arguments: stringsCases)
    func strings(test: GoldenCase) async throws {
        #expect(try await EpsilonFixtures.run(test.source) == test.expected)
    }

    static let collectionsCases: [GoldenCase] = [
        GoldenCase("mutation is visible through aliases", "var a = Sequence{}; var b = a; b.add(1); a.println();", "Sequence {1}\n"),
        GoldenCase("including and excluding copy", "var a = Sequence{1}; var b = a.including(2); a.size().println(); b.excluding(1).println();", "1\nSequence {2}\n"),
        GoldenCase("aggregates", "Sequence{1, 2, 3}.sum().println(); Sequence{2, 5, 1}.max().println(); Sequence{2, 5, 1}.min().println();", "6\n5\n1\n"),
        GoldenCase("positions", "var s = Sequence{'a', 'b', 'c'}; s.first().println(); s.last().println(); s.at(1).println(); s.indexOf('c').println(); s.invert().println();", "a\nc\nb\n2\nSequence {c, b, a}\n"),
        GoldenCase("membership", "Sequence{1, 2}.includes(2).println(); Sequence{1, 2}.excludesAll(Sequence{3}).println(); Sequence{1, 1, 2}.count(1).println();", "true\ntrue\n2\n"),
        GoldenCase("concat and flatten", "Sequence{1, 2, 3}.concat(', ').println(); Sequence{Sequence{1}, Sequence{2, Sequence{3}}}.flatten().println();", "1, 2, 3\nSequence {1, 2, 3}\n"),
        GoldenCase("select reject collect", "var s = Sequence{1..6}; s.select(x | x > 3).println(); s.reject(x | x > 3).println(); s.collect(x | x * x).println();", "Sequence {4, 5, 6}\nSequence {1, 2, 3}\nSequence {1, 4, 9, 16, 25, 36}\n"),
        GoldenCase("quantifiers", "var s = Sequence{1..5}; s.exists(x | x = 3).println(); s.forAll(x | x > 0).println(); s.one(x | x > 4).println(); s.none(x | x > 9).println();", "true\ntrue\ntrue\ntrue\n"),
        GoldenCase("selectOne and count", "Sequence{1..9}.selectOne(x | x > 4).println(); Sequence{1..9}.count(x | x.mod(2) = 0).println(); Sequence{1..9}.nMatch(x | x > 7, 2).println();", "5\n4\ntrue\n"),
        GoldenCase("sortBy keeps ties in order", "Sequence{'pear', 'fig', 'apple', 'kiwi'}.sortBy(s | s.length()).println();", "Sequence {fig, pear, kiwi, apple}\n"),
        GoldenCase("mapBy groups", "Sequence{'ant', 'bee', 'cat', 'ape'}.mapBy(s | s.characterAt(0)).println();", "Map {a=Sequence {ant, ape}, b=Sequence {bee}, c=Sequence {cat}}\n"),
        GoldenCase("aggregate with total", "Sequence{'ant', 'bee', 'ape'}.aggregate(s | s.characterAt(0), total + 1, 0).println();", "Map {a=2, b=1}\n"),
        GoldenCase("closure", "var m = Map{1 = Sequence{2, 3}, 2 = Sequence{4}, 3 = Sequence{}, 4 = Sequence{}}; Sequence{1}.closure(n | m.get(n)).println();", "OrderedSet {2, 3, 4}\n"),
        GoldenCase("typed iterator filters", "Sequence{1, 'a', 2}.select(x : Integer | true).println();", "Sequence {1, 2}\n"),
        GoldenCase("parallel variants run sequentially", "Sequence{1, 2}.parallelCollect(x | x + 1).println();", "Sequence {2, 3}\n"),
        GoldenCase("selectByKind", "Sequence{1, 'a', 2.5}.selectByKind(Real).println();", "Sequence {1, 2.5}\n"),
        GoldenCase("map operations", "var m = new Map; m.put('k', 1); m.containsKey('k').println(); m.keySet().println(); m.values().println(); m.remove('k'); m.isEmpty().println();", "true\nSet {k}\nBag {1}\ntrue\n"),
    ]

    @Test("Collection and map operations", arguments: collectionsCases)
    func collections(test: GoldenCase) async throws {
        #expect(try await EpsilonFixtures.run(test.source) == test.expected)
    }

    static let statementsCases: [GoldenCase] = [
        GoldenCase("if else chains", "var x = 5; if (x > 10) 'big'.println(); else if (x > 3) { 'medium'.println(); } else 'small'.println();", "medium\n"),
        GoldenCase("while with loopCount", "var i = 0; while (i < 3) { i = i + 1; loopCount.print(); } ''.println();", "123\n"),
        GoldenCase("for with hasMore", "for (x in Sequence{'a', 'b', 'c'}) { x.print(); if (hasMore) ','.print(); } ''.println();", "a,b,c\n"),
        GoldenCase("break and continue", "for (i in Sequence{1..10}) { if (i = 2) continue; if (i = 5) break; i.print(); } ''.println();", "134\n"),
        GoldenCase("breakAll leaves nested loops", "for (i in Sequence{1..3}) { for (j in Sequence{1..3}) { if (j = 2) breakAll; (i + '' + j).print(); } } ''.println();", "11\n"),
        GoldenCase("switch without fall-through", "switch (2) { case 1: 'one'.println(); case 2: 'two'.println(); case 3: 'three'.println(); default: 'other'.println(); }", "two\n"),
        GoldenCase("switch with continue falls through", "switch ('a') { case 'a': 'A'.println(); continue; case 'b': 'B'.println(); default: 'D'.println(); }", "A\nB\n"),
        GoldenCase("switch default", "switch (9) { case 1: 'one'.println(); default: 'other'.println(); }", "other\n"),
        GoldenCase("compound assignment and increment", "var i = 1; i += 4; i *= 2; i -= 1; i++; i.println(); var s = 'a'; s += 'b'; s.println();", "10\nab\n"),
        GoldenCase("assign if undefined", "var a; a ?= 1; a ?= 2; a.println();", "1\n"),
        GoldenCase("typed declarations get default values", "var i : Integer; var s : String; var q : Sequence; var b : Boolean; (i + '|' + s + '|' + q.size() + '|' + b).println();", "0||0|false\n"),
        GoldenCase("integers widen to reals", "var r : Real = 2; r.println();", "2.0\n"),
        GoldenCase("nested scopes shadow", "var x = 1; { var x = 2; x.println(); } x.println();", "2\n1\n"),
        GoldenCase("extended properties", "var s = Sequence{}; s.~tag = 'hello'; s.~tag.println(); s.~missing.isDefined().println();", "hello\nfalse\n"),
        GoldenCase("top-level return", "'a'.println(); return; 'b'.println();", "a\n"),
    ]

    @Test("Statements and control flow", arguments: statementsCases)
    func statements(test: GoldenCase) async throws {
        #expect(try await EpsilonFixtures.run(test.source) == test.expected)
    }

    static let operationsCases: [GoldenCase] = [
        GoldenCase("context and parameters", "operation Integer add(n : Integer) : Integer { return self + n; } 3.add(4).println();", "7\n"),
        GoldenCase("context-free operation", "operation greet(name : String) { ('Hi ' + name).println(); } greet('Ann');", "Hi Ann\n"),
        GoldenCase("recursion", "operation Integer fact() : Integer { if (self <= 1) return 1; return self * (self - 1).fact(); } 10.fact().println();", "3628800\n"),
        GoldenCase("exact type wins over declaration order", "operation Real kind() { return 'real'; } operation Integer kind() { return 'integer'; } 1.kind().println(); 1.5.kind().println();", "integer\nreal\n"),
        GoldenCase("first kind-of match in declaration order", "operation Any describe() { return 'any'; } operation Collection describe() { return 'collection'; } Sequence{}.describe().println();", "any\n"),
        GoldenCase("arrow prefers built-ins", "operation String size() { return 99; } 'abc'.size().println(); 'abc'->size().println();", "99\n3\n"),
        GoldenCase("pre and post conditions hold", "$pre n > 0\n$post _result > n\noperation inc(n : Integer) : Integer { return n + 1; } inc(1).println();", "2\n"),
    ]

    @Test("Operations and dispatch", arguments: operationsCases)
    func operations(test: GoldenCase) async throws {
        #expect(try await EpsilonFixtures.run(test.source) == test.expected)
    }

    @Test("Operations do not see the caller's local variables")
    func operationFrames() async {
        let error = await EpsilonFixtures.failure("operation probe() { return x; } var x = 1; probe();")
        #expect(error?.code == EOLDiagnosticCode.unresolvedName.rawValue)
    }

    @Test("@cached operations run their body once per receiver")
    func cached() async throws {
        let output = try await EpsilonFixtures.run(
            """
            @cached
            operation Integer slow() : Integer { 'computing'.println(); return self * 2; }
            2.slow().println(); 2.slow().println(); 3.slow().println();
            """)
        #expect(output == "computing\n4\n4\ncomputing\n6\n")
    }

    @Test("A violated precondition is reported at the annotation")
    func preconditionViolation() async {
        let error = await EpsilonFixtures.failure("$pre n > 0\noperation inc(n : Integer) : Integer { return n + 1; }\ninc(0);")
        #expect(error?.code == EOLDiagnosticCode.contractViolation.rawValue)
        #expect(error?.range?.start.line == 1)
    }

    @Test("Return values are checked against the declared type")
    func returnTypeChecked() async {
        let error = await EpsilonFixtures.failure("operation f() : Integer { return 'x'; } f();")
        #expect(error?.code == EOLDiagnosticCode.typeMismatch.rawValue)
    }

    @Test("Imported operations are available, and importing modules override them")
    func imports() async throws {
        let loader = EOLInMemoryModuleLoader([
            "util.eol": "operation Integer double() : Integer { return self * 2; } operation hello() { return 'imported'; }",
            "base.eol": "import 'util.eol'; operation triple(n : Integer) : Integer { return n * 3; }",
        ])
        let output = try await EpsilonFixtures.run(
            "import 'base.eol'; operation hello() { return 'local'; } 4.double().println(); triple(2).println(); hello().println();",
            loader: loader)
        #expect(output == "8\n6\nlocal\n")
    }

    @Test("A missing import is reported at the import declaration")
    func missingImport() async {
        do {
            _ = try await EpsilonFixtures.run("var a = 1;\nimport 'nowhere.eol';")
            Issue.record("expected an import error")
        } catch let error as EOLError {
            #expect(error.code == EOLDiagnosticCode.importFailed.rawValue)
            #expect(error.range?.start.line == 2)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    static let failures: [(String, EOLDiagnosticCode, Int, Int)] = [
        ("var x = 1;\nx.foo();", .unknownOperation, 2, 1),
        ("var s = 'a';\nvar n = s / 2;", .typeMismatch, 2, 9),
        ("var n = null;\nn.size();", .undefinedReceiver, 2, 1),
        ("unknown.println();", .unresolvedName, 1, 1),
        ("var x = 1 / 0;", .arithmetic, 1, 9),
        ("Sequence{1}.at(5);", .indexOutOfBounds, 1, 1),
        ("throw 'custom problem';", .userError, 1, 1),
        ("if (1) { }", .typeMismatch, 1, 5),
        ("var a = 1; var a = 2;", .invalidDeclaration, 1, 12),
    ]

    @Test("Run-time errors carry codes and positions", arguments: 0..<failures.count)
    func runtimeErrors(index: Int) async {
        let (source, code, line, column) = Self.failures[index]
        let error = await EpsilonFixtures.failure(source)
        #expect(error?.code == code.rawValue, "\(source): \(String(describing: error))")
        #expect(error?.range?.start.line == line, "\(source)")
        #expect(error?.range?.start.column == column, "\(source)")
    }

    @Test("A thrown value becomes the message")
    func thrownMessage() async {
        let error = await EpsilonFixtures.failure("throw 'custom ' + 42;")
        #expect(error?.message == "custom 42")
    }
}

@Suite("EOL cancellation")
struct EOLCancellationTests {
    @Test("An endless loop stops when its task is cancelled")
    func cancellation() async throws {
        let task = Task { try await EpsilonFixtures.run("var i = 0; while (true) { i = i + 1; }") }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch let error as EOLError {
            #expect(error.code == EOLDiagnosticCode.cancelled.rawValue)
        }
    }
}
