
# ls-dev (ls-dev)

Development environment for lisp-stat with configurable BLAS libraries.

## Example Usage

```json
"features": {
    "ghcr.io/Symbolics/devcontainer-features/ls-dev:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| blas | Choose BLAS library | string | openblas |
| install_emacs | Install Emacs (nox) with SLIME for Common Lisp development | boolean | true |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/Symbolics/devcontainer-features/blob/main/src/ls-dev/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
