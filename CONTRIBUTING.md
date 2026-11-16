# Contributing to yard

Thank you for your interest in contributing to **yard**.

## Prerequisites

- [Zig](https://ziglang.org/) **0.16.0**

```sh
git clone https://github.com/SMC17/yard.git
cd yard
zig build test-core
zig build test-all
```

## Guidelines

- **One topic per PR** and link the relevant issue (`Closes #N`) when applicable.
- **Evidence first.** Include the exact command, commit, toolchain, and target machine for any performance or validation claim.
- **Module-scoped changes.** Each module keeps its own `build.zig`, source, and test suite; co-locate unit tests in the module you change.
- **Zig 0.16 conventions.** Prefer explicit error sets, allocator-aware APIs, and `defer` for resource cleanup.

## License

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE).
