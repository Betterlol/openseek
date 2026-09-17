# Proton Desktop Applications

Proton builds native desktop applications with a web frontend and a MoonBit
native backend. Use it for MoonBit desktop tasks unless the existing project
or the user selects another framework.

## Start a project

Use `proton_cli new my-app --yes` to generate a working project. Read its
`README.md` and `AGENTS.md` before changing the generated code. For an existing
application, start with its instructions and `proton.project.json`.

The default `isomorphic` template contains a Rabbita web frontend, a Proton
native backend, and shared command definitions. The frontend handles the UI;
the backend implements native operations. Use
`proton_cli new my-app --template minimal --yes` for a single MoonBit module
with inline HTML.

From the generated project directory:

1. Run `moon update` to resolve dependencies.
2. Run `proton_cli cef setup` to prepare CEF, the embedded browser runtime.
3. Run `proton_cli dev` to launch the application during development.

Let the CLI manage the runtime and helper; do not assemble them by hand.

## Common commands

- `proton_cli dev`: start the configured frontend and native application.
- `proton_cli build`: build the frontend and native backend without launching.
- `proton_cli package --release`: create a release application package.
- `proton_cli doctor`: inspect the project configuration and local environment.

Use `moon check` and `moon test` for MoonBit code feedback, and launch the
application with `proton_cli dev` to check its UI and native behavior.

## Project configuration

Proton CLI projects are configured by `proton.project.json`. Set the child
process working directory to the directory containing that file, or pass the
command's explicit `--config` option; do not use the global `-C`/`--cwd`
options and do not assume Proton searches parent directories.

In `proton.project.json`, `backend.path` must identify the exact MoonBit
working directory. Do not assume Proton searches parent directories for a
`moon.work` or `moon.mod` file.

## Find help

Read `proton_cli --help` for available commands and
`proton_cli <command> --help` before using unfamiliar options. If the CLI is
not installed, it can be invoked with `moonx moonbit-community/proton_cli`.

Use `moon ide doc` from the relevant MoonBit module to inspect imported Proton
APIs before guessing names or signatures. Query package aliases or symbols
from the generated code, for example `moon ide doc "@proton"` in the backend.
