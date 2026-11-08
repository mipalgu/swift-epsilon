# Language Coverage

The subset of the Epsilon Object Language that the EOL module supports.

## Overview

The semantics follow the [Epsilon documentation](https://eclipse.dev/epsilon/doc/eol/) and the
[original paper on EOL](https://doi.org/10.1007/11787044_11) (ECMDA-FA 2006). Where the documentation leaves a detail open, the choice made
here is stated. The dialects are covered by the Understanding articles of the
EVL, ETL and EGL modules.

## EOL

| Construct | Status | Notes |
|:--|:--|:--|
| `var`, typed declarations, `var x : new T(p = v)` | Supported | Typed declarations without a value get the type's default (`0`, `""`, empty collection). |
| `=`, `:=`, `+=`, `-=`, `*=`, `/=`, `?=`, `++`, `--` | Supported | A single `=` that starts a statement assigns; elsewhere it compares. |
| `::=` | Supported | Plain assignment in EOL; dialects (ETL) convert the value. |
| `if`/`else`, `while`, `for (x : T in c)`, `switch` | Supported | `loopCount` (from one) and `hasMore`; typed iterators skip other values; `switch` falls through only on `continue`. |
| `break`, `breakAll`, `continue`, `return`, `throw`, `delete` | Supported | `delete` removes contents and all references to the element. |
| Operators, ternary `? :`/`? else`, elvis `?:`, `?.` | Supported | Logical operators share one precedence level and short-circuit. |
| Collections, ranges `Sequence{1..5}`, `Map{k = v}`, `x[i]` | Supported | Collections and maps have reference semantics; indices start at zero. |
| First-order operations | Supported | `select`, `reject`, `collect`, `selectOne`, `rejectOne`, `exists`, `forAll`, `none`, `one`, `count`, `nMatch`, `atLeastNMatch`, `atMostNMatch`, `sortBy`, `mapBy`, `closure`; `parallel…` variants run sequentially. |
| `aggregate(x \| key, value, initial?)` | Partial | The running value of a key is bound to `total`. |
| String, number, collection and map built-ins | Supported | See ``EOLBuiltinName`` and the tests; `replace` and `split` take regular expressions, `substring` is zero-based. |
| `Model!Type`, `pkg::Type`, `Type.all`, `allInstances`, `allOfKind`, `allOfType` | Supported | Unqualified types resolve in the first model that defines them; a name that is both a type and a model denotes the type. |
| `Model!Enum#literal`, `Enum#literal`, `#literal` | Supported | |
| Operations with context type, `@cached`, `$pre`, `$post` | Supported | Dispatch prefers an exact type match, then the first kind-of match in declaration order. |
| `import` | Supported | Imported operations come after the importing module's. |
| Extended properties `x.~name` | Supported | |
| Zero-argument operations written as properties (`s.size`) | Supported | Built-in operations only. |
| `eContainer`, `eContents`, `eAllContents`, `eClass`, `owningModel` | Supported | Reflective element access. |
| Property access on a collection | Partial | Collects the property over the elements (an extension; Epsilon reports an error). |
| `transaction`, `abort` | Unsupported | Reported as `eol.unsupportedConstruct`. |
| `Native`, Java methods, `System`, tools | Unsupported | Reported as `eol.nativeUnsupported`. |
| `Tuple`, `format`, `asDate`, `asVar` | Unsupported | |
