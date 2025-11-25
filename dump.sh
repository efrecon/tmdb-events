#!/bin/sh


set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Root directory where this script is located
: "${TMDB_ROOTDIR:="$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )"}"

# API key (read).
: "${TMDB_KEY:=""}"

# Language for results.
: "${TMDB_LANGUAGE:="en-US"}"

# Root directory for downloaded data
: "${TMDB_DATA_ROOT:="${TMDB_ROOTDIR}/data"}"

# After how many requests to pause (avoid rate limiting)
: "${TMDB_PAUSE:="40"}"

# Filter to pass the content to. Content will be piped to this command,
# destination filename will be passed as argument.
: "${TMDB_FILTER:=""}"

# Pause duration in seconds
: "${TMDB_SLEEP:="1"}"

# Base URL for TMDB exports. Set to "-" to read IDs from stdin, one per line.
: "${TMDB_EXPORTS:="https://files.tmdb.org/p/exports/"}"

# Verbosity level, can be increased with -v option
: "${TMDB_VERBOSE:=0}"

usage() {
  # This uses the comments behind the options to show the help. Not extremely
  # correct, but effective and simple.
  echo "$0 dumps TMDB content to disk." && \
    grep "[[:space:]].)[[:space:]][[:space:]]*#" "$0" |
    sed 's/#//' |
    sed -E 's/([a-zA-Z-])\)/-\1/'
  printf \\nEnvironment:\\n
  set | grep '^TMDB_' | sed 's/^TMDB_/    TMDB_/g'
  exit "${1:-0}"
}

# Parse named arguments using getopts
while getopts ":f:k:l:s:r:vh-" opt; do
  case "$opt" in
    k) # API key, at least read permissions
      TMDB_KEY=$OPTARG;;
    l) # Language for results
      TMDB_LANGUAGE=$OPTARG;;
    r) # Root directory for dumped data. Will contain one sub per language, then one sub per type.
      TMDB_DATA_ROOT=$OPTARG;;
    s) # How long to pause (in seconds) after $TMDB_PAUSE requests
      TMDB_SLEEP=$OPTARG;;
    f) # Filter to pass the content to
      TMDB_FILTER=$OPTARG;;
    x) # Base URL for TMDB exports. Set to "-" to read IDs from stdin, one per line.
      TMDB_EXPORTS=$OPTARG;;
    v) # Increase verbosity each time repeated
      TMDB_VERBOSE=$(( TMDB_VERBOSE + 1 ));;
    h) # Show this help
      usage 0;;
    -) # Any argument after -- is a known type of data to dump. Recognized: person, movie, tv, collection, network, company
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
trace() { [ "$TMDB_VERBOSE" -ge "2" ] && _log DBG "$@" || true ; }
info() { [ "$TMDB_VERBOSE" -ge "1" ] && _log NFO "$@" || true ; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }


# Silence the command passed as an argument.
silent() { "$@" >/dev/null 2>&1 </dev/null; }


# Silently download a file using curl
# $1: URL
# $2: output file (optional, default: basename of URL)
download() { run_curl -o "${2:-$(basename "$1")}" "$1"; }


# Wrapper around curl to add common options
# $@: curl arguments
run_curl() {
  curl -fsSL --retry 5 --retry-delay 3 "$@"
}

api_curl() {
  run_curl --header "Authorization: Bearer $TMDB_KEY" --url "https://api.themoviedb.org/3/${1}?language=${TMDB_LANGUAGE}"
}

list_all() {
  if [ -n "$TMDB_EXPORTS" ] && [ "$TMDB_EXPORTS" != "-" ]; then
    _dump_date=$(date -d 'yesterday' +%m_%d_%Y)
    info "Listing all IDs for type %s at %s" "$1" "$_dump_date"

    # Convert from (API) type to export type
    types=$( printf '%s\n' "$1" | sed 's/person/person/g; s/movie/movie/g; s/tv/tv_series/g; s/collection/collection/g; s/network/tv_network/g; s/keyword/keyword/g; s/company/production_company/g' )
    download "${TMDB_EXPORTS%%/}/${types}_ids_${_dump_date}.json.gz" - |
      gunzip |
      grep -Eo '"id":[[:space:]]*([0-9]+),' |
      grep -Eo '[0-9]+'
  else
    info "Picking IDs for type %s from stdin" "$1"
    cat -
  fi
}

dump() {
  if [ -n "$TMDB_FILTER" ] && [ "$TMDB_FILTER" != "-" ]; then
    trace "Filtering and dumping ID ${1}"
    api_curl "${type}/${1}" | $TMDB_FILTER "${TMDB_DATA_DIR}/${1}.json" || warn "Failed to dump ${type} ID ${1}"
  else
    trace "Dumping ID ${1}"
    api_curl "${type}/${1}" > "${TMDB_DATA_DIR}/${1}.json" || warn "Failed to dump ${type} ID ${1}"
  fi
}


silent command -v curl || error "curl command not found"
silent command -v gunzip || error "gunzip command not found"
printf "%s" "$TMDB_LANGUAGE" | grep -qE '^[a-z]{2}(-\w{2})?$' || \
  error "Invalid language code format: %s" "$TMDB_LANGUAGE"

for type; do
  case "$type" in
    person|movie|tv|collection|network|keyword|company)
      # Create dump directory named after the type under the root, if needed.
      TMDB_DATA_DIR="${TMDB_DATA_ROOT}/${TMDB_LANGUAGE}/${type}"
      if ! [ -d "$TMDB_DATA_DIR" ]; then
        info "Creating dump directory for language %s: %s" "$TMDB_LANGUAGE" "$TMDB_DATA_DIR"
        mkdir -p "${TMDB_DATA_DIR}"
      fi

      _req=$TMDB_PAUSE
      list_all "$type" | while IFS= read -r _id; do
        # Dump the content, perform filtering if requested
        dump "$_id"

        # Count requests and pause if needed
        _req=$(( _req - 1 ))
        if [ "$_req" -le 0 ] && [ "$TMDB_SLEEP" -gt 0 ]; then
          trace "Pausing for %s seconds to avoid rate limiting..." "$TMDB_SLEEP"
          sleep "$TMDB_SLEEP"
          _req=$TMDB_PAUSE
        fi
      done
      ;;
    *)
      warn "Unknown dump type: %s. Recognized: person, movie, tv, collection, network, keyword, company" "$type"
      ;;
  esac
done
