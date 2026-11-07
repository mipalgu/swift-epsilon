# Getting Started with ETL

Add the package, parse an ETL module, transform a model and inspect the trace.

## Overview

The ETL module transforms source models into target models with rules written in
the Epsilon Transformation Language. This article shows how to run a
transformation and save its result.

## Add the package

Add swift-epsilon to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-epsilon.git", branch: "main"),
]
```

Then add the `ETL` product, together with `EOL` for loading models, to your
target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "ETL", package: "swift-epsilon"),
        .product(name: "EOL", package: "swift-epsilon"),
    ]
)
```

## Parse a module

``ETLSyntax/parse(_:document:)`` recovers from errors and reports positioned
diagnostics. Call `get()` on the result to stop at the first
error:

```swift
import ECore
import EOL
import ETL
import Foundation

let source = """
    @greedy
    rule Tree2Node transform t : Tree!Tree to n : Graph!Node {
        n.name = t.label;
        n.leaf = t.children.isEmpty();
    }
    """
let parsed = ETLSyntax.parse(source, document: "tree2graph.etl")
for diagnostic in parsed.diagnostics {
    print(diagnostic.message)
}
let module = try parsed.get()
```

## Transform

Load the source model and create an empty target model that shares its resource
set. The program names them by their model names (`Tree` and `Graph` here):

```swift
let resourceSet = ResourceSet()
let tree = try await EOLModel.load(
    name: "Tree",
    url: URL(fileURLWithPath: "Tree.xmi"),
    metamodels: [URL(fileURLWithPath: "Tree.ecore")],
    resourceSet: resourceSet)
let graphPackages = try await ModelIO.registerMetamodels(
    at: [URL(fileURLWithPath: "Graph.ecore")], in: resourceSet)
let graph = await EOLModel.empty(
    name: "Graph", packages: graphPackages, resourceSet: resourceSet,
    uri: "memory:/graph.xmi")

let transformer = ETLTransformer(module: module, models: [tree, graph])
try await transformer.transform()
```

Save the target with swift-ecore:

```swift
try await ModelIO.save(graph.resource, to: URL(fileURLWithPath: "Graph.xmi"))
```

## Inspect the trace

``ETLTransformer/trace`` records each rule application as an
``ETLTraceLink`` with the rule name, the source element and the target elements:

```swift
for link in transformer.trace.links {
    print("\(link.rule): \(link.targets.count) target(s)")
}
```

## Next steps

- <doc:UnderstandingETL> describes the phases of a transformation, equivalents
  and the supported constructs.
