//
//  ETLTransformerTests.swift
//  ETLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import EOL
import EpsilonTestSupport
import Testing

@testable import ETL

/// The outcome of running a transformation in a test.
struct TransformationRun {
    /// What the transformation printed.
    let output: String
    /// The target graph model.
    let graph: EOLModel
    /// The transformer, for inspecting its trace.
    let transformer: ETLTransformer
}

/// Transforms the tree fixture into an empty graph model that shares its resource set.
///
/// - Parameter source: The ETL module text.
/// - Returns: The output, target model and transformer.
/// - Throws: ``EOLError`` for parse or run-time errors.
func transformTree(_ source: String) async throws -> TransformationRun {
    let resourceSet = ResourceSet()
    let tree = try await EpsilonFixtures.tree(in: resourceSet)
    let graph = try await EpsilonFixtures.emptyGraph(in: resourceSet)
    let module = try ETLSyntax.parse(source, document: "test.etl").get()
    let output = EOLStringOutput()
    let transformer = ETLTransformer(module: module, models: [tree, graph], output: output, errorOutput: output)
    try await transformer.transform()
    return TransformationRun(output: output.text, graph: graph, transformer: transformer)
}

/// Transforms the tree fixture and returns the error raised, if any.
///
/// - Parameter source: The ETL module text.
/// - Returns: The error, or `nil` if the transformation succeeded.
func transformationFailure(_ source: String) async -> EOLError? {
    do {
        _ = try await transformTree(source)
        return nil
    } catch let error as EOLError {
        return error
    } catch {
        return EOLError(.userError, "\(error)")
    }
}

/// A post block that prints the node names and edges of the target graph.
let graphSummary = """
    post {
        Graph!Node.all.collect(n | n.name).println();
        Graph!Edge.all.collect(e | e.source.name + '->' + e.target.name).println();
    }
    """

@Suite("ETL transformations")
struct ETLTransformerTests {
    /// The tree-to-graph transformation of the Epsilon documentation, rewritten for the test metamodels.
    static let treeToGraph = """
        pre {
            var g = new Graph!Graph;
            g.name = 'G';
        }
        rule Tree2Node
            transform t : Tree!Tree
            to n : Graph!Node {
            n.name = t.label;
            g.nodes.add(n);
            if (t.eContainer().isDefined()) {
                var e = new Graph!Edge;
                e.source ::= t.eContainer();
                e.target = n;
                g.edges.add(e);
            }
        }
        """

    /// The same transformation with a greedy rule.
    static let greedyTreeToGraph = treeToGraph.replacingOccurrences(of: "rule Tree2Node", with: "@greedy\nrule Tree2Node")

    @Test("Rules match exact types by default and resolve containers with ::=")
    func exactMatching() async throws {
        let run = try await transformTree(Self.treeToGraph + graphSummary)
        #expect(run.output == "Sequence {root, a}\nSequence {root->a}\n")
    }

    @Test("A variable declared with ::= is initialised with the equivalent")
    func specialDeclaration() async throws {
        let run = try await transformTree(
            """
            rule Tree2Node transform t : Tree!Tree to n : Graph!Node { n.name = t.label; }
            post {
                var node : Graph!Node ::= Tree!Tree.all.first();
                node.name.println();
                var plain = Tree!Tree.all.first();
                plain.isKindOf(Tree!Tree).println();
            }
            """)
        #expect(run.output == "root\ntrue\n")
    }

    @Test("Greedy rules also match subtypes")
    func greedyMatching() async throws {
        let run = try await transformTree(Self.greedyTreeToGraph + graphSummary)
        #expect(
            run.output == "Sequence {root, a, a1, a2, b}\nSequence {root->a, a->a1, a->a2, root->b}\n")
    }

    @Test("The target model serialises with the transformed content")
    func serialisation() async throws {
        let run = try await transformTree(Self.greedyTreeToGraph)
        var diagnostics = ConversionDiagnostics()
        let text = try await ModelIO.serialise(run.graph.resource, format: .xmi, diagnostics: &diagnostics)
        for label in ["root", "a", "a1", "a2", "b"] { #expect(text.contains("name=\"\(label)\"")) }
        #expect(text.contains("edges"))
        #expect(await run.graph.resource.getRootObjects().count == 1)
    }

    @Test("The trace records each rule application")
    func trace() async throws {
        let run = try await transformTree(Self.greedyTreeToGraph)
        let links = run.transformer.trace.links
        #expect(links.count == 5)
        #expect(links.allSatisfy { $0.rule == "Tree2Node" && $0.targets.count == 1 })
    }

    @Test("Guards written as expressions and as blocks filter matches")
    func guards() async throws {
        let run = try await transformTree(
            """
            @greedy
            rule Labelled transform t : Tree!Tree to n : Graph!Node {
                guard : t.label <> 'b'
                n.name = t.label;
            }
            @greedy
            rule Parents transform t : Tree!Tree to n : Graph!Node {
                guard { return t.children.size() > 0; }
                n.name = 'parent ' + t.label;
            }
            """ + graphSummary)
        #expect(run.output == "Sequence {root, a, a1, a2, parent root, parent a}\nSequence {}\n")
    }

    @Test("Equivalents follow rule order, primary rules first, and can be restricted by rule name")
    func primaryOrdering() async throws {
        let run = try await transformTree(
            """
            @greedy
            rule Tree2Node transform t : Tree!Tree to n : Graph!Node { n.name = t.label; }
            @primary
            rule Leaf2Node transform l : Tree!Leaf to n : Graph!Node { n.name = 'leaf ' + l.label; n.leaf = true; }
            post {
                var leaf = Tree!Leaf.all.first();
                leaf.equivalent().name.println();
                leaf.equivalents().collect(n | n.name).println();
                leaf.equivalent('Tree2Node').name.println();
                Tree!Tree.all.first().equivalent().name.println();
                Tree!Leaf.all.equivalent().size().println();
                Tree!Leaf.all.equivalents().first().size().println();
            }
            """)
        #expect(run.output == "leaf a1\nSequence {leaf a1, a1}\na1\nroot\n3\n2\n")
    }

    @Test("Lazy rules run only when an equivalent is requested, once per element")
    func lazyRules() async throws {
        let run = try await transformTree(
            """
            rule Root transform t : Tree!Tree to n : Graph!Node {
                guard : t.eContainer().isUndefined()
                n.name = t.label;
            }
            @lazy
            rule Label transform t : Tree!Tree to n : Graph!Node {
                n.name = 'lazy ' + t.label;
                ('ran ' + t.label).println();
            }
            post {
                Graph!Node.all.size().println();
                var a = Tree!Tree.all.selectOne(t | t.label = 'a');
                a.equivalent('Label').name.println();
                a.equivalent().name.println();
                Graph!Node.all.size().println();
                Tree!Leaf.all.first().equivalent().isDefined().println();
            }
            """)
        #expect(run.output == "1\nran a\nlazy a\nlazy a\n2\nfalse\n")
    }

    @Test("Bare modifier words are accepted before rule")
    func bareModifiers() async throws {
        let run = try await transformTree(
            """
            rule Root transform t : Tree!Tree to n : Graph!Node { n.name = t.label; }
            lazy rule Later transform t : Tree!Leaf to n : Graph!Node { n.name = 'later'; }
            post { Graph!Node.all.size().println(); }
            """)
        #expect(run.output == "2\n")
        let module = try ETLSyntax.parse("abstract greedy rule R transform t : A to n : B { }").get()
        #expect(module.rules[0].isAbstract)
        #expect(module.rules[0].isGreedy)
    }

    @Test("Extended rules run their bodies first, with parameters bound by position")
    func extends() async throws {
        let run = try await transformTree(
            """
            @abstract
            rule Named transform s : Tree!Tree to x : Graph!Node {
                x.name = 'named';
                ('super ' + s.label).println();
            }
            rule Concrete transform t : Tree!Tree to n : Graph!Node extends Named {
                ('sub ' + t.label + ' ' + n.name).println();
                n.name = n.name + ' ' + t.label;
            }
            """ + graphSummary)
        #expect(
            run.output
                == "super root\nsub root named\nsuper a\nsub a named\nSequence {named root, named a}\nSequence {}\n")
    }

    @Test("Guards of extended rules also apply")
    func superGuards() async throws {
        let run = try await transformTree(
            """
            @abstract
            rule OnlyRoot transform s : Tree!Tree to x : Graph!Node { guard : s.label = 'root' }
            rule Concrete transform t : Tree!Tree to n : Graph!Node extends OnlyRoot { n.name = t.label; }
            """ + graphSummary)
        #expect(run.output == "Sequence {root}\nSequence {}\n")
    }

    @Test("Variables declared in pre blocks are visible to rules and post blocks")
    func preAndPost() async throws {
        let run = try await transformTree(
            """
            pre setup { var count = 0; 'pre'.println(); }
            rule R transform t : Tree!Tree to n : Graph!Node { count = count + 1; n.name = t.label; }
            post report { ('post ' + count).println(); }
            """)
        #expect(run.output == "pre\npost 2\n")
    }

    @Test("A target initialiser supplies an existing element instead of a new one")
    func initialiser() async throws {
        let run = try await transformTree(
            """
            pre { var shared = new Graph!Node; shared.name = 'S'; }
            rule R transform t : Tree!Tree to n : Graph!Node = shared { n.name = n.name + '+' + t.label; }
            post { Graph!Node.all.collect(n | n.name).println(); }
            """)
        #expect(run.output == "Sequence {S+root+a}\n")
    }

    @Test("The special assignment maps collections element by element and keeps values without equivalents")
    func specialAssignmentOfCollections() async throws {
        let run = try await transformTree(
            """
            rule R transform t : Tree!Tree to n : Graph!Node { n.name = t.label; }
            post {
                var g = new Graph!Graph;
                g.nodes ::= Tree!Tree.allOfType();
                g.nodes.collect(n | n.name).println();
                var kept = Sequence{};
                kept ::= Tree!Leaf.all;
                kept.collect(l | l.label).println();
                var text = 'x';
                text ::= 'y';
                text.println();
            }
            """)
        #expect(run.output == "Sequence {root, a}\nSequence {a1, a2, b}\ny\n")
    }

    @Test("Operations declared in the module are available to rules")
    func operations() async throws {
        let run = try await transformTree(
            """
            operation Tree!Tree describe() : String { return self.label.toUpperCase(); }
            rule R transform t : Tree!Tree to n : Graph!Node { n.name = t.describe(); }
            post { Graph!Node.all.collect(n | n.name).println(); }
            """)
        #expect(run.output == "Sequence {ROOT, A}\n")
    }

    @Test("A rule type that cannot be resolved is reported at its type reference")
    func unresolvedType() async {
        let error = await transformationFailure("rule R\n  transform t : Tree!Tree\n  to n : Nowhere!Node { }")
        #expect(error?.code == EOLDiagnosticCode.unresolvedType.rawValue)
        #expect(error?.range?.start.line == 3)
        #expect(error?.range?.start.column == 10)
    }

    @Test("Run-time errors in rule bodies carry positions")
    func bodyError() async {
        let error = await transformationFailure(
            "rule R transform t : Tree!Tree to n : Graph!Node {\n  n.colour = 'red';\n}")
        #expect(error?.code == EOLDiagnosticCode.unknownProperty.rawValue)
        #expect(error?.range?.start.line == 2)
    }

    @Test("Requesting equivalents for an unknown rule fails")
    func unknownRuleName() async {
        let error = await transformationFailure(
            "rule R transform t : Tree!Tree to n : Graph!Node { t.equivalent('Missing'); }")
        #expect(error?.code == EOLDiagnosticCode.unknownDeclaration.rawValue)
    }
}
