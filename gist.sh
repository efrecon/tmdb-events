#!/bin/sh


set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Root directory where this script is located
: "${GIST_ROOTDIR:="$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )"}"

# Classic PAT token with gist write access.
: "${GIST_TOKEN:=""}"

# Pattern to match files to process in directories, e.g. "*.json"
: "${GIST_PATTERN:="*.json"}"

# Language of results.
: "${GIST_LANGUAGE:="en-US"}"

# Description for the gist, Empty for a good default based on path and language.
: "${GIST_DESCRIPTION:=""}"

# Make the gist public. Default is private (false).
: "${GIST_PUBLIC:="0"}"

# Root directory for downloaded data
: "${GIST_DATA_ROOT:="${GIST_ROOTDIR}/data"}"

# Verbosity level, can be increased with -v option
: "${GIST_VERBOSE:=0}"

usage() {
  # This uses the comments behind the options to show the help. Not extremely
  # correct, but effective and simple.
  echo "$0 upload TMDB dump to a gist." && \
    grep "[[:space:]].)[[:space:]][[:space:]]*#" "$0" |
    sed 's/#//' |
    sed -E 's/([a-zA-Z-])\)/-\1/'
  printf \\nEnvironment:\\n
  set | grep '^GIST_' | sed 's/^GIST_/    GIST_/g'
  exit "${1:-0}"
}

# Parse named arguments using getopts
while getopts ":d:l:pt:vh-" opt; do
  case "$opt" in
    t) # GitHub PAT token with gist write access
      GIST_TOKEN=$OPTARG;;
    l) # Language of results
      GIST_LANGUAGE=$OPTARG;;
    d) # Description for the gist
      GIST_DESCRIPTION=$OPTARG;;
    p) # Make the gist public
      GIST_PUBLIC="1";;
    v) # Increase verbosity each time repeated
      GIST_VERBOSE=$(( GIST_VERBOSE + 1 ));;
    h) # Show this help
      usage 0;;
    -) # Any argument after -- is a known type of data to push as a base64 encoded compressed archive.
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
trace() { [ "$GIST_VERBOSE" -ge "2" ] && _log DBG "$@" || true ; }
info() { [ "$GIST_VERBOSE" -ge "1" ] && _log NFO "$@" || true ; }
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
  _api=${1##/}; shift
  run_curl --header "Authorization: Token $GIST_TOKEN" --url "https://api.github.com/$_api" "$@"
}


silent command -v curl || error "curl command not found"
printf "%s" "$GIST_LANGUAGE" | grep -qE '^[a-z]{2}(-\w{2})?$' || \
  error "Invalid language code format: %s" "$GIST_LANGUAGE"

if [ "$GIST_PUBLIC" = "1" ]; then
  GIST_PUBLIC_JSON="true"
else
  GIST_PUBLIC_JSON="false"
fi

for type; do
  case "$type" in
    person|movie|tv|collection|network|keyword|company)
      path="${GIST_DATA_ROOT%//}/${GIST_LANGUAGE}/${type}"
      if [ ! -d "$path" ]; then
        warn "Data path %s for type %s does not exist, skipping" "$path" "$type"
        continue
      fi

      _desc=$GIST_DESCRIPTION
      [ -z "$_desc" ] && _desc="TMDB dump for $type in ${GIST_LANGUAGE}"
      fname=${type}-${GIST_LANGUAGE}.tgz.b64
      info "Compressing content of %s to upload to gist" "$path"
      b64=$(  ( cd "$path" && find . -maxdepth 1 -type f -name "$GIST_PATTERN" ) |
              sort -g |
              xargs tar -C "$path" -czf - |
              base64 -w 0 )
      info "Uploading gist for %s as %s" "$path" "$fname"
      api_curl /gists -X POST -d @- <<EOF
{
  "description": "$_desc",
  "public": $GIST_PUBLIC_JSON,
  "files": {
    "$fname": {
      "content": "$b64"
    }
  }
}
EOF

      ;;  
    *)
      warn "Unknown dump type: %s. Recognized: person, movie, tv, collection, network, keyword, company" "$type"
      ;;
  esac
done
