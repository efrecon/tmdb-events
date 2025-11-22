#!/bin/sh


set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi


# Pattern to match files to process in directories, e.g. "*.json"
: "${SHOW_PATTERN:="*.json"}"

# List of keys to extract from each file, space separated. Empty means all keys,
# e.g. .biography .date_of_birth. Leading dot is optional.
: "${SHOW_KEYS:=".id"}"

# Lines matching this regex will be removed from the content before showing the
# values of the keys. Default is to remove null values.
: "${SHOW_CLEAN:="^null$"}"

# Verbosity level, can be increased with -v option
: "${SHOW_VERBOSE:=0}"

usage() {
  # This uses the comments behind the options to show the help. Not extremely
  # correct, but effective and simple.
  echo "$0 actively picks and list ids from TMDB entities in directory" && \
    grep "[[:space:]].)[[:space:]][[:space:]]*#" "$0" |
    sed 's/#//' |
    sed -E 's/([a-zA-Z-])\)/-\1/'
  printf \\nEnvironment:\\n
  set | grep '^SHOW_' | sed 's/^SHOW_/    SHOW_/g'
  exit "${1:-0}"
}

# Parse named arguments using getopts
while getopts ":k:vh-" opt; do
  case "$opt" in
    k) # List of keys to extract from each file, space separated.
      SHOW_KEYS=$OPTARG;;
    c) # Lines matching this regex will be removed from the content before testing the keys
      SHOW_CLEAN=$OPTARG;;
    v) # Increase verbosity each time repeated
      SHOW_VERBOSE=$(( SHOW_VERBOSE + 1 ));;
    h) # Show this help
      usage 0;;
    -) # Takes name of directory as argument
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
trace() { [ "$SHOW_VERBOSE" -ge "2" ] && _log DBG "$@" || true ; }
info() { [ "$SHOW_VERBOSE" -ge "1" ] && _log NFO "$@" || true ; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }


# Silence the command passed as an argument.
silent() { "$@" >/dev/null 2>&1 </dev/null; }

# Extract key and clean its content
# $1: jq key to extract
# $2: path to file where to extract the key from
content() {
  if [ -z "$SHOW_CLEAN" ]; then
    jq -r ".${1##.}" "$2"
  else
    jq -r ".${1##.}" "$2" | grep -vE "$SHOW_CLEAN"
  fi
}


# Print values of keys from given file
# $1: path to file to process
print_keys() {
  # When no keys are provided, pick all keys. Generate a list using jq which is
  # in the same expected format as for the -k option. This is a bit expensive as
  # we need to do thie on every file (no guarantee that all files have the same
  # keys).
  if [ -z "$SHOW_KEYS" ]; then
    _key_list=$(jq -r 'keys | map("." + .) | join(" ")' "$_content")
    trace "No SHOW_KEYS set, using all keys: %s" "$_key_list"
  else
    _key_list=$SHOW_KEYS
  fi

  for key in $_key_list; do
    content "$key" "$1"
  done
}


# Verify required commands are available
silent command -v jq || error "jq command not found"

# Default to current directory if no path provided
if [ "$#" -eq 0 ]; then
  set -- "."
fi

for path; do
  if [ -d "$path" ]; then
    info "Processing directory %s" "$path"
    find "${1:-.}" -type f -name "$SHOW_PATTERN" | while read -r file; do
      print_keys "$file"
    done
  elif [ -f "$path" ]; then
    info "Processing file %s" "$path"
    print_keys "$path"
  elif [ "$path" = "-" ]; then
    info "Processing stdin"
    _content=$(mktemp)
    cat > "$_content"
    print_keys "$_content"
    rm -f "$_content"
  else
    error "Provided path %s is not a directory, nor a file, nor a -" "$path"
  fi
done
