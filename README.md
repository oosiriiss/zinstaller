# Zinstaller

A **declarative, automated system configuration tool** written in [Zig](https://ziglang.org/), designed for Arch Linux-based systems. Zinstaller automates the process of setting up a new system from scratch - downloading packages, running per-package setup scripts, managing dotfiles, and recovering from interrupted sessions using a persistent cache. The project also features it's own custom-written configuration language.

---

## Features

- **Custom configuration language** - a purpose-built language with its own lexer, parser, and AST. Supports string literals, booleans, lists, nested objects, comments, and escape sequences.
- **Declarative package definitions** - packages are described in plain `.list` files using the custom language, with optional descriptions, setup commands, and recursive dependencies.
- **Recursive dependency resolution** - the dependency graph is flattened via DFS traversal, with automatic deduplication of packages appearing in multiple dependency trees.
- **Interactive package selection** - at startup, the user is prompted to exclude packages by number or inclusive range (e.g. `1 3 5-8`), making partial installs easy.
- **Per-package setup scripts** - each package can declare a shell script to run after installation. Scripts receive `DOTFILES_DIR` and `CONFIG_DIR` environment variables automatically.
- **Resumable sessions via cache** - progress is serialized to a `.cache` file after each stage. If the process is interrupted, the user is prompted to resume from the last saved state.

---


## Building and running

**Requirements:**
- [Zig](https://ziglang.org/download/) (0.15.1)
- `yay` (AUR helper for Arch Linux, currently used to download packages) 


**Build && run**

```bash
zig build

# Make sure you have correct directories specified (Watch out for relative paths - you may need to copy the executable from build directory)
zig build run
```

**Configuration:** Place `installer.cfg` in the working directory (or adjust `CONFIG_PATH` in `main.zig`). The config file is optional - all paths have defaults.

**Directory layout example:**
```
.
├── <compiled_executable>
├── installer.cfg
├── packages.list
├── scripts/
│   ├── setup_neovim.sh
│   └── setup_fd.sh
└── dotfiles/
    └── nvim/
```

---

## The Configuration Language

All three data files - the main config, the packages list, and the cache - are parsed using the same custom language and the same lexer/parser pipeline.

### Language Syntax

The language supports the following constructs:

**Primitive values:**
```
name = "hello world";
flag = true;
flag2 = false;
```

**Lists:**
```
items = ["first", "second", "third"];
```

**Objects** (typed named scopes):
```
myobject {
    field1 = "value";
    field2 = true;
}
```

**Comments** (C++ style, single-line):
```
// This is a comment - everything after // is ignored until newline
name = "foo"; // inline comment also works
```

**Escape sequences in strings:**
| Sequence | Meaning |
|---|---|
| `\"` | literal double-quote |
| `\\` | literal backslash |
| `\n` | newline |
| `\r` | carriage return |
| `\0` | null byte |

**Statement termination** is flexible: a semicolon `;` or a newline both end a statement. This allows both compact and relaxed formatting styles.

### Config File (`installer.cfg`)

The main configuration file is a single object named `config`:

```
config {
    scripts_dir    = "./scripts";
    dotfiles_dir   = "./dotfiles";
    config_dir     = "~/.config";
    packages_file  = "./packages.list";
    cache_file     = "./packages.cache";
    log_file       = "./out.log";
    setup_script_stop_on_fail = false;
}
```

For an example file check [Example config](./installer.cfg) or [development example config](./installer/installer.cfg)

All fields are optional. Default values:

| Field | Default |
|---|---|
| `scripts_dir` | `./scripts` |
| `dotfiles_dir` | `./dotfiles` |
| `config_dir` | `~/.config` |
| `packages_file` | `./packages.list` |
| `cache_file` | `./packages.cache` |
| `log_file` | `./out.log` |
| `setup_script_stop_on_fail` | `false` |

When `setup_script_stop_on_fail = true`, bash is invoked with `-e` flag, causing the setup script to exit immediately on the first failing command.

### Packages File (`.list`)

The packages file is a top-level list of package definitions. Each entry can be either:

**A simple string** (name only, no setup):
```
[
    "git",
    "curl",
    "wget"
]
```

**A `package` object** with optional fields:
```
[
    package {
        name        = "neovim";
        description = "Chad editor";
        setup_command = "./setup_neovim.sh";
        dependencies = [
            package {
                name        = "fd";
                description = "\"find\" alternative";
                setup_command = "./setup_fd.sh";
            },
            "ripgrep",
            package {
                name = "wl-clipboard";
                description = "wayland clipboard support";
            }
        ];
    }
]
```

`PackageDescriptor` fields:

| Field | Type | Required |
|---|---|---|
| `name` | `string` | yes |
| `description` | `string` | no |
| `setup_command` | `string` (path to script, relative to ```scripts_dir``` in config) | no |
| `dependencies` | `list` of packages | no |

Dependencies can themselves be full `package` objects with their own nested dependencies, forming an arbitrarily deep tree.

### Cache File (`.cache`)

The cache is written and read automatically by the tool. It stores the installation status of each package as a list of typed objects:

```
[
    entry { name = "fd"; status = "finished"; },
    entry { name = "ripgrep"; status = "setup"; },
    entry { name = "neovim"; status = "download"; },
]
```

Possible statuses: `download` → `setup` → `finished`.

---

## Setup Scripts

Each package's `setup_command` points to a shell script relative to `scripts_dir`. Scripts are invoked by bash with a working directory of `scripts_dir` and receive two environment variables:

| Variable | Value |
|---|---|
| `DOTFILES_DIR` | Path to the dotfiles directory, relative to `scripts_dir` |
| `CONFIG_DIR` | Path to the system `.config` directory, relative to `scripts_dir` |

**Example - script that always succeeds even if a command fails (`-e` not set):**
```bash
echo "Setting up fd..."
false            # This fails, but the script continues
echo "OK"
```

**Example - script that stops on first failure (`setup_script_stop_on_fail = true`):**
```bash
set -e
cp $DOTFILES_DIR/nvim $CONFIG_DIR/nvim
echo "Neovim config copied"
false            # Script stops here
echo "FAILED"   # Never reached
```

---


## Testing

The project has an extensive unit test suite covering all major subsystems. Tests are embedded directly in each source file using Zig's built-in `test` blocks.

Run all tests:
```bash
zig test src/main.zig
```


### LICENSE

This project is licensed under MIT License check [License](./LICENSE) for details

