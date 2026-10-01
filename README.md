# OpenMS Homebrew tap

Nightly [Homebrew](https://brew.sh) bottles of [OpenMS](https://openms.de) built from the
[`nightly`](https://github.com/OpenMS/OpenMS/tree/nightly) branch of OpenMS/OpenMS.

```sh
brew install openms/openms/openms      # TOPP command-line tools (pulls in libopenms)
brew install openms/openms/openms-gui  # TOPPView, TOPPAS, INIFileEditor
brew install openms/openms/libopenms   # only the C++ library, e.g. to build against it
```

Or `brew tap openms/openms` and then `brew install openms`.

| Formula      | Contents                                                                 | Depends on            |
| ------------ | ------------------------------------------------------------------------ | --------------------- |
| `libopenms`  | libOpenMS, libOpenSwathAlgo, libOpenMS_CLI, headers, CMake package, `share/OpenMS` (incl. PeptDeep models) | — |
| `openms`     | TOPP command-line tools, `share/OpenMS/TOOLS/OpenMS-TOPP.tsv`            | `libopenms`           |
| `openms-gui` | libOpenMS_GUI, TOPPView, TOPPAS, INIFileEditor (app bundles on macOS, plus shell wrappers in `bin`), ExecutePipeline, ImageCreator | `libopenms`, `openms`, Qt |

The three formulae are built from the same OpenMS commit: `libopenms` with `BUILD_TOPP_TOOLS=OFF
WITH_GUI=OFF`, the other two against the installed `libopenms` with
`OPENMS_USE_INSTALLED_LIBRARY=ON` ([OpenMS#10339](https://github.com/OpenMS/OpenMS/pull/10339)).
Their versions must always match exactly. pyOpenMS is intentionally not packaged here.

Upgrading from the earlier all-in-one `openms` formula: `libopenms` takes over the library files
(`link_overwrite`), so `brew upgrade openms` works without manual unlinking.

## How bottles are built

Bottles are built with `brew test-bot` and published with `brew pr-upload` to GitHub Packages,
the same tooling homebrew-core uses.

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
  the standard `brew tap-new` pull request flow (`brew test-bot`, then `brew pr-pull`) for
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
