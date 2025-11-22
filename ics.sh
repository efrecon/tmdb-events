#!/bin/sh


set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Root directory where this script is located
: "${ICS_ROOTDIR:="$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )"}"

# Root directory for downloaded data
: "${ICS_DATA_ROOT:="${ICS_ROOTDIR}/data"}"

# Path to show.sh script to extract keys from content. Defaults to show.sh in
# the same directory as this script.
: "${ICS_SHOW:="${ICS_ROOTDIR%//}/show.sh"}"

# Path to select.sh script to find persons.
: "${ICS_SELECT:="${ICS_ROOTDIR%//}/select.sh"}"

# Number of days around today to include in the calendar. Default is 7 (one week
# before and one week after today). When empty, the entire year is included.
: "${ICS_DAYS:="7"}"

# Language for entries in the calendar. This should match the language used in
# the data files, so used when running dump.sh. When empty, no language will be
# set, this is the default.
: "${ICS_LANGUAGE:=""}"

# Verbosity level, can be increased with -v option
: "${ICS_VERBOSE:=0}"

usage() {
  # This uses the comments behind the options to show the help. Not extremely
  # correct, but effective and simple.
  echo "$0 saves relevant TMDB entity to disk" && \
    grep "[[:space:]].)[[:space:]][[:space:]]*#" "$0" |
    sed 's/#//' |
    sed -E 's/([a-zA-Z-])\)/-\1/'
  printf \\nEnvironment:\\n
  set | grep '^ICS_' | sed 's/^ICS_/    ICS_/g'
  exit "${1:-0}"
}

# Parse named arguments using getopts
while getopts ":d:l:vh-" opt; do
  case "$opt" in
    d) # Number of days around today to include in the calendar. Empty means entire year.
      ICS_DAYS=$OPTARG;;
    l) # Language for entries in the calendar
      ICS_LANGUAGE=$OPTARG;;
    v) # Increase verbosity each time repeated
      ICS_VERBOSE=$(( ICS_VERBOSE + 1 ));;
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
trace() { [ "$ICS_VERBOSE" -ge "2" ] && _log DBG "$@" || true ; }
info() { [ "$ICS_VERBOSE" -ge "1" ] && _log NFO "$@" || true ; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }


# Output a list of dates around a given date.
# $1: span in days
# $2: center date in a format recognized by -d, defaults to now
# $3: output date format, defaults to "%Y-%m-%d"
date_span() {
  # Default to now if no date given
  [ -z "${2:-}" ] && set -- "$1" "$(date -u +'%Y-%m-%d %H:%M:%S')"

  # Compute the "center" of the date span in seconds since epoch
  _now=$(date -u -d "$2" +%s)
  # Pick the span from the parameters.
  _span=$1
  # Compute the start date in seconds since epoch
  _start=$(( _now - _span * 86400 ))
  # How many days to output, i.e. the days before and after the center date,
  # including the center date.
  _days=$(( 1 + _span * 2))
  date_interval $_days "@$_start" "${3:-}"
}


# Output a list of dates starting from a given date.
# $1: number of days to output
# $2: start date in a format recognized by -d, defaults to now
# $3: output date format, defaults to "%Y-%m-%d"
date_interval() {
  # Default to now if no date given
  [ -z "${2:-}" ] && set -- "$1" "$(date -u +'%Y-%m-%d %H:%M:%S')"

  # Compute the start of the interval in seconds since epoch
  _secs=$(date -u -d "$2" +%s)
  # Output the dates in YYYY-MM-DD format
  for i in $(seq 1 $1); do
    date -u -d "@$_secs" +"${3:-"%Y-%m-%d"}"
    _secs=$(( _secs + 86400 ))
  done
}


# Pick the most popular person born on a given month-day.
# $1: month-day in MM-DD format
most_popular_person() {
  birthday=$1
  info "Picking most popular person born on %s" "$1"
  "$ICS_SELECT" \
    -k 'popularity' \
    -w 'birthday' \
    -q "$1" \
    -r "${1}\$" \
      -- \
        ${ICS_DATA_ROOT%%/}/person |
      sort -k 1 -g -r |
      head -n 1 |
      cut -f2
}


ics_line_endings() { tr -d '\r' | sed 's/$/\r/'; }

ics_localized() {
  if [ -n "$ICS_LANGUAGE" ]; then
    printf '%s;LANGUAGE=%s' "$1" "$ICS_LANGUAGE"
  else
    printf '%s' "$1" "$ICS_LANGUAGE"
  fi
}


# Generate an ICS entry language parameter if a language is provided.
# $1: language code
ics_language() { [ -n "$1" ] && printf ';LANGUAGE:%s' "$1"; }


# Output ICS header
ics_header() {
  cat <<EOF
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//themoviedb.org//TMDB Birthdays//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
X-WR-CALNAME:TMDB Birthdays
X-WR-CALDESC:Birthdays of popular persons from The Movie Database (TMDB)
EOF
}


# Output ICS footer
ics_footer() {
  cat <<EOF
END:VCALENDAR
EOF
}

ics_fold() { fold -s -w 74 | sed 's/^/ /; 1s/^ //'; }

# Output an ICS entry for a given person file. Content will be pinpointed to the
# language if provided.
# $1: path to person file
ics_entry() {
  # Collect person data using the show.sh script. For the description, we keep
  # only the first sentence of the first line.
  info "Collecting person data from %s" "$1"
  birthday=$("$ICS_SHOW" -k 'birthday' -- "$1")
  id=$("$ICS_SHOW" -k 'id' -- "$1")
  name=$("$ICS_SHOW" -k 'name' -- "$1")
  bio=$("$ICS_SHOW" -k 'biography' -- "$1" |
        head -n 1 |
        sed 's/\([^.!?]*[.!?]\).*/\1/')

  # Extract month and day from birthday to setup the yearly recurrence and when
  # the event starts and stops.
  month=$(date -u -d "$birthday" +%m)
  day=$(date -u -d "$birthday" +%d)
  today="$(date -u +%Y)-$month-$day 12:00:00"
  tomorrow=$(date_span 1 "$today" "%Y-%m-%d %H:%M:%S" | tail -n1)

  # Generate the ICS entry
  cat <<EOF
BEGIN:VEVENT
CLASS:PUBLIC
UID:$(date -u -d "$today" +'%Y%m%d')-person-${id}@themoviedb.org
DTSTAMP:$(date -u +'%Y%m%dT%H%M%SZ')
DTSTART;VALUE=DATE:$(date -u -d "$today" +'%Y%m%d')
RRULE:FREQ=YEARLY;INTERVAL=1;BYMONTH=$month;BYMONTHDAY=$day
X-MICROSOFT-CDO-ALLDAYEVENT:TRUE
$(printf '%s:%s (%s)' "$(ics_localized "SUMMARY")" "$name" "$birthday" | ics_fold)
$(printf '%s:%s' "$(ics_localized "DESCRIPTION")" "$bio" | ics_fold)
URL:https://www.themoviedb.org/person/${id}
STATUS:CONFIRMED
END:VEVENT
EOF
}


# Output ICS entries for all persons born on the given dates. Dates are read
# from stdin, one per line in YYYY-MM-DD format, as typically output by
# date_span or date_interval.
ics_entries() {
  while read -r d; do
    birthday=$(date -d "$d" +%m-%d)
    path=$(most_popular_person "$birthday")
    [ -n "$path" ] && ics_entry "$path"
  done
}


# Silence the command passed as an argument.
silent() { "$@" >/dev/null 2>&1 </dev/null; }



# Verify required commands are available
silent command -v fold || error "fold command not found"


if [ -n "$ICS_DAYS" ] && [ "$ICS_DAYS" -gt 0 ]; then
  {
    ics_header
    date_span "$ICS_DAYS" | ics_entries
    ics_footer
  } | ics_line_endings
else
  {
    ics_header
    year=$(date +%Y)
    date_interval 365 "${year}-01-01 00:00:00" | ics_entries
    ics_footer
  } | ics_line_endings
fi
