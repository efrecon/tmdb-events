# TMDB Filtering and Analysis

The ultimate goal of this project is to generate [iCalendar] files with one-day events for selected celebrities.
The project contains a series of POSIX shell scripts to collect and select data, and then generate calendars.
Information is collected from data at [the Movie DB][tmdb].
You will need to [request] for API key if you want to run those scripts by yourself.
Available online is only a [calendar][person-fr] in French, with celebrities related to France.
This calendar is re-generated twice a week and contains one-day events for 10 days before and 10 days after the generation date.
Regeneration uses a one-time [dump](#automated) of a selected subset from [TMDB][tmdb].

While the purpose is generating calendars, scripts from this project are able to collect information about:
persons, movies, TV series, collections, TV networks, Companies.
Language for the output can be changed from the command-line.
[TMDB][tmdb] contains [millions] of entries.
Scripts such as [byorigin](#automated) or [dump](#dump-persons-names-and-bio) will restrict the subset saved to disk.

I made this to break the uniformity of life for my mum.
She lives in a elderly care house and this information will be picked and shown on eInk display.

  [iCalendar]: https://icalendar.org/
  [tmdb]: https://themovie.db/
  [request]: https://developer.themoviedb.org/docs/faq#how-do-i-apply-for-an-api-key
  [person-fr]: https://efrecon.github.io/tmdb-events/fr-FR/person.ics
  [millions]: https://developer.themoviedb.org/docs/daily-id-exports

## Calendars

Calenders are automatically generated for French-born person at the following locations.

- [fr-FR](https://efrecon.github.io/tmdb-events/fr-FR/person.ics)

## Running

Create an API key.
Set the `TMDB_KEY` environment variable to the content of the API key.
Using the key for reading from the DB is enough.
**Note**: the key below is invalid, it is here for demonstration purposes only.

```bash
# API key to TMDB
TMDB_KEY=eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiIyZGJiN2Q0NWVkYjNiMWE1ZjdiZTNhZjRjOTE0NDJmMyIsIm5iZiI6MTc2Mzc0MDczNS4xNzUsInN1YiI6IjY5MjA4YzNmY2FjOTUxY2ZhYjVkNjM0OCIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.O2KdtTsUWvK2AUCAXPe33PklbRkm_GNk3lV4Wx_mYn0
export TMDB_KEY
```

## Examples

### Dumping the Entire TMDB

To dump the entire TMDB knowledge about an entity type, e.g. `person` run a command similar to the following.
This **is** a lengthy operation.
Some care is taken as to not bump into rate limiting issues.
Note that this changes the output language to french as an example, the default is `en-US`.

```bash
./dump.sh -l fr-FR -v -- person
```

### Filtering a Dump

#### Manual

##### Select French-related persons

To only dump persons that mention a french relation in their biography and place of birth, use a command as below.
This uses the [`filter.sh`](./filter.sh) to keep only persons that match the regular expression in their biography or place of birth.

```bash
FILTER_KEYS=".biography .place_of_birth"
FILTER_REGEX="(français|francais|french|france)"
export FILTER_KEYS FILTER_REGEX

./dump.sh -l fr-FR -f "./filter.sh -v" -- person
```

##### Select people born in France and around

To only dump persons born in France and French-speaking countries nearby, do as follows instead.

```bash
FILTER_KEYS=".place_of_birth"
FILTER_REGEX="(france|belgique|suisse|luxembourg)"
export FILTER_KEYS FILTER_REGEX

./dump.sh -l fr-FR -f "./filter.sh -v" -- person
```

#### Automated

Automatically originating TMDB entities to their origing can be automated through `byorigin.sh` instead.
To only dump persons born in France and French-speaking countries nearby, do as follows instead.
This will resolve the locale to a relevant filter -- same as above for France,
and then run `dump.sh` using that filter.
`byorigin.sh` is able to take several locales and several types.
Note that this is a **lengthy** -- several hours -- operation,
as it needs to download the entire database for each pass.

```bash
./byorigin.sh -l fr-FR -v -- person
```

### Extract Results

Extracting results can be done through the [`show.sh`](./show.sh).
Internally, this is how [`filter.sh`](./filter.sh) dumps data out of downloaded JSON files for entities.

#### Dump Identifiers

Generated JSON files are named after the identifiers of the entities.
However, the following command will actively look for the id in all files in a directory resulting from above:

```bash
./show.sh -k 'id' -- ./data/person
```

#### Dump Person's names and bio

```bash
./show.sh -k 'name biography' -- ./data/person
```

#### Update Current Set

You can actualize your current set using a command similar to the one below.
This will request again data for all already known persons.
Note that these commands pinpoint the data directory for input and output on purpose to avoid mistakes.

```bash
./show.sh -k 'id' -- ./data/person | ./dump.sh -l fr-FR -v -r ./data -- person
```

### Searching for matching data

#### All persons born today

This uses the [`select.sh`](./select.sh) tool.
It will search for entities that match one or several keys.
The content of the keys will be matched against the same regular expression.
The default is to print the value for the keys, together with the path to the file (tabulated).

The example below would print all known persons born on the same day as today, and their birthdate.
This works because the default is to print the keys that are used for the match.

```bash
./select.sh -w 'birthday' -r "$(date +'%m-%d')\$" -- ./data/person
```

Selecting from a directory can be slow because it has to read all files from that directory and extract the value of the JSON keys for all files.
You can apply a pre-filter that enforces the **textual** content to match a regular expression before selecting.
In most cases, this pre-filter should be something that is very similar to regular expression to match, but without begin/end of string/line markers.

```bash
./select.sh -w 'birthday' -q "$(date +'%m-%d')" -r "$(date +'%m-%d')\$" -- ./data/person
```

#### Most popular person born today

The following command would show the most popular person born today.
It works by requesting to show other keys, led by the popularity and sorting on that popularity score as a numerical value.

```bash
./select.sh -k 'popularity birthday name' -q "$(date +'%m-%d')" -w 'birthday' -r "$(date +'%m-%d')\$" -- ./data/person |
  sort -k 1 -g -r |
  head -n 1
```

## TODO

+ Remove files where the biography is empty?
