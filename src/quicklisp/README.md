
# Quicklisp (quicklisp)

Install the Quicklisp package manager for Common Lisp.

## Example Usage

```json
"features": {
    "ghcr.io/Symbolics/devcontainer-features/quicklisp:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| make_slim | Remove build dependencies after installation to reduce image size. | boolean | true |
| dist_version | Version of the Quicklisp distribution to install. | string | latest |
| client_version | Version of the Quicklisp client to install. | string | latest |
| add_to_init_file | Add Quicklisp to the Lisp implementation's init file. | boolean | true |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/Symbolics/devcontainer-features/blob/main/src/quicklisp/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
