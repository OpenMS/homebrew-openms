# OpenMS Homebrew tap

Nightly [Homebrew](https://brew.sh) bottles of [OpenMS](https://openms.de) built from the
[`nightly`](https://github.com/OpenMS/OpenMS/tree/nightly) branch of OpenMS/OpenMS.

```sh
brew tap openms/openms
brew trust openms/openms               # required by Homebrew >= 6.0 for third-party taps
brew install openms                    # TOPP command-line tools (pulls in libopenms)
brew install openms-gui                # TOPPView, TOPPAS, INIFileEditor
brew install libopenms                 # only the C++ library, e.g. to build against it
```

| Formula      | Contents                                                                 | Depends on            |
| ------------ | ------------------------------------------------------------------------ | --------------------- |
| `libopenms`  | libOpenMS, libOpenSwathAlgo, libOpenMS_CLI, headers, CMake package, `share/OpenMS` (incl. PeptDeep models) | — |
| `openms`     | TOPP command-line tools, `share/OpenMS/TOOLS/OpenMS-TOPP.tsv` (keg-only) | `libopenms`           |
| `openms-gui` | libOpenMS_GUI, TOPPView, TOPPAS, INIFileEditor (app bundles on macOS), ExecutePipeline, ImageCreator; only these entry points are linked into `bin` | `libopenms`, `openms`, Qt |

`openms` is keg-only: its ~150 tools have generic names (`FileInfo` clashes with leptonica's
`fileinfo` on case-insensitive file systems) and are not linked into `HOMEBREW_PREFIX/bin`. To use
them, add them to `PATH`:

```sh
export PATH="$(brew --prefix openms)/bin:$PATH"
```

They find their tool registry relative to themselves, so no other setup is needed. `openms-gui`
lays out the GUI in `libexec` as a merged installation (`libexec/bin` holds the GUI tools plus
links to all TOPP tools, `libexec/share/OpenMS/TOOLS` both registries), so TOPPView and TOPPAS
find the TOPP tools without `openms` being linked. On macOS, link the apps with
`ln -sf "$(brew --prefix openms-gui)"/Applications/*.app /Applications/`.

The three formulae are built from the same OpenMS commit: `libopenms` with `BUILD_TOPP_TOOLS=OFF
WITH_GUI=OFF`, the other two against the installed `libopenms` with
`OPENMS_USE_INSTALLED_LIBRARY=ON` ([OpenMS#10339](https://github.com/OpenMS/OpenMS/pull/10339)).
Their versions must always match exactly. pyOpenMS is intentionally not packaged here.

Upgrading from the earlier all-in-one `openms` formula: `libopenms` takes over the library files
(`link_overwrite`), so `brew upgrade openms` works without manual unlinking.

## How bottles are built

Bottles are built with the same `brew` commands `brew test-bot` runs (`install --build-bottle`,
`bottle --json`, `audit`, reinstall from the bottle, `linkage --test`, `test`; see
[`build-bottles.sh`](.github/scripts/build-bottles.sh)) and published with `brew pr-upload` to
GitHub Packages, like homebrew-core. `brew test-bot --only-formulae` itself is not used, because it
uninstalls and reinstalls the whole dependency tree around every formula, which took about half of
each CI run. The bottle downloads of the dependency trees are kept in the Actions cache, keyed on
the exact dependency versions.

- [`nightly.yml`](.github/workflows/nightly.yml): triggered by OpenMS/OpenMS after the `nightly`
  branch moves (`repository_dispatch`, type `openms-nightly`), with a daily fallback at 04:00 UTC
  and manual `workflow_dispatch`. It
  1. pins all three formulae to the `nightly` commit
     ([`bump-nightly.py`](.github/scripts/bump-nightly.py)): source tarball, version
     `X.Y.Z-pre.YYYYMMDD`, and `resource`s for everything OpenMS' CMake would download
     (FetchContent deps, PeptDeep ONNX models; only `libopenms` needs them), read from OpenMS' CMake files at that commit;
  2. builds bottles on macOS and Linux ([`build.yml`](.github/workflows/build.yml));
  3. uploads them to `ghcr.io/openms/openms` and pushes the bottle commit to `main`.
- [`tests.yml`](.github/workflows/tests.yml) / [`publish.yml`](.github/workflows/publish.yml):
  the standard `brew tap-new` pull request flow (build as above, then `brew pr-pull`) for
  manual formula changes.

### Compiler cache

A full OpenMS build takes hours on hosted runners, so CI keeps a
[ccache](https://ccache.dev) per runner OS in the Actions cache. The formulae only use it when
`HOMEBREW_OPENMS_CCACHE` and `HOMEBREW_OPENMS_CCACHE_DIR` are set (CI only). The cache is saved
by the nightly run (default-branch scope, saved even on failure) and restored by every run,
including pull requests.

### Triggering from OpenMS/OpenMS

Add to `.github/workflows/update_nightly.yml` after the nightly branch is updated, using a token
(e.g. the OpenMS GitHub App) with `contents: write` on this repository:

```yaml
    - name: Build Homebrew bottles
      if: steps.compare_branches.outputs.behind == 'true' || inputs.force
      run: gh api repos/OpenMS/homebrew-openms/dispatches -f event_type=openms-nightly -f "client_payload[sha]=$(git rev-parse HEAD)"
      env:
        GH_TOKEN: ${{ steps.app-token.outputs.token }}
```

## Upstreaming to homebrew-core

The formulae are written to homebrew-core rules (offline build, no vendored downloads, tests).
For submission, replace the nightly `url`/`version` with a release tarball, drop `livecheck`
`skip` and the `ccache_args` hook.
