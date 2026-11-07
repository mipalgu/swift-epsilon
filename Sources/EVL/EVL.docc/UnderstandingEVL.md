# Understanding EVL

How validation runs, how results are reported and which EVL constructs are supported.

## Overview

EVL adds contexts, constraints, critiques and fixes to EOL (Kolovos, Paige and
Polack, "On the Evolution of OCL for Capturing Structural Constraints in
Modelling Languages", 2009). Its semantics follow the Epsilon documentation;
where the documentation leaves a detail open, the choice made here is stated.

## Execution order

``EVLValidator/validate(_:)`` runs in four steps:

1. The `pre` blocks run, and the variables they declare stay visible.
2. Every non-lazy constraint of every non-lazy context is checked for each
   instance of the context type, including instances of subtypes, unless the
   context or constraint `guard` excludes it.
3. Each unsatisfied constraint is recorded with its message and applicable fixes.
4. The `post` blocks run.

Results are cached per constraint and element, so `satisfies`, `satisfiesAll`
and `satisfiesOne` never check a constraint twice. Lazy constraints and contexts
(annotated `@lazy`) run only through those operations.

## Diagnostics

An unsatisfied constraint is an error and an unsatisfied critique is a warning.
``EVLUnsatisfiedConstraint/diagnostic`` locates the result at the constraint
declaration in its document, using the `message` of the constraint or a default
message. A `guard`, `check` or `message` can be written as `: expression` or as
a block ending in `return`. The variables of a `check` block are visible to its
`message` and to its fixes.

## Fixes

A `fix` has an optional `guard`, a `title` and a `do` block. Only fixes whose
guards hold are offered, as ``EVLFixOffer`` values on the unsatisfied
constraint. ``EVLValidator/apply(_:)`` runs the block with `self` bound to the
element and clears the interpreter's caches, so a second validation sees the
repair. The caller chooses which fix to apply.

## Supported constructs

| Construct | Status | Notes |
|:--|:--|:--|
| `context T { guard … constraint … critique … }` | Supported | Contexts apply to instances of the type and its subtypes. |
| `guard`, `check`, `message` as `: expression` or `{ … return …; }` | Supported | Variables of `check` are visible to `message` and to fixes. |
| `@lazy` constraints and contexts | Supported | Lazy constraints run only through `satisfies`. |
| `satisfies`, `satisfiesAll`, `satisfiesOne` | Supported | Results are cached per constraint and element. |
| `fix { guard … title … do { … } }` | Supported | Fixes are listed; ``EVLValidator/apply(_:)`` applies one. |
| `pre`/`post` (named or not), operations, `import` | Supported | Variables declared in `pre` are global. |
| Results as diagnostics | Supported | Constraints are errors, critiques warnings, located at the declaration. |
| Constraints outside a context | Unsupported | Reported as `eol.unsupportedConstruct`. |
| Interactive fix selection, transactional fixes | Unsupported | |

All EOL constructs are available inside blocks and expressions, as listed in the
EOL documentation.

## Topics

### Essentials

- <doc:GettingStarted>
