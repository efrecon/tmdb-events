#!/bin/sh


set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Root directory where this script is located
: "${FILTER_ROOTDIR:="$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )"}"

# List of JSON keys to apply filtering to, space separated, jq format. Empty
# means all keys, e.g. .biography .date_of_birth
: "${FILTER_KEYS:=""}"

# Regular expression to match values to keep, case insensitive. If empty, all
# values are kept, e.g. (français|francais|french|france)
: "${FILTER_REGEX:=""}"

# Lines matching this regex will be removed from the content before testing the
# keys. Useful to remove source lines, e.g. "Source: Wikipedia" that would
# make too much content to be kept.
: "${FILTER_CLEAN:="^Source:"}"

# Path to show.sh script to extract keys from content. Defaults to show.sh in
# the same directory as this script.
: "${FILTER_SHOW:="${FILTER_ROOTDIR%//}/show.sh"}"

# Verbosity level, can be increased with -v option
: "${FILTER_VERBOSE:=0}"

usage() {
  # This uses the comments behind the options to show the help. Not extremely
  # correct, but effective and simple.
  echo "$0 saves relevant TMDB entity to disk" && \
    grep "[[:space:]].)[[:space:]][[:space:]]*#" "$0" |
    sed 's/#//' |
    sed -E 's/([a-zA-Z-])\)/-\1/'
  printf \\nEnvironment:\\n
  set | grep '^FILTER_' | sed 's/^FILTER_/    FILTER_/g'
  exit "${1:-0}"
}

# Parse named arguments using getopts
while getopts ":k:l:s:r:t:vh-" opt; do
  case "$opt" in
    k) # List of JSON keys to apply filtering to, space separated, jq format
      FILTER_KEYS=$OPTARG;;
    r) # Regular expression to match values to keep, case insensitive
      FILTER_REGEX=$OPTARG;;
    c) # Lines matching this regex will be removed from the content before testing the keys
      FILTER_CLEAN=$OPTARG;;
    v) # Increase verbosity each time repeated
      FILTER_VERBOSE=$(( FILTER_VERBOSE + 1 ));;
    h) # Show this help
      usage 0;;
    -) # Takes name of destination file as argument, empty or "-" means stdout
      break;;
    *)
      usage 1;;
  esac
done
shift $((OPTIND -1))


# PML: Poor Man's Logging on stderr
_log() {
  printf '[%s] [%s] [%s] ' \
    "$(basename "$0")" \
    "${1:-LOG}" \
    "$(date +'%Y%m%d-%H%M%S')" \
    >&2
  shift
  _fmt="$1"
  shift
  # shellcheck disable=SC2059 # ok, we want to use printf format
  printf "${_fmt}\n" "$@" >&2
}
trace() { [ "$FILTER_VERBOSE" -ge "2" ] && _log DBG "$@" || true ; }
info() { [ "$FILTER_VERBOSE" -ge "1" ] && _log NFO "$@" || true ; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }


# Silence the command passed as an argument.
silent() { "$@" >/dev/null 2>&1 </dev/null; }

# Use external show.sh to extract keys from content
# $1: path to file where to extract the key from
content() {
  SHOW_VERBOSE=$FILTER_VERBOSE \
  SHOW_KEYS=$FILTER_KEYS \
  SHOW_CLEAN=$FILTER_CLEAN \
    "$FILTER_SHOW" -- "$1"
}

# Verify required commands are available
silent command -v jq || error "jq command not found"

# Dump content from stdin to temporary file, we might read several times from
# it.
_content=$(mktemp)
cat > "$_content"

# When no regex is provided, match all values.
if [ -z "$FILTER_REGEX" ]; then
  FILTER_REGEX=".*"
  trace "No FILTER_REGEX set, matching all values"
fi

# If at least one key matched, save or output the content, else remove the
# temporary file.
if content "$_content" | grep -Eiq "$FILTER_REGEX"; then
  if [ -z "${1:-}" ] || [ "$1" = "-" ]; then
    info "Copying content to stdout"
    cat "$_content"
    rm -f "$_content"
  else
    info "Saving content to %s" "$1"
    mv -f "$_content" "$1"
  fi
else
  trace "No content matching regex %s, skipping" "$FILTER_REGEX"
  rm -f "$_content"
fi
