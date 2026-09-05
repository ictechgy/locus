#!/bin/sh
# Recreates the git-flavored demo environment for Examples/DemoApp.
#
# The demo app sources are tracked as regular files in this repository. To run
# the README Quickstart's git-dependent step (`locus affected-tests` with a
# dirty working tree), give the demo its own throwaway git repository:
#
#   Scripts/setup-demo.sh
#
# Afterwards `git status` in the parent repo shows "m Examples/DemoApp" — that
# is the nested repo, by design of the demo. Remove Examples/DemoApp/.git to
# make it disappear. Zero-git alternative: `locus affected-tests
# --files Sources/ProfileView.swift`.
set -eu
cd "$(dirname "$0")/../Examples/DemoApp"

git init -q -b main
git config user.name "locus-demo"
git config user.email "demo@localhost"
git add -A
git commit -q -m "demo app baseline"

# One uncommitted change, so `locus affected-tests` has something to see.
printf '\n// demo dirty change: identifier coverage experiment\n' >> Sources/ProfileView.swift
echo "DemoApp ready: 1 commit + 1 uncommitted change in Examples/DemoApp/.git"
