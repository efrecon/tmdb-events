# TMDB Filtering

## Running

Create an API key. Set the `TMDB_KEY` environment variable to the content of the
API key. Using the key for reading from the DB is enough. Note: the key below is
invalid, it is here for demonstration purposes.

```bash
# API key to TMDB
TMDB_KEY=eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiIyZGJiN2Q0NWVkYjNiMWE1ZjdiZTNhZjRjOTE0NDJmMyIsIm5iZiI6MTc2Mzc0MDczNS4xNzUsInN1YiI6IjY5MjA4YzNmY2FjOTUxY2ZhYjVkNjM0OCIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.O2KdtTsUWvK2AUCAXPe33PklbRkm_GNk3lV4Wx_mYn0
export TMDB_KEY
```

## Examples

### Dumping the Entire TMDB

To dump the entire TMDB knowledge about an entity type, e.g. `person` run a
command similar to the following. Note that this changes the output language to
french as an example, the default is `en-US`.

```bash
./dump.sh -l fr-FR -v -- person
```

### Filtering a Dump

#### Select French-related persons

To only dump persons that mention a french relation in their biography and place
of birth, use a command as below. This uses the [`filter.sh`](./filter.sh) to
keep only persons that match the regular expression in their biography or place
of birth.

```bash
FILTER_KEYS=".biography .place_of_birth"
FILTER_REGEX="(français|francais|french|france)"
export FILTER_KEYS FILTER_REGEX

./dump.sh -l fr-FR -f "./filter.sh -v" -- person
```

#### Select people born in France and around

To only dump persons born in France and French-speaking countries nearby, do as
follows instead.

```bash
FILTER_KEYS=".place_of_birth"
FILTER_REGEX="(france|belgique|suisse|luxembourg)"
export FILTER_KEYS FILTER_REGEX

./dump.sh -l fr-FR -f "./filter.sh -v" -- person
```

### Extract Results

Extracting results can be done through the [`show.sh`](./show.sh). Internally,
this is how [`filter.sh`](./filter.sh) dumps data out of downloaded JSON files
for entities.

#### Dump Identifiers

Generated JSON files are named after the identifiers of the entities. However,
the following command will actively look for the id in all files in a directory
resulting from above:

```bash
./show.sh -k 'id' -- ./data/person
```

#### Dump Person's names and bio

```bash
./show.sh -k 'name biography' -- ./data/person
```

#### Update Current Set

You can actualize your current set using a command similar to the one below.
This will request again data for all already known persons. Note that these
commands pinpoint the data directory for input and output on purpose to avoid
mistakes.

```bash
./show.sh -k 'id' -- ./data/person | ./dump.sh -l fr-FR -v -r ./data -- person
```

### Searching for matching data

#### All persons born today

This uses the [`select.sh`](./select.sh) tool. It will search for entities that
match one or several keys. The content of the keys will be matched against the
same regular expression. The default is to print the value for the keys,
together with the path to the file (tabulated).

The example below would print all known persons born on the same day as today,
and their birthdate. This works because the default is to print the keys that
are used for the match.

```bash
./select.sh -w 'birthday' -r "$(date +'%m-%d')\$" -- ./data/person
```

#### Most popular person born today

The following command would show the most popular person born today. It works by
requesting to show other keys, led by the popularity and sorting on that
popularity score as a numerical value.

```bash
./select.sh -k 'popularity birthday name' -w 'birthday' -r "$(date +'%m-%d')\$" -- ./data/person |
  sort -k 1 -g -r |
  head -n 1
```


## TODO

+ Remove files where the biography is empty?
