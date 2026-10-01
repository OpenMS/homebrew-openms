#!/usr/bin/env bash
# Builds, bottles and tests formulae with the same brew commands `brew test-bot --only-formulae`
# runs, minus its dependency churn: test-bot uninstalls and reinstalls the whole dependency tree
# around every formula (~5 min each for the OpenMS/Qt trees), which is pointless here.
#
# Usage: build-bottles.sh <root-url> <formula>... (in dependency order)
set -euo pipefail

export HOMEBREW_NO_AUTOREMOVE=1

root_url="$1"
shift

step() {
  echo "::group::$*"
  local start=$SECONDS rc=0
  "$@" || rc=$?
  echo "::endgroup::"
  echo "==> $* ($((SECONDS - start)) s, exit $rc)"
  if [[ $rc -ne 0 ]]; then
    echo "::error::'$*' failed with exit code $rc"
    exit "$rc"
  fi
}

for formula in "$@"; do
  name="${formula##*/}"
  echo "::notice::Building ${formula}"

  step brew install --only-dependencies --verbose --formula --build-bottle "$formula"
  step brew install --verbose --formula --build-bottle "$formula"
  step brew audit --formula "$formula"
  step brew bottle --verbose --json "$formula" "--root-url=${root_url}"

  bottle=$(ls -t ./"${name}"--*.bottle*.tar.gz | head -n1)

  # Verify the bottle itself (not the build keg) installs, links and passes the tests.
  # HOMEBREW_NO_AUTOREMOVE keeps the uninstall from removing (and the install from re-pouring)
  # the whole dependency tree.
  step brew uninstall --formula --force --ignore-dependencies "$formula"
  step brew install "./${bottle#./}"
  step brew linkage --test "$formula"
  step brew install --formula --only-dependencies --include-test "$formula"
  step brew test --verbose "$formula"
done
