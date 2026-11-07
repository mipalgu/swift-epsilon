//
//  EOLBuiltinTests.swift
//  EOLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import EpsilonTestSupport
import Foundation
import Testing

@testable import EOL

@Suite("EOL built-in operations")
struct EOLBuiltinTests {
    static let numberCases: [GoldenCase] = [
        GoldenCase("abs", "(-3).abs().println(); (-2.5).abs().println();", "3\n2.5\n"),
        GoldenCase("rounding", "2.5.round().println(); 2.1.ceiling().println(); 4.floor().println(); 7.ceiling().println(); 7.round().println();", "3\n3\n4\n7\n7\n"),
        GoldenCase("powers and logarithms", "2.pow(10).println(); 16.sqrt().println(); 100.log10().println(); 1.log().println();", "1024.0\n4.0\n2.0\n0.0\n"),
        GoldenCase("max and min", "3.max(5).println(); 3.min(5).println(); 2.5.max(1).println(); 1.min(0.5).println();", "5\n3\n2.5\n0.5\n"),
        GoldenCase("modulo", "17.mod(5).println(); 7.5.mod(2).println();", "2\n1.5\n"),
        GoldenCase("ranges", "3.to(1).println(); 1.iota(7, 3).println();", "Sequence {3, 2, 1}\nSequence {1, 4, 7}\n"),
        GoldenCase("radix", "10.toBinary().println(); 255.toHex().println();", "1010\nff\n"),
        GoldenCase("conversions", "2.7.asInteger().println(); 3.asReal().println(); 3.asDouble().println();", "2\n3.0\n3.0\n"),
        GoldenCase("special reals", "(0.0 / 0.0).println(); (1.0 / 0).println(); (-1.0 / 0).println(); (-1.5E12).println(); 0.0.println();", "NaN\nInfinity\n-Infinity\n-1.5E12\n0.0\n"),
        GoldenCase("real comparisons", "(1.5 < 2).println(); (2 >= 2.0).println(); (3 <= 2).println(); (2 > 1).println();", "true\ntrue\nfalse\ntrue\n"),
        GoldenCase("negation", "(-(2.5)).println(); (-(3)).println();", "-2.5\n-3\n"),
        GoldenCase("real arithmetic", "(5.0 - 1).println(); (2 * 1.5).println(); (1.0 / 4).println();", "4.0\n3.0\n0.25\n"),
    ]

    @Test("Number operations", arguments: numberCases)
    func numbers(test: GoldenCase) async throws {
        #expect(try await EpsilonFixtures.run(test.source) == test.expected)
    }

    static let stringCases: [GoldenCase] = [
        GoldenCase("predicates", "'Abc'.equalsIgnoreCase('aBC').println(); '42'.isInteger().println(); '4.2'.isReal().println(); ''.isEmpty().println(); 'abc'.contains('b').println();", "true\ntrue\ntrue\ntrue\ntrue\n"),
        GoldenCase("affixes", "'library'.startsWith('lib').println(); 'library'.endsWith('ary').println(); 'ab'.concat('cd').println();", "true\ntrue\nabcd\n"),
        GoldenCase("conversions", "'TRUE'.asBoolean().println(); '2.5'.asDouble().println(); 'ab'.toCharSequence().println(); 'abc'.size().println();", "true\n2.5\nSequence {a, b}\n3\n"),
        GoldenCase("xml escaping", "'<a href=\"x\">&\\'</a>'.escapeXml().println();", "&lt;a href=&quot;x&quot;&gt;&amp;&apos;&lt;/a&gt;\n"),
        GoldenCase("left padding", "'7'.pad(3, '0', false).println();", "007\n"),
        GoldenCase("missing substrings", "'abc'.indexOf('z').println(); 'abc'.lastIndexOf('').println(); 'ab'.indexOf('abc').println();", "-1\n3\n-1\n"),
        GoldenCase("regular expression groups", "'2026-11-07'.replaceAll('(\\\\d+)-(\\\\d+)-(\\\\d+)', '$3/$2/$1').println(); 'a.b'.replace('\\\\.', '\\\\$').println();", "07/11/2026\na$b\n"),
        GoldenCase("split edge cases", "'a,,b,,'.split(',').println(); ''.split(',').size().println(); 'abc'.split('').println();", "Sequence {a, , b}\n1\nSequence {a, b, c}\n"),
        GoldenCase("character items", "'xyz'[1].println(); 'xyz'.charAt(2).println(); 'Hello'.firstToLowerCase().println(); ''.firstToUpperCase().length().println();", "y\nz\nhello\n0\n"),
    ]

    @Test("String operations", arguments: stringCases)
    func strings(test: GoldenCase) async throws {
        #expect(try await EpsilonFixtures.run(test.source) == test.expected)
    }

    static let collectionCases: [GoldenCase] = [
        GoldenCase("ordinal access", "var s = Sequence{1, 2, 3, 4}; s.second().println(); s.third().println(); s.fourth().println(); Sequence{}.second().println(); Sequence{}.last().println();", "2\n3\n4\nnull\nnull\n"),
        GoldenCase("removal", "var s = Sequence{1, 2, 1, 3}; s.removeAt(0).println(); s.removeAll(Sequence{1}); s.println(); s.remove(9).println(); s.clear(); s.isEmpty().println();", "1\nSequence {2, 3}\nfalse\ntrue\n"),
        GoldenCase("bulk operations", "var s = Set{1}; s.addAll(Sequence{1, 2}).println(); s.includingAll(Sequence{3}).println(); s.excludingAll(Sequence{1}).println(); s.includesAll(Sequence{1, 2}).println();", "true\nSet {1, 2, 3}\nSet {2}\ntrue\n"),
        GoldenCase("products and defaults", "Sequence{2, 3, 4}.product().println(); Sequence{}.max(0).println(); Sequence{}.sum().println(); Sequence{'b', 'a'}.max().println();", "24\n0\n0\nb\n"),
        GoldenCase("sorting", "Sequence{3, 1, 2}.sort().println(); Bag{'b', 'a'}.sort().println();", "Sequence {1, 2, 3}\nBag {a, b}\n"),
        GoldenCase("random picks a member", "var s = Sequence{1, 2, 3}; s.includes(s.random()).println(); Sequence{}.random().println();", "true\nnull\n"),
        GoldenCase("rejectOne", "Sequence{1, 2, 3, 2}.rejectOne(x | x = 2).println(); Sequence{1}.rejectOne(x | x = 5).println(); Sequence{1}.selectOne(x | x = 5).println();", "Sequence {1, 3, 2}\nSequence {1}\nnull\n"),
        GoldenCase("match counts", "var s = Sequence{1..5}; s.atLeastNMatch(x | x > 2, 3).println(); s.atMostNMatch(x | x > 2, 2).println(); s.forAll(x | x < 3).println(); s.exists(x | x > 7).println(); s.none(x | x = 3).println();", "true\nfalse\nfalse\nfalse\nfalse\n"),
        GoldenCase("unordered collect gives a bag", "Set{1, 2}.collect(x | x * 0).println(); Sequence{1}.reverse().println();", "Bag {0, 0}\nSequence {1}\n"),
        GoldenCase("first-order operations on maps and single values", "Map{'a' = 1}.select(k | k = 'a').println(); 5.collect(x | x + 1).println();", "Sequence {a}\nSequence {6}\n"),
        GoldenCase("conversions between kinds", "Sequence{1, 1}.asSet().println(); Set{1}.asSequence().println(); Sequence{2, 1, 2}.asOrderedSet().println(); 7.asBag().println(); Map{'k' = 'v'}.asSequence().println(); null.asSequence().size().println();", "Set {1}\nSequence {1}\nOrderedSet {2, 1}\nBag {7}\nSequence {v}\n0\n"),
        GoldenCase("equality of collections", "(Sequence{1, 2} = Sequence{1, 2}).println(); (Set{1, 2} = Set{2, 1}).println(); (Sequence{1} = Set{1}).println(); (Map{1 = 2} = Map{1 = 2}).println(); (Bag{1, 1} = Bag{1, 2}).println();", "true\ntrue\nfalse\ntrue\nfalse\n"),
        GoldenCase("map operations", "var m = Map{'a' = 1}; m.putAll(Map{'b' = 2}); m.containsValue(2).println(); m.notEmpty().println(); m.get('z').println(); m.remove('z').println(); m.clear(); m.size().println(); m['q'] = 5; m.println();", "true\ntrue\nnull\nnull\n0\nMap {q=5}\n"),
        GoldenCase("clone is independent", "var a = Sequence{1}; var b = a.clone(); b.add(2); a.println();", "Sequence {1}\n"),
        GoldenCase("printing variants", "1.print(); 2.print('>'); ''.println(); 3.println('n='); null.println();", "1>2\nn=3\nnull\n"),
        GoldenCase("ifUndefined and type of undefined", "null.ifUndefined('d').println(); 4.ifUndefined('d').println(); null.isUndefined().println(); null.type().name.println();", "d\n4\ntrue\nAny\n"),
        GoldenCase("types", "Sequence{}.type().name.println(); Map{}.type().name.println(); true.type().name.println(); 1.5.type().name.println(); Sequence{}.isTypeOf(Sequence).println(); Sequence{}.isTypeOf(Collection).println(); 'a'.isKindOf(Any).println(); 'a'.isTypeOf(Any).println(); 1.instanceOf(Integer).println();", "Sequence\nMap\nBoolean\nReal\ntrue\nfalse\ntrue\nfalse\ntrue\n"),
        GoldenCase("instantiation of built-in types", "(new String).length().println(); (new Integer).println(); (new Real).println(); (new Boolean).println(); (new Bag).println(); (new OrderedSet).println();", "0\n0\n0.0\nfalse\nBag {}\nOrderedSet {}\n"),
        GoldenCase("typed declarations of other kinds", "var r : Real; var m : Map; var o : OrderedSet; var x : Any; r.println(); m.println(); o.println(); x.println();", "0.0\nMap {}\nOrderedSet {}\nnull\n"),
        GoldenCase("logical operators on more cases", "(false and true).println(); (true or false).println(); (true implies false).println(); (false xor true).println();", "false\ntrue\nfalse\ntrue\n"),
    ]

    @Test("Collection, map and general operations", arguments: collectionCases)
    func collections(test: GoldenCase) async throws {
        #expect(try await EpsilonFixtures.run(test.source) == test.expected)
    }

    static let errorCases: [(String, EOLDiagnosticCode)] = [
        ("'a'.substring(2, 1);", .indexOutOfBounds),
        ("'a'.characterAt(3);", .indexOutOfBounds),
        ("'x'.asInteger();", .typeMismatch),
        ("'x'.asReal();", .typeMismatch),
        ("'a'.startsWith(1);", .typeMismatch),
        ("'a'.substring('b');", .typeMismatch),
        ("'a'.pad(3, '*', 1);", .typeMismatch),
        ("'a'.matches('(');", .typeMismatch),
        ("2.pow('x');", .typeMismatch),
        ("2.max('x');", .typeMismatch),
        ("2.mod(0);", .arithmetic),
        ("2.iota(5, 0);", .typeMismatch),
        ("Sequence{1}.removeAt(4);", .indexOutOfBounds),
        ("Sequence{1}.at('x');", .typeMismatch),
        ("Sequence{1, 'a'}.max();", .typeMismatch),
        ("Sequence{1, 'a'}.sortBy(x | x);", .typeMismatch),
        ("Sequence{1}.select(x | 1);", .typeMismatch),
        ("Sequence{1}.nMatch(x | true, 'n');", .typeMismatch),
        ("Sequence{1}.selectByKind(1);", .typeMismatch),
        ("Sequence{1}.frobnicate(x | true);", .unknownOperation),
        ("Map{}.putAll(1);", .typeMismatch),
        ("1.isKindOf(2);", .typeMismatch),
        ("'a'[0.5];", .typeMismatch),
        ("'a'[5];", .indexOutOfBounds),
        ("Sequence{1}[3];", .indexOutOfBounds),
        ("Sequence{1}['a'];", .typeMismatch),
        ("true[0];", .typeMismatch),
        ("var s = Sequence{1}; s[5] = 2;", .indexOutOfBounds),
        ("var b = true; b[0] = 1;", .typeMismatch),
        ("var n = null; n.x = 1;", .undefinedReceiver),
        ("var n = 1; n.x = 1;", .unknownProperty),
        ("1.foo;", .unknownProperty),
        ("null.foo;", .undefinedReceiver),
        ("var x = - 'a';", .typeMismatch),
        ("var x = not 1;", .typeMismatch),
        ("var x = 1 < 'a';", .typeMismatch),
        ("var x = true + 1;", .typeMismatch),
        ("var x = 9223372036854775807 + 1;", .arithmetic),
        ("var x = Sequence{'a'..2};", .typeMismatch),
        ("var x = new Sequence(1);", .unsupportedConstruct),
        ("var x = Set{1}; x.foo();", .unknownOperation),
        ("foo();", .unknownOperation),
        ("undefinedVariable = 1;", .unresolvedName),
        ("var x : Integer = 'a';", .typeMismatch),
        ("var x = #nothing;", .unresolvedName),
        ("var x = String#a;", .unresolvedType),
        ("null.foo();", .undefinedReceiver),
        ("operation f() { return f(); } f();", .arithmetic),
        ("$post _result > 5\noperation g() : Integer { return 1; } g();", .contractViolation),
        ("Sequence{1}.select(x | x).println();", .typeMismatch),
        ("var t = Integer; t.all.println();", .typeMismatch),
        ("var t = Integer; t.colour.println();", .unknownProperty),
        ("var x = 1 and true;", .typeMismatch),
    ]

    @Test("Built-in operations report errors", arguments: 0..<errorCases.count)
    func errors(index: Int) async {
        let (source, code) = Self.errorCases[index]
        let error = await EpsilonFixtures.failure(source)
        #expect(error?.code == code.rawValue, "\(source): \(String(describing: error))")
    }

    @Test("Error output goes to the error stream")
    func errorStream() async throws {
        let module = try EOLSyntax.parse("'out'.println(); 'bad'.errln(); 'x'.err('!');").get()
        let output = EOLStringOutput()
        let errors = EOLStringOutput()
        try await EOLInterpreter(output: output, errorOutput: errors).run(module)
        #expect(output.text == "out\n")
        #expect(errors.text == "bad\n!x")
    }

    @Test("A top-level return yields a value to the caller")
    func returnValue() async throws {
        let module = try EOLSyntax.parse("return Sequence{1, 2}.size() + 1;").get()
        let value = try await EOLInterpreter(output: EOLStringOutput()).run(module)
        #expect(value == .integer(3))
        #expect(value.integerValue == 3)
        #expect(value.realValue == 3.0)
        #expect(value.stringValue == nil)
        #expect(value.booleanValue == nil)
        #expect(value.collectionValue == nil)
        #expect(value.mapValue == nil)
        #expect(value.elementValue == nil)
        #expect(value.typeValue == nil)
        #expect(value.description == "3")
    }

    @Test("Integers have 64 bits on every platform")
    func sixtyFourBitIntegers() async throws {
        let module = try EOLSyntax.parse("return 9223372036854775806 + 1 - 4294967296 * 2;").get()
        let value = try await EOLInterpreter(output: EOLStringOutput()).run(module)
        let expected: Int64 = .max - 8_589_934_592
        #expect(value == .integer(expected))
        #expect(value.integerValue == expected)
    }

    @Test("Template output outside a template is reported")
    func templateOutsideTemplate() async throws {
        let interpreter = EOLInterpreter(output: EOLStringOutput())
        let statement = EOLStatement(.templateText("x"), range: EOLBuiltinName.noRange)
        await #expect(throws: EOLError.self) { try await interpreter.execute([statement]) }
    }
}

@Suite("EOL values, types and support")
struct EOLValueTests {
    @Test("Collections keep uniqueness, order and identity")
    func collection() {
        let set = EOLCollection(.orderedSet, [.integer(1), .integer(2)])
        #expect(!set.append(.integer(1)))
        #expect(set.insert(.integer(0), at: 0))
        #expect(!set.insert(.integer(2), at: 9))
        set.replace(at: 0, with: .integer(5))
        #expect(set.elements == [.integer(5), .integer(1), .integer(2)])
        #expect(set.contains(.integer(5)))
        #expect(!set.contains(.integer(0)))
        let copy = set.copy(as: .sequence)
        #expect(copy.kind == .sequence)
        #expect(copy != set)
        #expect(EOLCollection(.bag, [.integer(1)]) != EOLCollection(.set, [.integer(1)]))
        #expect(EOLCollection(.bag, [.integer(1), .integer(2)]) == EOLCollection(.bag, [.integer(2), .integer(1)]))
        var hasher = Hasher()
        set.hash(into: &hasher)
        #expect(EOLCollectionKind(ordered: false, unique: false) == .bag)
        #expect(EOLCollectionKind(ordered: false, unique: true) == .set)
        #expect(EOLValue.collection(set).asElements.count == 3)
        #expect(EOLValue.undefined.asElements.isEmpty)
        #expect(EOLValue.integer(1).asElements == [.integer(1)])
    }

    @Test("Maps keep insertion order and compare by contents")
    func map() {
        let map = EOLMap()
        map.put(.string("a"), .integer(1))
        map.put(.string("b"), .integer(2))
        map.put(.string("a"), .integer(3))
        #expect(map.keys == [.string("a"), .string("b")])
        #expect(map.values == [.integer(3), .integer(2)])
        let other = EOLMap()
        other.put(.string("b"), .integer(2))
        #expect(map != other)
        other.put(.string("a"), .integer(3))
        #expect(map == other)
        #expect(EOLValue.map(map) == .map(other))
        #expect(EOLValue.map(map).description == "Map {a=3, b=2}")
        #expect(EOLValue.map(map).mapValue === map)
    }

    @Test("Values compare across numeric kinds and with enumeration literals")
    func equality() {
        let literal = EOLEnumerationLiteral(enumeration: "Genre", name: "fiction", value: 0)
        #expect(EOLValue.enumerationLiteral(literal) == .string("fiction"))
        #expect(EOLValue.string("fiction") == .enumerationLiteral(literal))
        #expect(EOLValue.integer(2) == .real(2))
        #expect(EOLValue.boolean(true) != .integer(1))
        #expect(Set<EOLValue>([.integer(1), .real(1)]).count == 1)
        #expect(EOLValue.type(.string) == .type(.string))
        #expect(EOLValue.boolean(false).description == "false")
        #expect(EOLValue.enumerationLiteral(literal).description == "fiction")
        #expect(EOLValue.type(.collection(nil)).description == "Collection")
        #expect(EOLValue.real(2.5).realValue == 2.5)
    }

    @Test("Built-in type names resolve, including aliases")
    func builtinTypes() {
        let names = ["Any", "String", "Integer", "Long", "Real", "Double", "Float", "Boolean", "Collection", "Sequence", "List", "Set", "OrderedSet", "Bag", "Map"]
        let types = names.compactMap(EOLType.builtin(named:))
        #expect(types.count == names.count)
        #expect(types.map(\.name) == ["Any", "String", "Integer", "Integer", "Real", "Real", "Real", "Boolean", "Collection", "Sequence", "Sequence", "Set", "OrderedSet", "Bag", "Map"])
        #expect(EOLType.builtin(named: "Native") == nil)
        #expect(EOLType.real.description == "Real")
    }

    @Test("Type references describe themselves as written")
    func typeReferenceDescription() throws {
        guard case .type(let reference) = try EOLSyntax.parseExpression("Map(String, Sequence(Integer))").kind else {
            Issue.record("expected a type")
            return
        }
        #expect(reference.description == "Map(String, Sequence(Integer))")
        #expect(throws: EOLError.self) { try EOLSyntax.parseExpression("1 +") }
        #expect(throws: EOLError.self) { try EOLSyntax.parseExpression("1 2") }
        #expect(throws: EOLError.self) { try EOLSyntax.parseExpression("'open") }
    }

    @Test("Errors describe their location")
    func errorDescription() {
        let range = SourceRange(start: SourcePosition(utf8Offset: 0, line: 2, column: 3), end: SourcePosition(utf8Offset: 1, line: 2, column: 4))
        #expect(EOLError(.userError, "boom").description == "boom")
        #expect(EOLError(.userError, "boom", range: range).description == "2:3: boom")
        #expect(EOLError(.userError, "boom", range: range, document: "a.eol").errorDescription == "a.eol:2:3: boom")
    }

    @Test("File imports resolve relative to the importing document")
    func fileImports() throws {
        let base = EpsilonFixtures.url("Library.ecore")
        let loader = EOLFileModuleLoader()
        let resolved = EOLFileModuleLoader.resolve("Tree.ecore", relativeTo: base.absoluteString)
        #expect(resolved.lastPathComponent == "Tree.ecore")
        #expect(EOLFileModuleLoader.resolve("x.eol", relativeTo: base.path).lastPathComponent == "x.eol")
        #expect(EOLFileModuleLoader.resolve("/a/b.eol", relativeTo: nil).path == "/a/b.eol")
        #expect(EOLFileModuleLoader.resolve("file:///a/c.eol", relativeTo: nil).path == "/a/c.eol")
        #expect(EOLFileModuleLoader.resolve("d.eol", relativeTo: nil).lastPathComponent == "d.eol")
        let loaded = try loader.load("Tree.ecore", relativeTo: base.absoluteString)
        #expect(loaded.text.contains("EPackage"))
        #expect(throws: (any Error).self) { try loader.load("missing.eol", relativeTo: base.absoluteString) }
    }

    @Test("Models resolve qualified classifiers and compare metamodels")
    func models() async throws {
        let resourceSet = ResourceSet()
        let library = try await EpsilonFixtures.library(in: resourceSet)
        let tree = try await EpsilonFixtures.tree(in: resourceSet)
        #expect(library.classifier(named: "library::Book")?.name == "Book")
        #expect(library.classifier(named: "nowhere::Book") == nil)
        #expect(library.classifier(named: "Shelf") == nil)
        #expect(library.sharesMetamodel(with: library))
        #expect(!library.sharesMetamodel(with: tree))
        #expect(library.description == "Library")
        #expect(library != tree)
        let alias = EOLModel(name: "L", resource: library.resource, packages: library.packages, aliases: ["Lib"])
        #expect(alias.answers(to: "Lib"))
        let output = try await EpsilonFixtures.run(
            """
            Lib!Book.all.size().println();
            L.allContents().size().println();
            L.getAllOfKind('Publication').size().println();
            L.getAllOfType('Book').size().println();
            L.owns(Lib!Book.all.first()).println();
            var m = L.createInstance('Magazine');
            m.owningModel().name.println();
            Lib!Book.all.first().owningModel().allContents().size().println();
            Lib!Magazine.createInstance().isKindOf(Lib!Publication).println();
            Lib!Book.isInstantiable().println();
            Lib!Publication.isInstantiable().println();
            Integer.isInstantiable().println();
            Lib!Book.allOfKind().size().println();
            Lib!Book.name.println();
            Lib!Genre.name.println();
            """, models: [alias])
        #expect(output == "3\n8\n4\n3\ntrue\nL\n9\ntrue\ntrue\nfalse\ntrue\n3\nBook\nGenre\n")
        let failure = await EpsilonFixtures.failure("L.createInstance('Shelf');", models: [alias])
        #expect(failure?.code == EOLDiagnosticCode.unresolvedType.rawValue)
    }

    @Test("Model elements expose reflective operations and extended properties")
    func reflection() async throws {
        let output = try await EpsilonFixtures.run(
            """
            var lib = Library.all.first();
            lib.eAllContents().size().println();
            lib.eContents().size().println();
            lib.eClass().name.println();
            lib.eContainer().isDefined().println();
            lib.eClass.name.println();
            lib.~visited = true;
            lib.~visited.println();
            Book.all.first().hasProperty('colour').println();
            1.hasProperty('x').println();
            1.owningModel().println();
            Book.all.first().type().println();
            Book.all.first().genre.type().name.println();
            Library!Genre#science.isKindOf(Library!Genre).println();
            Book.all.collect(b | b.genre).asSet().size().println();
            """, models: [try await EpsilonFixtures.library()])
        #expect(output == "7\n7\nLibrary\nfalse\nLibrary\ntrue\nfalse\nfalse\nnull\nBook\nGenre\ntrue\n2\n")
    }

    @Test("Enumeration literals are checked")
    func enumerationErrors() async throws {
        let library = try await EpsilonFixtures.library()
        for (source, code) in [
            ("Library!Genre#romance.println();", EOLDiagnosticCode.unresolvedName),
            ("Library!Book#fiction.println();", .unresolvedType),
            ("Book.all.first().genre = 7;", .typeMismatch),
            ("Book.all.first().keywords = Sequence{1};", .typeMismatch),
            ("Book.all.first().authors = Sequence{1};", .typeMismatch),
            ("Library.all.first().authors.first().books = Sequence{Book.all.first(), Book.all.last()}; Book.all.first().authors.size().println();", nil),
        ] {
            let error = await EpsilonFixtures.failure(source, models: [library])
            #expect(error?.code == code?.rawValue, "\(source): \(String(describing: error))")
        }
    }

    @Test("Attributes of all data types are written and read back")
    func attributeKinds() async throws {
        let output = try await EpsilonFixtures.run(
            """
            var b = Book.all.first();
            b.genre = 1;
            b.genre.println();
            b.genre = 'history';
            b.genre.println();
            b.keywords = Sequence{'x', 'y'};
            b.keywords.println();
            b.keywords.add('z');
            b.keywords.size().println();
            b.available = false;
            b.available.println();
            b.title = null;
            b.title.isDefined().println();
            b.authors = null;
            b.authors.size().println();
            b.authors.add(Author.all.first());
            b.authors.remove(Author.all.first());
            b.authors.size().println();
            """, models: [try await EpsilonFixtures.library()])
        #expect(output == "science\nhistory\nOrderedSet {x, y}\n3\nfalse\nfalse\n0\n0\n")
    }
}
