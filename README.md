# Common Lisp Development Container Features

Installs the Common Lisp programming language into a [development container](https://containers.dev/).

## Example Usage

```json
"features": {
    "ghcr.io/Symbolics/devcontainer-features/lisp:1": {}
}
```

## Options

You can select a specific Common Lisp implementation by specifying a name as an option. For example, the following installs the SBCL release:

```json
"features": {
    "ghcr.io/Symbolics/devcontainer-features/lisp:1": {
        "implementation": "sbcl"
    }
}
```