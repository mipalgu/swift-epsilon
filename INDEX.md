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

## Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/) - EMF/Ecore metamodelling, OCL, generator models and multi-level modelling ([GitHub](https://github.com/mipalgu/swift-ecore))
- [swift-aql](https://mipalgu.github.io/swift-aql/) - AQL model queries ([GitHub](https://github.com/mipalgu/swift-aql))
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation ([GitHub](https://github.com/mipalgu/swift-mtl))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations ([GitHub](https://github.com/mipalgu/swift-atl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations ([GitHub](https://github.com/mipalgu/swift-xtend))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Documentation

The package provides the EOL, EVL, ETL and EGL modules.
For [EOL](documentation/eol/), see
[Getting Started](documentation/eol/gettingstarted) and
[Understanding EOL](documentation/eol/understandingeol).
For [EVL](documentation/evl/), see
[Getting Started](documentation/evl/gettingstarted) and
[Understanding EVL](documentation/evl/understandingevl).
For [ETL](documentation/etl/), see
[Getting Started](documentation/etl/gettingstarted) and
[Understanding ETL](documentation/etl/understandingetl).
For [EGL](documentation/egl/), see
[Getting Started](documentation/egl/gettingstarted) and
[Understanding EGL](documentation/egl/understandingegl).

The `swift-epsilon` command-line tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/) is described in
[swift-epsilon](https://mipalgu.github.io/swift-modelling/documentation/swift_epsilon/index.html),
and the Epsilon tutorials [Querying and Validating Models with EOL and EVL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/epsilon-01-eol-evl/index.html) and
[Transforming Models and Generating Text with ETL and EGL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/epsilon-02-etl-egl/index.html)
introduce it step by step (see all [tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)).
