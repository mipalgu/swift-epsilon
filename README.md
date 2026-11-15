# Swift Epsilon - Epsilon Model Management Languages

[![CI](https://github.com/mipalgu/swift-epsilon/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-epsilon/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-epsilon/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-epsilon/actions/workflows/documentation.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-epsilon%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mipalgu/swift-epsilon)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-epsilon%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mipalgu/swift-epsilon)

A pure Swift implementation of a subset of the
[Eclipse Epsilon](https://eclipse.dev/epsilon/) model management languages for
Ecore models: the Epsilon Object Language and its validation, transformation and
generation dialects.

## Features

- **EOL**: parser and interpreter for the Epsilon Object Language
- **EVL**: validation with contexts, constraints, critiques and fixes
- **ETL**: rule-based model-to-model transformation with a trace
- **EGL and EGX**: text generation from templates, with protected regions that
  survive regeneration, and rules that generate files
- **Editor support**: error-tolerant parsing with positioned diagnostics, outlines
  and highlighting tokens
- **[swift-ecore](https://github.com/mipalgu/swift-ecore) integration**: works on
  models held in ECore resources

## Requirements

- Swift 6.0 or later
- macOS 15.0 or later, Linux or Windows

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-epsilon.git", branch: "main")
]
```

And add the products you need to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EOL", package: "swift-epsilon"),
        .product(name: "EVL", package: "swift-epsilon"),
        .product(name: "ETL", package: "swift-epsilon"),
        .product(name: "EGL", package: "swift-epsilon"),
    ]
)
```

## Building

```bash
# Build the library
swift build

# Run tests
swift test
```

Setting `EPSILON_REFERENCE_DIR` to a checkout of the public Epsilon examples
enables an optional comparison test.

## Usage

Load a model with swift-ecore and run an EOL program against it:

```swift
import ECore
import EOL
import Foundation

let library = try await EOLModel.load(
    name: "Library",
    url: URL(fileURLWithPath: "Library.xmi"),
    metamodels: [URL(fileURLWithPath: "Library.ecore")],
    resourceSet: ResourceSet())
let module = try EOLSyntax.parse("Book.all.collect(b | b.title).println();").get()
try await EOLInterpreter(models: [library]).run(module)
```

## Documentation

Each module has its own published documentation:

- [EOL](https://mipalgu.github.io/swift-epsilon/documentation/eol/):
  [Getting Started](https://mipalgu.github.io/swift-epsilon/documentation/eol/gettingstarted),
  [Understanding EOL](https://mipalgu.github.io/swift-epsilon/documentation/eol/understandingeol)
- [EVL](https://mipalgu.github.io/swift-epsilon/documentation/evl/):
  [Getting Started](https://mipalgu.github.io/swift-epsilon/documentation/evl/gettingstarted),
  [Understanding EVL](https://mipalgu.github.io/swift-epsilon/documentation/evl/understandingevl)
- [ETL](https://mipalgu.github.io/swift-epsilon/documentation/etl/):
  [Getting Started](https://mipalgu.github.io/swift-epsilon/documentation/etl/gettingstarted),
  [Understanding ETL](https://mipalgu.github.io/swift-epsilon/documentation/etl/understandingetl)
- [EGL](https://mipalgu.github.io/swift-epsilon/documentation/egl/):
  [Getting Started](https://mipalgu.github.io/swift-epsilon/documentation/egl/gettingstarted),
  [Understanding EGL](https://mipalgu.github.io/swift-epsilon/documentation/egl/understandingegl)

The `swift-epsilon` command-line tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/) is described in
[swift-epsilon](https://mipalgu.github.io/swift-modelling/documentation/swift_epsilon/index.html),
and the Epsilon tutorials [Querying and Validating Models with EOL and EVL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/epsilon-01-eol-evl/index.html) and
[Transforming Models and Generating Text with ETL and EGL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/epsilon-02-etl-egl/index.html)
introduce it step by step (see all [tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)).

## Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/) - EMF/Ecore metamodelling, OCL, generator models and multi-level modelling ([GitHub](https://github.com/mipalgu/swift-ecore))
- [swift-aql](https://mipalgu.github.io/swift-aql/) - AQL model queries ([GitHub](https://github.com/mipalgu/swift-aql))
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation ([GitHub](https://github.com/mipalgu/swift-mtl))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations ([GitHub](https://github.com/mipalgu/swift-atl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations ([GitHub](https://github.com/mipalgu/swift-xtend))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Licence

See the details in the LICENCE file.

This package is an independent implementation based on the public
[Epsilon documentation](https://eclipse.dev/epsilon/doc/) and papers. Epsilon itself is an Eclipse project under the
Eclipse Public License 2.0.

## References

- [Eclipse Epsilon](https://eclipse.dev/epsilon/) - The reference implementation
- Kolovos, Paige and Polack, "[The Epsilon Object Language (EOL)](https://doi.org/10.1007/11787044_11)",
  ECMDA-FA 2006
- Kolovos, Paige and Polack, "[The Epsilon Transformation Language](https://doi.org/10.1007/978-3-540-69927-9_4)",
  ICMT 2008
- Kolovos, Paige and Polack, "[On the Evolution of OCL for Capturing Structural
  Constraints in Modelling Languages](https://doi.org/10.1007/978-3-642-11447-2_13)", 2009 (EVL)
- Rose, Paige, Kolovos and Polack, "[The Epsilon Generation Language](https://doi.org/10.1007/978-3-540-69100-6_1)",
  ECMDA-FA 2008
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The metamodelling foundation
