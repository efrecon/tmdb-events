#!/bin/sh


set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Root directory where this script is located
: "${ORIGIN_ROOTDIR:="$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )"}"

# Location of the dump and filter scripts
: "${ORIGIN_DUMP:="${ORIGIN_ROOTDIR%//}/dump.sh"}"
: "${ORIGIN_FILTER:="${ORIGIN_ROOTDIR%//}/filter.sh"}"

# Root directory for downloaded data
: "${ORIGIN_DATA_ROOT:="${ORIGIN_ROOTDIR}/data"}"

# Languages to dump.
: "${ORIGIN_LANGUAGE:="fr-FR sv-SV"}"

# Verbosity level, can be increased with -v option
: "${ORIGIN_VERBOSE:=0}"

usage() {
  # This uses the comments behind the options to show the help. Not extremely
  # correct, but effective and simple.
  echo "$0 dumps TMDB content originating from one or several languages." && \
    grep "[[:space:]].)[[:space:]][[:space:]]*#" "$0" |
    sed 's/#//' |
    sed -E 's/([a-zA-Z-])\)/-\1/'
  printf \\nEnvironment:\\n
  set | grep '^ORIGIN_' | sed 's/^ORIGIN_/    ORIGIN_/g'
  exit "${1:-0}"
}

# Parse named arguments using getopts
while getopts ":f:k:l:s:r:vh-" opt; do
  case "$opt" in
    l) # Languages for results
      ORIGIN_LANGUAGE=$OPTARG;;
    r) # Root directory for dumped data. Will contain one sub per language, then one sub per type.
      ORIGIN_DATA_ROOT=$OPTARG;;
    v) # Increase verbosity each time repeated
      ORIGIN_VERBOSE=$(( ORIGIN_VERBOSE + 1 ));;
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
trace() { [ "$ORIGIN_VERBOSE" -ge "2" ] && _log DBG "$@" || true ; }
info() { [ "$ORIGIN_VERBOSE" -ge "1" ] && _log NFO "$@" || true ; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }


# Silence the command passed as an argument.
silent() { "$@" >/dev/null 2>&1 </dev/null; }


[ -x "$ORIGIN_DUMP" ] || error "Dump script not found or not executable: %s" "$ORIGIN_DUMP"
[ -x "$ORIGIN_FILTER" ] || error "Filter script not found or not executable: %s" "$ORIGIN_FILTER"

get_country() {
  case "$1" in
    fr-FR)
      country="france|belgique|suisse|luxembourg"
      ;;
    *)
      _sed=$(mktemp)
      cat <<EOF >"$_sed"
# Mappings for specific codes (language-country)
s/de-DE/Deutschland/g
s/fr-FR/France/g
s/en-US/United States/g
s/en-GB/United Kingdom/g
s/es-ES/España/g
s/it-IT/Italia/g
s/pt-PT/Portugal/g
s/pt-BR/Brasil/g
s/ja-JP/日本/g
s/zh-CN/中国/g
s/ru-RU/Россия/g
s/nl-NL/Nederland/g
s/sv-SE/Sverige/g
s/fi-FI/Suomi/g
s/pl-PL/Polska/g
s/dk-DK/Danmark/g
s/no-NO/Norge/g
s/is-IS/Ísland/g
s/tr-TR/Türkiye/g
s/gr-GR/Ελλάδα/g
s/hu-HU/Magyarország/g
s/cz-CZ/Česko/g
s/sk-SK/Slovensko/g
s/hr-HR/Hrvatska/g
s/ua-UA/Україна/g
s/in-HI/भारत/g
s/th-TH/ไทย/g
s/vn-VN/Việt Nam/g
s/id-ID/Indonesia/g
# Add simple language code fallbacks if needed, placed after specific codes
s/de/Deutschland/g
s/fr/France/g
s/en/United States/g
s/es/España/g
s/it/Italia/g
s/pt/Portugal/g
s/ja/日本/g
s/zh/中国/g
s/ru/Россия/g
s/nl/Nederland/g
s/sv/Sverige/g
s/fi/Suomi/g
s/pl/Polska/g
s/dk/Danmark/g
s/no/Norge/g
s/is/Ísland/g
s/tr/Türkiye/g
s/gr/Ελλάδα/g
s/hu/Magyarország/g
s/cz/Česko/g
s/sk/Slovensko/g
s/hr/Hrvatska/g
s/ua/Україна/g
s/in/भारत/g
s/th/ไทย/g
s/vn/Việt Nam/g
s/id/Indonesia/g
EOF
      country=$(printf '%s\n' "$1" | sed -f "$_sed")
      rm -f "$_sed"
      if printf "%s" "$country" | grep -qE '^[a-z]{2}(-\w{2})?$'; then
        warn "Could not map language code %s to a country name, skipping" "$1"
        country=""
      else
        info "Mapped language code %s to country name %s" "$1" "$country"
      fi
      ;;
  esac
  printf '%s' "$country"
}

get_language() {
  _sed=$(mktemp)
cat <<EOF >"$_sed"
# Mappings for common 2-letter language codes to their native names
s/\ben(-\w{2})?/English/g
s/\bfr(-\w{2})?/Français/g
s/\bde(-\w{2})?/Deutsch/g
s/\bes(-\w{2})?/Español/g
s/\bit(-\w{2})?/Italiano/g
s/\bpt(-\w{2})?/Português/g
s/\bja(-\w{2})?/日本語/g
s/\bzh(-\w{2})?/中文/g
s/\bru(-\w{2})?/Русский язык/g
s/\bnl(-\w{2})?/Nederlands/g
s/\bsv(-\w{2})?/Svenska/g
s/\bfi(-\w{2})?/Suomi/g
s/\bpl(-\w{2})?/Polski/g
s/\bda(-\w{2})?/Dansk/g
s/\bno(-\w{2})?/Norsk/g
s/\bis(-\w{2})?/Íslenska/g
s/\btr(-\w{2})?/Türkçe/g
s/\bel(-\w{2})?/Ελληνικά/g
s/\bhu(-\w{2})?/Magyar/g
s/\bcs(-\w{2})?/Čeština/g
s/\bsk(-\w{2})?/Slovenčina/g
s/\bhr(-\w{2})?/Hrvatski/g
s/\buk(-\w{2})?/Українська/g
s/\bhi(-\w{2})?/हिन्दी/g
s/\bth(-\w{2})?/ไทย/g
s/\bvi(-\w{2})?/Việt Nam/g
s/\bhe(-\w{2})?/עברית/g
s/\bar(-\w{2})?/العربية/g
EOF
  language=$(printf '%s\n' "$1" | sed -E -f "$_sed")
  rm -f "$_sed"
  if printf "%s" "$language" | grep -qE '^[a-z]{2}(-\w{2})?$'; then
    warn "Could not map language code %s to a country name, skipping" "$1"
    language=""
  else
    info "Mapped language code %s to language %s" "$1" "$language"
  fi
  printf '%s' "$language"
}


for type; do
  for code in $ORIGIN_LANGUAGE; do
    printf "%s" "$code" | grep -qE '^[a-z]{2}(-\w{2})?$' || \
      error "Invalid language code format: %s" "$code"
    case "$type" in
      person|network|company)
        # Set the JSON key to filter on dependeing on the type
        FILTER_KEYS=".origin_country"
        [ "$type" = "person" ] && FILTER_KEYS=".place_of_birth"

        # Match the content on the country extracted from the language code
        country=$(get_country "$code")
        if [ -n "$country" ]; then
          FILTER_REGEX="($country)"
        else
          warn "No country found for code %s, skipping dump" "$code"
          continue
        fi
        ;;
      movie|tv|collection)
        # Set the JSON key to filter on dependeing on the type
        FILTER_KEYS=".original_language"

        # Match the content on the language extracted from the language code.
        # Language is the original language here, not the name of the language
        # in English.
        lang=$(get_language "$code" | tr '|' ', ')
        if [ -n "$lang" ]; then
          FILTER_REGEX="($lang)"
        else
          warn "No language found for code %s, skipping dump" "$code"
          continue
        fi
        ;;
      *)
        error "Dumping type %s not yet supported" "$type";;
    esac
    export FILTER_KEYS FILTER_REGEX
    info "Dumping data for language %s with filter regex %s on keys" "$code" "$FILTER_REGEX" "$FILTER_KEYS"
    FILTER_VERBOSE=$ORIGIN_VERBOSE \
    TMDB_VERBOSE=$ORIGIN_VERBOSE \
      "$ORIGIN_DUMP" \
        -l "$code" \
        -r "${ORIGIN_DATA_ROOT%%/}" \
        -f "$ORIGIN_FILTER" \
          -- \
            "$type"
  done
done