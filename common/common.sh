#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

function common::log () {
  GREEN="$1"
  shift
  if [ -t 2 ] ; then
    echo -e "[$(date +%H:%M:%S)] \e[1m \x1B[97m* \x1B[92m${GREEN}\x1B[39m \e[0m $*" 1>&2
  else
    echo "* ${GREEN} $*" 1>&2
  fi
}

function common::lognewline () {
    common::log "$* \n"  >&2
}

function common::die () {
    common::log "\e[31m[ ERROR ] \e[0m $*"  >&2
    exit 1
}

function common::warn() {
    common::log "\e[33m[ WARNING ]  \e[0m$*"
}

function common::debug() {
    common::log "\e[39m[ DEBUG ]  \e[0m$*"
}

function common::bold(){
    echo -e "\e[1m$*\e[0m"
}

function common::title(){
    echo -e "\e[1m\x1B[92m************ $* ************\x1B[39m\e[0m"
}

function common::underline(){
    echo -e "\e[4m$*\e[0m"
}

function common::text(){
    echo -e "$*"
}

function common::paragraph(){
    echo -e "$*\n"
}
