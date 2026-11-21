#!/bin/sh
set -eu
git config merge.sorted-set.name "merge a sorted list of lines as a set"
git config merge.sorted-set.driver "python3 .github/merge-sorted-set.py %O %A %B"
