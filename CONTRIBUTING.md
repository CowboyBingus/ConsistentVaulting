# Build and release preparation

Use Windows x64, Python 3.10 or newer, Visual Studio C++ Build Tools with an x64 Windows SDK, and the LuaJIT revision in `dependencies.json`.

```powershell
git clone https://github.com/LuaJIT/LuaJIT.git tools/src/LuaJIT
git -C tools/src/LuaJIT checkout 24c20c94e7db195b640854619577441f9b4bc6be
```

Build the game's Windows x64 non-GC64 compiler from an x64 Native Tools Command Prompt:

```bat
cd tools\src\LuaJIT\src
msvcbuild.bat nogc64
```

From this repository's root:

```powershell
python -B scripts/build.py
```

Set `HD2_GAME_ROOT` for a nonstandard installation or `HD2_LUAJIT` to an existing compatible compiler. The source needs no parent project, extracted boot resource, native decompilation or research capture. Build inputs are checked against the supported game hashes.

In a standalone clone, output is `releases/Consistent-Vaulting-v8.zip`. Within the shared mod-development workspace, the existing packager selects that workspace's base `releases/` directory. No extra release directories are needed. Intermediate output stays in ignored `build/`; building does not install, launch or modify the game.

The build compiles the module, runs query/geometry/slope/loader regressions, validates the package and audits its publication inventory. Behavioral tests can run without game files:

```powershell
tools/src/LuaJIT/src/luajit.exe tests/test_vault.lua src
tools/src/LuaJIT/src/luajit.exe tests/test_geometry.lua src
tools/src/LuaJIT/src/luajit.exe tests/test_slope.lua src
tools/src/LuaJIT/src/luajit.exe tests/test_loader.lua src
```

Before publication, use `python -B scripts/privacy_audit.py --git --history --zip releases/Consistent-Vaulting-v8.zip`, substituting the shared base ZIP path when appropriate. The scanner defines the exact source inventory and checks reachable Git history. Optional `--staged` also verifies the index bytes. Reports contain relative paths and hashes; sensitive matches are never printed.

Keep logs, captures, dependency checkouts, binary game files and build output out of source control. Review the final diff and preserve existing public noreply Git identities. Release preparation does not publish, tag, push or rewrite repository history.

The loader is a separate dependency. Preserve the module resource `mods/cowboybingus/consistent_vaulting`, runtime singleton and manager GUID across display-name or artwork changes.
