#!/bin/bash

# Id: git-versioning/0.0.16-dev-master+20150504-0251 tools/prep-version.sh


# Script to reset flags for (auto) increments

# just set pre-release tag to the branch
BRANCH=$(git status|grep On.branch|awk '{print $3}')
./bin/cli-version.sh pre-release $BRANCH

