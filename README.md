# xmake-psx
Utilities for PlayStation 1 projects that use Xmake as their build system. This is intended to be used as a git submodule, or you can just copy it (but it still needs some improvements, so you should preferably be able to update it later).

> [!NOTE]
> This is not an SDK in any way, and it doesn't provide any libraries. It only deals with compilation (including the bare minimum amount of supporting code required for freestanding C and C++), and has some user-facing utilities. To actually access the PS1 hardware from your code and do anything, you can either implement that yourself, or use a library like [ps1-bare-metal](https://github.com/spicyjpeg/ps1-bare-metal). [Here is an example using xmake-psx and ps1-bare-metal together](https://codeberg.org/malucart/ps1-bare-metal-xmake-example).

## How to `git submodule` effectively
When including other remote projects (like xmake-psx, or a library) in a project, or simply when sharing some code across your projects, you may want to keep those things synced with their main repos so that you can update them in the future. A neat way to do this is with Git submodules. However, submodules are by default pinned to specific commits, so you can't easily update them, defeating the point of them for us. The solution is pretty simple, but you still have to pay attention. Here's how to do it:

----
When adding a new submodule, use the `-b <branch>` option, which will make it track that branch (i.e. it will be a reference to the latest commit on it). For example, this is how you add xmake-psx to a repo, assuming you want to place it in a subfolder called `ext`:
```bash
git submodule add -b main https://codeberg.org/malucart/xmake-psx ext/xmake-psx
```

----
When cloning a repo that uses submodules, you need to pass `--recursive` to it, or the submodules will not be included in your clone:
```bash
git clone --recursive <url>
```
If you try to build a project and you see "`warning: includes("ext/xmake-psx") cannot find any files!`", that means xmake-psx is missing, so you may have cloned a git repo but forgotten to pass `--recursive`. Although if xmake-psx wasn't present in the original repo either, you may just have to provide it manually.

----
When you have an existing repo and you want to update its submodules, do the following. If they're already up to date, there will be no output.
```bash
git submodule update --remote
```

----
And reminder: when modifying your submodules, the `.gitmodules` file gets edited, so you have to add it to a commit.
```bash
git add .gitmodules
```

----
Yeah, this is all slightly inconvenient and a bit error prone, but it's the most reliable option I know of. Just remember the difference between a submodule tracking a commit and tracking a branch, and remember those commands.

## Getting started
To use xmake-psx in a project, you simply need to include it from your `xmake.lua`, and then add the `psx` rule to any targets that you want to compile for PS1 (that includes libraries, by the way). Here's a simple example, assuming you placed xmake-psx in an `ext/` subfolder:
```lua
includes("ext/xmake-psx")

target("example", function()
	add_rules("psx", "psexe")
	add_files("src/**.c")
end)
```
Of course, for a real project, you'll probably want to add more stuff, or you might even be throwing it into an existing project. But that's normal Xmake business, not xmake-psx's responsibility (unless you find a bug that I caused). However, I might eventually add more examples here for how to do certain things.

Also notice I threw the `psexe` rule in there; all that does is convert the regular `.elf` output of that target into a `.psexe` file after compilation is done. That's the official executable format expected by the PS1's kernel, and you'll need that in order to create a disc image, but note that xmake-psx can't help with that part yet.

By the way, when writing a README, you might want to [link](https://codeberg.org/malucart/xmake-psx#readme) it to this one, so you can keep some fluff out of yours.

## Clangd support
If you're using an editor that uses clangd for C and C++ support, just run this:
```bash
xmake project -k compile_commands
```
If it doesn't work right away, you may need to restart clangd or restart the editor.

Unfortunately, this won't get updated as you add new files or change configuration options. You need to regenerate the `compile_commands.json` file every time. You can get close by using the `plugin.compile_commands.autoupdate` rule ([see docs](https://xmake.io/api/description/builtin-rules.html#plugin-compile-commands-autoupdate)), which will regenerate it whenever you build.

## Toolchain
To compile code for PS1, you need to have an appropriate compiler toolchain installed. LLVM isn't great at MIPS-I code generation yet, so GCC is highly recommended. Generally, you should build it locally, targeting mipsel-none-elf. Also, please ensure your toolchain isn't too out of date. In part because optimizations are always improving, but also because if it is, it's very possible you'll clone a perfectly fine, but very modern bit of C or C++ code and then just end up with a crash or a cryptic error message.

xmake-psx will try to find any `mips*-gcc` in your PATH and use that, and failing that, it will fallback to Clang (if available). You can also override it using `xmake f --cross=prefix-` (for example, to use `/my/path/my-own-gcc`, run `xmake f --cross=/my/path/my-own-`).

## Running and debugging homebrew
Here are some useful commands for this:
- `xmake run` - run a target with a detected or specified PS1 emulator (PCSX-Redux and DuckStation are supported)
- `xmake gdb` - start GDB and attach it to a running GDB server (defaults to localhost:3333, matching PCSX-Redux's default) (you have to enable the GDB server in the emulator!)
- `xmake zed` - generate a debug configuration for Zed to attach to a running GDB server (generation for more editors will come later)

For quicker builds and/or better bug catching, you can switch your build from release mode into debug mode like this:
```bash
xmake f --mode=debug
```
This will undefine `NDEBUG` (so calls to `assert` will actually run), reduce the amount of optimizations and turn off LTO, and add trapping checks for division by zero. Note that debug symbols are always kept regardless of mode, since they will eventually be stripped by the conversion to a PS-EXE anyway, so you can debug release mode binaries too if you need to.
