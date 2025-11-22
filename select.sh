#!/bin/sh


set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Root directory where this script is located
: "${SELECT_ROOTDIR:="$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )"}"

# Pattern to match files to process in directories, e.g. "*.json"
: "${SELECT_PATTERN:="*.json"}"

# List of JSON keys to show.
: "${SELECT_KEYS:=""}"

# List of JSON keys to apply filtering to, space separated, jq format. Empty
# means all keys, e.g. .biography .date_of_birth
: "${SELECT_WHERE:=""}"

# Regular expression to match key values, case insensitive. If empty, all
# values are kept, e.g. (français|francais|french|france)
: "${SELECT_REGEX:=""}"

: "${SELECT_QUICK:=""}"

# Lines matching this regex will be removed from the content before testing the
# keys. Useful to remove source lines, e.g. "Source: Wikipedia" that would
# make too much content to be kept.
: "${SELECT_CLEAN:="^Source:"}"

# Path to show.sh script to extract keys from content. Defaults to show.sh in
# the same directory as this script.
: "${SELECT_SHOW:="${SELECT_ROOTDIR%//}/show.sh"}"

# Verbosity level, can be increased with -v option
: "${SELECT_VERBOSE:=0}"

usage() {
  # This uses the comments behind the options to show the help. Not extremely
  # correct, but effective and simple.
  echo "$0 saves relevant TMDB entity to disk" && \
    grep "[[:space:]].)[[:space:]][[:space:]]*#" "$0" |
    sed 's/#//' |
    sed -E 's/([a-zA-Z-])\)/-\1/'
  printf \\nEnvironment:\\n
  set | grep '^SELECT_' | sed 's/^SELECT_/    SELECT_/g'
  exit "${1:-0}"
}

# Parse named arguments using getopts
while getopts ":c:k:r:q:w:vh-" opt; do
  case "$opt" in
    k) # List of JSON keys to show.
      SELECT_KEYS=$OPTARG;;
    w) # List of JSON keys to apply filtering to, space separated, jq format
      SELECT_WHERE=$OPTARG;;
    r) # Regular expression to match values to keep, case insensitive
      SELECT_REGEX=$OPTARG;;
    q) # Quick filter to narrow down files to process
      SELECT_QUICK=$OPTARG;;
    c) # Lines matching this regex will be removed from the content before testing the keys
      SELECT_CLEAN=$OPTARG;;
    v) # Increase verbosity each time repeated
      SELECT_VERBOSE=$(( SELECT_VERBOSE + 1 ));;
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
trace() { [ "$SELECT_VERBOSE" -ge "2" ] && _log DBG "$@" || true ; }
info() { [ "$SELECT_VERBOSE" -ge "1" ] && _log NFO "$@" || true ; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }


# Silence the command passed as an argument.
silent() { "$@" >/dev/null 2>&1 </dev/null; }

# Use external show.sh to extract the value of all keys in SELECT_WHERE.
# $1: path to file where to extract the keys from
content() {
  SHOW_VERBOSE=$SELECT_VERBOSE \
  SHOW_KEYS=$SELECT_WHERE \
  SHOW_CLEAN=$SELECT_CLEAN \
    "$SELECT_SHOW" -- "$1"
}

# Use external show.sh to extract value of a given key
# $1: key to extract
# $2: path to file where to extract the key from
keyval() {
  SHOW_VERBOSE=$SELECT_VERBOSE \
  SHOW_KEYS=$1 \
  SHOW_CLEAN=$SELECT_CLEAN \
    "$SELECT_SHOW" -- "$2"
}

# Verify required commands are available
silent command -v jq || error "jq command not found"


# Quickly narrow down files to process using grep on their content.
# Use a subshell to avoid changing current directory.
# $1: directory to process
narrow() (
  cd "${1%%/}"
  # Grep files matching the quick regex, output full path by readding the
  # directory prefix using sed.
  grep -EiHl "$SELECT_QUICK" $SELECT_PATTERN |
    sed -E "s~^~${1%%/}\/~g"
)


# Extract the content of the keys in SELECT_WHERE. If it matches the regex,
# print the values of the keys in SELECT_KEYS along with the file path.
# $1: path to file to process
print_on_match() {
  if content "$1" | grep -Eiq "$SELECT_REGEX"; then
    # For all keys to show, extract their value and print them tab separated,
    for key in $SELECT_KEYS; do
      value=$(keyval "$key" "$1")
      printf '%s\t' "$value"
    done
    # End with the file path itself
    printf '%s' "$1"
    printf '\n'
  else
    trace "File %s does not match regex %s, skipping" "$1" "$SELECT_REGEX"
  fi
}

# Default to current directory if no path provided
if [ "$#" -eq 0 ]; then
  set -- "."
fi

# When no keys to show are provided, use the same as the keys to filter on.
[ -z "$SELECT_KEYS" ] && SELECT_KEYS=$SELECT_WHERE


# Process all provided paths, which can be directories, files, or "-" for stdin.
for path; do
  if [ -d "$path" ]; then
    info "Processing directory %s" "$path"
    if [ -z "$SELECT_QUICK" ]; then
      find "$path" -type f -name "$SELECT_PATTERN" | while read -r file; do
        print_on_match "$file"
      done
    else
      narrow "$path" | while read -r file; do
        print_on_match "$file"
      done
    fi
  elif [ -f "$path" ]; then
    info "Processing file %s" "$path"
    print_on_match "$path"
  elif [ "$path" = "-" ]; then
    info "Processing stdin"
    _content=$(mktemp)
    cat > "$_content"
    print_on_match "$_content"
    rm -f "$_content"
  else
    error "Provided path %s is not a directory, nor a file, nor a -" "$path"
  fi
done
