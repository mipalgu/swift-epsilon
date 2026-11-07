# Getting Started with EOL

Add the package, load a model, and parse and run an EOL program.

## Overview

The EOL module parses Epsilon Object Language programs and runs them against
models held by swift-ecore. This article shows how to add the module, load a
model, handle parse diagnostics and run a program.

## Add the package

Add swift-epsilon to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-epsilon.git", branch: "main"),
]
```

Then add the `EOL` product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EOL", package: "swift-epsilon"),
    ]
)
```

## Load a model

``EOLModel/load(name:url:metamodels:resourceSet:aliases:)`` reads a model
document (XMI or JSON) together with its `.ecore` metamodels. Programs refer to
the model by the given name:

```swift
import ECore
import EOL
import Foundation

let resourceSet = ResourceSet()
let library = try await EOLModel.load(
    name: "Library",
    url: URL(fileURLWithPath: "Library.xmi"),
    metamodels: [URL(fileURLWithPath: "Library.ecore")],
    resourceSet: resourceSet)
```

Use ``EOLModel/empty(name:packages:resourceSet:uri:aliases:)`` to create an empty
model, for example as the target of a transformation.

## Parse a program

``EOLSyntax/parse(_:document:)`` never throws. It recovers from errors and
returns the module together with positioned diagnostics, an outline and
highlighting tokens:

```swift
let result = EOLSyntax.parse("Book.all.collect(b | b.title).println();", document: "report.eol")
for diagnostic in result.diagnostics {
    if let start = diagnostic.range?.start {
        print("\(start.line):\(start.column): \(diagnostic.message)")
    }
}
```

To stop at the first error instead, call ``EOLParseResult/get()``, which throws
an ``EOLError`` when the result has errors.

## Run a program

``EOLInterpreter`` evaluates a module against its models. Pass an
``EOLStringOutput`` to collect what the program prints instead of writing to
standard output:

```swift
let module = try result.get()
let output = EOLStringOutput()
let interpreter = EOLInterpreter(models: [library], output: output)
try await interpreter.run(module)
print(output.text)
```

``EOLInterpreter/run(_:)`` returns the value of a top-level `return`. Run-time
failures throw an ``EOLError`` whose ``EOLError/code`` is a stable identifier
from ``EOLDiagnosticCode``.

## Next steps

- <doc:UnderstandingEOL> describes how programs are evaluated.
- <doc:LanguageCoverage> lists the supported constructs.
