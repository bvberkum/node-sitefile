#!/usr/bin/env bash

set -e

test -z "$Build_Debug" || set -x

test -n "$sudo" || sudo=

test -n "$SRC_PREFIX" || {
  echo "Not sure where checkout"
  exit 1
}

test -n "$PREFIX" || {
  echo "Not sure where to install"
  exit 1
}

test -d $SRC_PREFIX || ${sudo} mkdir -vp $SRC_PREFIX
test -d $PREFIX || ${sudo} mkdir -vp $PREFIX


install_bats()
{
  echo "Installing bats"
  pushd $SRC_PREFIX
  git clone https://github.com/sstephenson/bats.git
  cd bats
  ${sudo} ./install.sh $PREFIX
  popd
}

install_git_versioning()
{
  git clone https://github.com/dotmpe/git-versioning.git $SRC_PREFIX/git-versioning
  ( cd $SRC_PREFIX/git-versioning && ./configure.sh $HOME/.local && ENV=production ./install.sh )
}


main_entry()
{
  test -n "$1" || set -- '*'

  case "$1" in '*'|project|git )
      git --version >/dev/null || { echo "Sorry, GIT is a pre-requisite"; exit 1; }
    ;; esac

  case "$1" in '*'|build|test|sh-test|bats )
      test -x "$(which bats)" || install_bats || return $?
    ;; esac

  case "$1" in '*'|project|ditaa )
      # TODO: setup curl to do raw install,
      #http://downloads.sourceforge.net/project/ditaa/ditaa/0.9/ditaa0_9.zip
      # And: u-c to do via brew or apt or whatever
      # FIXME: Darwin only..
      test -x "$(which ditaa)" || brew install ditaa
    ;; esac


  case "$1" in '*'|project|dev|build|test|check|\
      sh-test|git|git-versioning|bats|ditaa ) ;;
    *)
      echo "No such known dependency '$1'"
      exit 2
    ;; esac

  echo "OK. All pre-requisites for '$1' checked"
}

test "$(basename $0)" = "install-dependencies.sh" && {
  main_entry $@ || exit $?
}

# Id: git-versioning/0.0.27-test install-dependencies.sh
