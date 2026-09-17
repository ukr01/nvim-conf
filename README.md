# Neovim Configuration

Personal LazyVim configuration focused on C# and .NET development. It supports
Windows and Linux, including CachyOS.

## Features

- Roslyn LSP with native NuGet, project, and solution file watching
- Full-solution C# compiler and analyzer diagnostics
- Selectable `.sln`, `.slnx`, and `.csproj` debug targets
- `nvim-dap` debugging through Mason-managed `netcoredbg`
- Executable `.http` files with environments and formatted response views
- Readable overload and symbol-documentation popups
- Persistent, compact error and warning list
- Treesitter highlighting through LazyVim's current `main`-branch integration

LazyVim's `<leader>` key is `Space`. For example, `<leader>Rs` means press
`Space`, then `R`, then `s`.

## Requirements

- Neovim
- Git
- .NET SDK
- A C compiler for Treesitter parser installation:
  - Windows: Visual Studio Build Tools, LLVM, or WinLibs
  - CachyOS: `gcc` or `clang`
- `curl` and `tar` on Linux

Plugins and developer tools are managed by `lazy.nvim` and Mason. On the first
start, run:

```vim
:Lazy sync
:Mason
:checkhealth
```

Mason installs `netcoredbg`, `tree-sitter-cli`, and the other configured tools.

## Installation locations

- Windows: `%LOCALAPPDATA%\nvim`
- Linux/CachyOS: `~/.config/nvim`

## .NET language server

Roslyn is provided by `seblyng/roslyn.nvim`.

The configuration delegates file watching to Roslyn:

```lua
filewatching = "roslyn"
```

This lets Roslyn detect external project changes such as:

- Adding, removing, or updating NuGet packages
- Changes to `.csproj` files
- Changes to `.sln` and `.slnx` files
- Added or removed source files

This is preferred over restarting the entire LSP after every project-file
change. Roslyn also runs compiler and analyzer diagnostics across the full
solution.

### NuGet package browser

Open the NuGet browser with `<leader>cN` or:

```vim
:NuGet
```

First select a direct `.csproj`, or select a `.sln`/`.slnx` and then one of its
C# projects. Package references belong to projects, so solution selection is a
shortcut for narrowing the project list.

The browser supports:

- **Add**: search configured NuGet sources, select a package, then select an
  explicit version.
- **Update**: select an installed top-level package and choose a different
  version.
- **Remove**: select and remove an installed top-level package.

Searches honor the `NuGet.Config` hierarchy for the selected project, including
configured private feeds. Package changes run through the `dotnet` CLI, perform
restore and compatibility checks, and are picked up by Roslyn's native file
watcher.

Use the following command when a workspace contains multiple solutions:

```vim
:Roslyn target
```

This selects the solution used for language-server analysis. Debug project
selection is independent and is described below.

If Roslyn does not observe a project change, check it with:

```vim
:checkhealth roslyn
:LspInfo
```

As a last resort, restart it with:

```vim
:LspRestart roslyn
```

## .NET debugging

Debugging uses `nvim-dap` and the standalone `netcoredbg` adapter installed by
Mason.

### Selecting a debug project

Press `<leader>dS` to open the .NET debug-source picker.

The picker includes:

- `.sln` solutions
- `.slnx` solutions
- Direct `.csproj` files

Selecting a solution opens a second picker containing its C# projects.
Selecting a `.csproj` chooses that project directly.

The selected project is remembered for the current Neovim session and Roslyn
workspace. Select a different target with `<leader>dS` at any time.

### Starting a debug session

Press `F5`.

Before launching, the configuration:

1. Opens the target picker if no project has been selected.
2. Runs `dotnet build` for the selected project.
3. Uses MSBuild to resolve the project's actual `TargetPath`.
4. Launches the resulting assembly through `netcoredbg`.

Select an executable project rather than a class-library project.

### Quick run in an external terminal

Press `<leader>dR` or run `:DotnetRun` to launch:

```sh
dotnet run --project <selected-project>
```

The process opens in a new external terminal window. The command first reuses
the project selected with `<leader>dS`. If no project has been selected, it
uses the nearest `.csproj` above the current file; otherwise it opens the
solution/project picker.

The terminal remains open after the application exits so output and errors stay
visible. On Windows it remains at a PowerShell prompt. On Linux it displays the
exit code and waits for Enter before closing.

On Windows this uses Windows Terminal (`wt.exe`). On CachyOS and other Linux
systems it detects `wezterm`, `kitty`, `alacritty`, `foot`, `footclient`,
`konsole`, `gnome-terminal`, or `xterm`.

### Debug keybindings

| Key | Action |
| --- | --- |
| `<leader>dS` | Select a solution or C# debug project |
| `<leader>dR` | Run the selected/nearest project in an external terminal |
| `F5` | Start or continue debugging |
| `F10` | Step over |
| `F11` | Step into |
| `F12` | Step out |
| `<leader>b` | Toggle breakpoint |
| `<leader>dq` | Terminate debugging and clear breakpoints |
| `<leader>du` | Toggle the DAP UI |
| `<leader>de` | Evaluate the selected expression |

When debugging starts, the file explorer and diagnostic error list are hidden
to make room for the DAP UI. They are restored when the session ends.

## HTTP requests

`.http` files can be executed with `kulala.nvim`. Requests use the same format
as the ASP.NET Core HTTP file editor, JetBrains HTTP Client, and the VS Code
REST Client extension.

Place the cursor inside a request and press `Ctrl-Enter` or `<leader>Rs` to
send it. Responses open in a vertical split with separate body, headers,
verbose output, script output, and report views.

On the first request, Kulala automatically downloads the platform-specific
`kulala-core` executable. This requires `curl`.

HTTP methods, URLs, headers, variables, request separators, embedded JSON, and
GraphQL bodies are syntax-highlighted. Press `<leader>cf` in an `.http` buffer
to format JSON request bodies. Formatting uses the Mason-managed `jq`
executable; request methods, URLs, headers, and non-JSON bodies are left
unchanged.

Example:

```http
@baseUrl = http://localhost:5000

### List weather forecasts
GET {{baseUrl}}/weatherforecast
Accept: application/json

### Create an item
POST {{baseUrl}}/api/items
Content-Type: application/json

{
  "name": "Example"
}
```

Separate requests with `###`. The request under the cursor is the one that is
executed.

### HTTP keybindings

| Key | Action |
| --- | --- |
| `Ctrl-Enter` | Send the request under the cursor |
| `<leader>cf` | Format embedded request bodies |
| `<leader>Rs` | Send the request under the cursor |
| `<leader>Rr` | Replay the previous request |
| `<leader>Rn` | Move to the next request |
| `<leader>Rp` | Move to the previous request |
| `<leader>Rt` | Toggle response headers and body |
| `<leader>Ri` | Inspect the resolved request |
| `<leader>Rc` | Copy the request as cURL |
| `<leader>RC` | Paste a request from cURL |
| `<leader>Re` | Select an environment |
| `<leader>RS` | Show request statistics |
| `<leader>Rq` | Close the response window |
| `<leader>Rb` | Open an HTTP scratchpad |

Kulala supports variables and environment files. Create
`http-client.env.json` in the project root:

```json
{
  "development": {
    "baseUrl": "http://localhost:5000",
    "token": "development-token"
  },
  "production": {
    "baseUrl": "https://api.example.com",
    "token": "production-token"
  }
}
```

Select an environment with `<leader>Re`, then use its variables in a request:

```http
GET {{baseUrl}}/api/items
Authorization: Bearer {{token}}
```

Do not commit environment files containing real credentials. Add private
environment files to the project's `.gitignore`.

## Completion and method documentation

Completion is provided by `blink.cmp`.

### Automatic overload popup

While entering function arguments, Roslyn signature help is displayed in a
custom rounded popup. Long signatures are formatted vertically with one
parameter per line.

| Key | Action |
| --- | --- |
| `Ctrl-n` | Select the next overload, or the next completion item |
| `Ctrl-p` | Select the previous overload, or the previous completion item |

### Documentation tooltip

Place the cursor over a method, type, property, or other symbol and press:

```text
<leader>ch
```

This directly requests `textDocument/hover` from the attached language server
and displays:

- Method signatures
- XML documentation comments
- Parameter and return information
- Type and property documentation

Long C# signatures in the documentation popup are also displayed with one
parameter per line. Documentation availability depends on the information
provided by Roslyn and the referenced package's XML documentation.

## Diagnostics

Trouble provides a persistent error list at the bottom of the editor.

- Height: 6 lines
- Shows errors and warnings
- Opens automatically
- Remains visible when there are no diagnostics
- Does not take keyboard focus when opened automatically
- Temporarily hides during debugging

Use `<leader>xe` to toggle it manually.

Inline diagnostic virtual text is disabled. Diagnostics are underlined, and a
line-level diagnostic popup appears after the cursor remains idle.

## Treesitter

LazyVim owns the Treesitter setup and uses the current `nvim-treesitter`
`main` API. The local plugin override only adds the `c_sharp` parser to
LazyVim's default parser list.

Do not configure this installation with the removed
`require("nvim-treesitter.configs").setup(...)` API.

Useful commands:

```vim
:TSUpdate
:checkhealth nvim-treesitter
```

## Main configuration files

| File | Purpose |
| --- | --- |
| [`init.lua`](./init.lua) | Loads LazyVim and configures the theme and status line |
| [`lua/config/lazy.lua`](./lua/config/lazy.lua) | Bootstraps `lazy.nvim` and LazyVim |
| [`lua/config/keymaps.lua`](./lua/config/keymaps.lua) | Custom global keybindings |
| [`lua/config/options.lua`](./lua/config/options.lua) | Custom Neovim options |
| [`lua/config/autocmds.lua`](./lua/config/autocmds.lua) | Custom autocommands |
| [`lsp/roslyn.lua`](./lsp/roslyn.lua) | Roslyn full-solution analysis settings |
| [`lua/plugins/roslyn.lua`](./lua/plugins/roslyn.lua) | Roslyn plugin and file-watching configuration |
| [`lua/dotnet-projects.lua`](./lua/dotnet-projects.lua) | Shared solution and project discovery |
| [`lua/dotnet-runner.lua`](./lua/dotnet-runner.lua) | Cross-platform external terminal runner |
| [`lua/nuget-browser.lua`](./lua/nuget-browser.lua) | NuGet search, add, update, and removal workflow |
| [`lua/plugins/debugging.lua`](./lua/plugins/debugging.lua) | .NET project selection and DAP configuration |
| [`lua/plugins/http.lua`](./lua/plugins/http.lua) | `.http` request execution and response layout |
| [`lua/plugins/completion.lua`](./lua/plugins/completion.lua) | Completion and documentation-window behavior |
| [`lua/overload-picker.lua`](./lua/overload-picker.lua) | Signature-help and hover popup rendering |
| [`lua/plugins/error-list.lua`](./lua/plugins/error-list.lua) | Persistent Trouble diagnostic window |
| [`lua/plugins/treesitter.lua`](./lua/plugins/treesitter.lua) | Additional Treesitter parsers |

## Troubleshooting

### `netcoredbg` cannot be found

Open Mason and install or update `netcoredbg`:

```vim
:Mason
```

The configuration resolves Mason's Windows executable and Linux shim
automatically.

### A project is missing from the debug picker

The picker searches below the active Roslyn root and intentionally ignores
`bin`, `obj`, and `.git` directories. Confirm the desired `.sln`, `.slnx`, or
`.csproj` is located below that root.

### Package symbols or diagnostics are stale

Wait for `dotnet restore` to complete and confirm Roslyn file watching:

```vim
:checkhealth roslyn
```

Then use `:LspRestart roslyn` only if the native watcher did not process the
change.

### NuGet browser search fails

The browser requires a .NET SDK that supports JSON package search:

```sh
dotnet package search Newtonsoft.Json --format json
```

Check authenticated feeds and source precedence in the applicable
`NuGet.Config`. CLI failures are displayed directly in Neovim.

### Treesitter parser errors

Confirm that `tree-sitter-cli` and a C compiler are available:

```vim
:Mason
:checkhealth nvim-treesitter
:TSUpdate
```

### HTTP requests do not run

Confirm `curl` is installed and inspect Kulala's dependencies:

```vim
:checkhealth kulala
```

On Windows, use `curl.exe`; the PowerShell `curl` command may be an alias for
`Invoke-WebRequest`. On CachyOS, install it with:

```sh
sudo pacman -S curl
```

If the `.http` file does not activate Kulala, verify its filetype:

```vim
:set filetype?
```

It should report `filetype=http`.

If syntax highlighting is missing, update the parser and inspect health:

```vim
:TSUpdate
:checkhealth nvim-treesitter
:checkhealth kulala
```

If `<leader>cf` cannot format a JSON body, confirm that it has an
`application/json` or `application/*+json` content type, then open `:Mason`
and confirm that `jq` is installed.
