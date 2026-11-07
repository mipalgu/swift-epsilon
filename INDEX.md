# Swift Epsilon

The [swift-epsilon](https://github.com/mipalgu/swift-epsilon) package
provides a pure Swift implementation of a subset of the
[Eclipse Epsilon](https://eclipse.dev/epsilon/) model management
languages (EOL, EVL, ETL and EGL) for Ecore models.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-epsilon.git", branch: "main"),
]
```

## Requirements

- Swift 6.0 or later
- macOS 15.0+, Linux, or Windows

## References

- [Eclipse Epsilon](https://eclipse.dev/epsilon/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
- [swift-ecore](https://github.com/mipalgu/swift-ecore)

## Related Packages

- [swift-ecore](https://github.com/mipalgu/swift-ecore) - Ecore metamodelling
- [swift-aql](https://github.com/mipalgu/swift-aql) - AQL model queries
- [swift-atl](https://github.com/mipalgu/swift-atl) - ATL model transformations
- [swift-mtl](https://github.com/mipalgu/swift-mtl) - MTL code generation
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit

## Documentation

The package provides the EOL, EVL, ETL and EGL modules.
For EOL, see
[Getting Started](documentation/eol/gettingstarted) and
[Understanding EOL](documentation/eol/understandingeol).
For EVL, see
[Getting Started](documentation/evl/gettingstarted) and
[Understanding EVL](documentation/evl/understandingevl).
For ETL, see
[Getting Started](documentation/etl/gettingstarted) and
[Understanding ETL](documentation/etl/understandingetl).
For EGL, see
[Getting Started](documentation/egl/gettingstarted) and
[Understanding EGL](documentation/egl/understandingegl).
