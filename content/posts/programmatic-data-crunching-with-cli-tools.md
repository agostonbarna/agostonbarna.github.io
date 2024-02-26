---
title: "Programmatic data crunching with CLI tools"
date: 2024-02-26
draft: false
---

As a software engineer we often need to closely examine the data we work with. To name a few examples:
- We need to implement a new feature that consumes an external service, but the quality of the API documentation can vary, and it may not always provide a comprehensive overview of the structure of the data, nor give a complete picture of the actual data it holds. So it may be necessary to analyze the data in the API responses before we implement the client-side logic to avoid surprises when going live.
- We are debugging a problem that requires querying and analyzing large amounts of data (e.g. APIs, databases, log files) to identify the culprit.
- We are preparing a complex migration that significantly alter the structure of the data. Our goal is to automate the process as much as possible, and verify that no data is lost in the end.
- We get a request to crunch some data from a system and generate reports out of it (e.g. for the PM, product owners, or customer).

<!--more-->

I prefer using CLI tools over GUI apps for these kinds of tasks for several reasons:
- The Unix philosophy played a significant role in shaping the design of CLI tools and provided an excellent foundation to build on, with the main idea that each program does one thing well, and uses a universal interface (text streams). This allows programs to be easily combined in an effectively infinite number of ways, making it possible to solve a diverse set of problems. Huge, standalone programs on the other hand are less flexible, and harder to extend and maintain.
- CLI tools can be used in an automated fashion, so for example if we need to create a report periodically, we only have to write the right combination of commands and queries once, and simply rerun it on subsequent occasions.
- Even if we need to generate a different report than we did in the past, we can likely reuse some parts of the previous commands/queries, and we can also extract some common patterns to aliases, functions, scripts, etc. to abstract away the complex logic and make it easier to use.
- Many CLI tools are available on headless servers as well, which reduces the amount of back-and-forth `scp`-ing during data crunching iterations.
- CLI tools generally have lower overhead than GUI apps due to their lightweight nature which can result in reduced resource usage and higher performance.
- There are plenty of open-source CLI tools out there. With open-source programs, we don't have to worry about vendor lock-in, we can inspect the code to make sure that it's not collecting and selling sensitive data, we can request new features or contribute, open bug tickets, debug and fix bugs ourselves, and so on.

**NOTE:** This blog post is geared towards those who already have some basic shell scripting skills on Linux or macOS environments with `bash` or `zsh` shells, as I don't go into the shell basics here and only tried these commands in said environments and shells.

## JSON

JSON is a widely adopted data format, used in many (e.g. web) applications these days. JSON APIs can return large amounts of data though, which often gets condensed into a single-line format to lower the overhead, but making it hard to read and analyze for humans out of the box.

### fastgron

The first tool that comes to our rescue is [fastgron](https://github.com/adamritter/fastgron). It can flatten a deeply nested JSON structure into discrete `.path.to.key = value` lines, making it possible to use tools like `grep` to quickly find some patterns even in a huge JSON and reveal their exact path all the way up from the JSON root. This JSON path is also quite handy when writing `jq` queries (more about that in the next section). My usual workflow is this: first explore the JSON with some quick `fastgron` + `grep` commands, and then combine the located paths (identifier-indexes) with more fine-grained queries and transformations in `jq` to get the desired output.

**NOTE:** the `--root ''` option removes the `json` prefix from `fastgron`'s output which is not necessary. This makes the path a usable identifier-index filter in `jq`.

{{< details "Examples:" >}}

  **Flatten a JSON:**

  input.json:
  ```json
  [
    {
      "id": "1",
      "name": "John Doe",
      "address": {
        "city": "Paris",
        "country": "France"
      }
    },
    {
      "id": "2",
      "name": "Jane Doe",
      "address": {
        "city": "Rome",
        "country": "Italy"
      }
    }
  ]
  ```
  command:
  ```sh
  <input.json fastgron --root ''
  ```
  output:
  ```json
   = []
  [0] = {}
  [0].id = "1"
  [0].name = "John Doe"
  [0].address = {}
  [0].address.city = "Paris"
  [0].address.country = "France"
  [1] = {}
  [1].id = "2"
  [1].name = "Jane Doe"
  [1].address = {}
  [1].address.city = "Rome"
  [1].address.country = "Italy"
  ```
  
  **Unflatten a flattened JSON:**

  `fastgron` can also unflatten its own flattened JSON output back to a nested JSON with the `-u` flag. In case we did some `grep`-ing before, the unflattened output will result in a smaller JSON with a subset of `key:values`, but it keeps the original JSON structure.
  
  command:
  ```sh
  <input.json fastgron --root '' | grep name | fastgron --root '' -u
  ```
  output:
  ```json
  [
    {
      "name": "John Doe"
    },
    {
      "name": "Jane Doe"
    }
  ]
  ```

  **fastgron wrapper with auto-pager:**

  A formatted JSON can be pretty lengthy so if we simply dump it out, then the terminal buffer might fill up and cut off the beginning of the data. It can be also tedious to manually scroll to the top of the terminal each time after we change something and run the command, so I created a little shell wrapper function which makes sure the output is piped to a pager (`less`) with interactive navigation and syntax highlighting if the stdout is a tty/terminal, unless we do some further piping or redirecting the output to a file as we don't want to clutter the plain text output with the ANSI color codes in these cases:

  ```sh
  # jf: JSON flattener
  jf() {
    local cmd_base=(fastgron --root '')
    if [ -t 1 ]; then # if stdout is a tty
      "${cmd_base[@]}" -c "$@" | less -R
    else # if stdout is redirected to a pipe or file
      "${cmd_base[@]}" "$@"
    fi
  }
  
  # juf: JSON unflattener
  juf() {
    jf -u | jq
  }
  ```
{{< /details >}}

### jq

[jq](https://jqlang.github.io/jq/) is an incredibly powerful JSON querying tool that has proven to be invaluable to me over the years. It has its own concise and expressive language (DSL) to query JSON structures that takes some time to really wrap our head around, and requires learning a couple of new concepts before we could utilize its full potential, but it can spare us a lot of time on the long run if we often have to query JSON inputs.

I try to cover the basics here with some examples.

{{< details "Examples:" >}}

  #### Formatting

  If we simply redirect or pipe a JSON into `jq`, it formats a single-line condensed JSON and also does syntax highlighting out of the box.

  **Expanding:**

  input.json:
  ```json
  {"key1":"value1","key2":"value2"}
  ```
  command:
  ```sh
  <input.json jq . # . is the identity operator which simply returns the full input and optional to use if we pass in an stdin instead of a file
  ```
  output.json:
  ```json
  {
    "key1": "value1",
    "key2": "value2"
  }
  ```

  **Condensing:**

  We can also do it the other way around and formatted JSON into a compact single-line with the `-c` flag:
  ```sh
  <input.json jq -c .
  ```

  #### Streams

  To put it simply, streams in `jq` mean line-delimited JSON input or output. Also see the [JSON Lines](https://jsonlines.org) text format.

  **Compact stream input -> formatted stream output:**

  input.json:
  ```json
  {"key1":"value1","key2":"value2"}
  {"key3":"value3","key4":"value4"}
  ```
  command:
  ```sh
  <input.json jq .
  ```
  output:
  ```json
  {
    "key1": "value1",
    "key2": "value2"
  }
  {
    "key3": "value3",
    "key4": "value4"
  }
  ```

  **Stream input -> JSON array output:**

  input.json:
  ```json
  {"key1":"value1","key2":"value2"}
  {"key3":"value3","key4":"value4"}
  ```
  command:
  ```sh
  <input.json jq -s .
  ```
  output:
  ```json
  [
    {
      "key1": "value1",
      "key2": "value2"
    },
    {
      "key3": "value3",
      "key4": "value4"
    }
  ]
  ```

  **JSON array input -> stream output:**

  input.json:
  ```json
  [
    {
      "key1": "value1",
      "key2": "value2"
    },
    {
      "key3": "value3",
      "key4": "value4"
    }
  ]
  ```
  command:
  ```sh
  <input.json jq -c '.[]'
  ```
  output:
  ```json
  {"key1":"value1","key2":"value2"}
  {"key3":"value3","key4":"value4"}
  ```

  #### Object identifier-index filtering

  input.json:
  ```sh
  {
    "a": "v1",
    "b": {
      "c": "v2"
    },
    "d": "v3"
  }
  ```

  **Select key `a` from the root of the JSON:**

  command:
  ```sh
  <input.json jq '.a'
  ```
  output:
  ```json
  "v1"
  ```

  **The `-r` flag selects the raw value, e.g. `v1` instead of the quoted `"v1"` string:**

  command:
  ```sh
  <input.json jq -r '.a'
  ```
  output:
  ```
  v1
  ```

  **Select key `b`, and then select key `c`:**

  command:
  ```sh
  <input.json jq '.b.c'
  ```
  output:
  ```json
  "v2"
  ```

  **Select key `a`, select key `b` and then select key `c` as a new key `bc`, and select key `d`:**

  command:
  ```sh
  <input.json jq '{a, bc:.b.c, d}'
  ```
  output:
  ```json
  {
    "a": "v1",
    "bc": "v2",
    "d": "v3"
  }
  ```

  #### Array identifier-index filtering

  ```sh
  <input.json jq '.[0]' # get the 0th item from the array
  <input.json jq '.[0,1]' # get the 0th and 1st items from an array as a stream
  <input.json jq '.[0:3]' # get the 0th to 3rd items from an array as a stream
  <input.json jq '.[-2]' # get the 2nd last item from an array
  ```

  #### Chaining

  The pipe operator `|` can be used to chain the different operations (filters, selectors, etc.):

  ```sh
  <input.json jq '.a | .b | .c' # same as .a.b.c
  <input.json jq '.[] | .b' # same as .[].b
  ```

  #### Mapping

  The map function can be used to transform every object in an array.

  input.json:
  ```json
  [
    {
      "a": "value1",
      "b": "value2"
    },
    {
      "b": "value3",
      "c": "value4"
    }
  ]
  ```

  ---

  command:
  ```sh
  <input.json jq 'map(.a)'
  ```
  output:
  ```json
  [
    "value2",
    "value3"
  ]
  ```

  ---

  command:
  ```sh
  <input.json jq 'map({a,b})'
  ```
  output:
  ```json
  [
    {
      "a": "value1",
      "b": "value2"
    },
    {
      "a": null,
      "b": "value3"
    }
  ]
  ```

  ---

  command:
  ```sh
  <input.json jq 'map({a, b, c:"value5"})'
  ```
  output:
  ```json
  [
    {
      "a": "value1",
      "b": "value2",
      "c": "value5"
    },
    {
      "a": null,
      "b": "value3",
      "c": "value5"
    }
  ]
  ```

  #### Selecting

  input:
  ```json
  [4,1,7,5,2]
  ```

  command:
  ```sh
  <input.json jq -c 'map(select(. > 3))'
  ```
  output:
  ```json
  [4,7,5]
  ```

  #### Assigning

  input.json:
  ```json
  {"a":1}
  ```

  command:
  ```sh
  <input.json jq '.b=2 | .c=3'
  ```
  output:
  ```json
  {
    "a": 1,
    "b": 2,
    "c": 3
  }
  ```

  #### Functions

  If we want to reuse a `jq` expression, we can wrap it into a function and put it into the `~/.jq` file. After that, we can simply call the function e.g. `jq sum`.

  **Get the sum an array of numbers (ignoring nulls):**

  ```elixir
  def sum: del(.. | nulls) | add;
  ```

  **Get the average/mean of an array of numbers (ignoring nulls):**

  ```elixir
  def avg: del(.. | nulls) | add/length;
  ```

  **Get the median of an array of numbers (ignoring nulls):**

  ```elixir
  def median:
    del(.. | nulls)
    | sort
    | if length == 0 then empty
      elif length%2 == 1 then .[length/2]
      else (.[length/2-1] + .[length/2]) / 2
      end;
  ```

  **Convert an array of objects to a matrix (array of arrays) without sorting the keys:**

  ```elixir
  def objs2matrix:
    (reduce .[] as $item ({}; . + $item) | keys_unsorted) as $cols
    | $cols, map([ .[$cols[]] ])[];
  ```

  input.json:
  ```json
  [
    {
      "h1": "r1c1",
      "h2": "r1c2",
      "h3": "r1c3"
    },
    {
      "h1": "r2c1",
      "h2": "r2c2",
      "h3": "r2c3"
    },
    {
      "h1": "r3c1",
      "h2": "r3c2",
      "h3": "r3c3"
    }
  ]
  ```
  command:
  ```sh
  <input.json jq -c objs2matrix
  ```
  output:
  ```json
  ["h1","h2","h3"]
  ["r1c1","r1c2","r1c3"]
  ["r2c1","r2c2","r2c3"]
  ["r3c1","r3c2","r3c3"]
  ```
  
  **Convert an array of objects to CSV format:**

  ```elixir
  def objs2csv: objs2matrix | @csv;
  ```

  command:
  ```sh
  <input.json jq -r objs2csv
  ```
  output:
  ```json
  "h1","h2","h3"
  "r1c1","r1c2","r1c3"
  "r2c1","r2c2","r2c3"
  "r3c1","r3c2","r3c3"
  ```
  
  **Convert an array of objects to TSV format:**
  ```elixir
  def objs2tsv: objs2matrix | @tsv;
  ```

  **jq with auto-pager:**

  ```sh
  jq() {
    if [ -t 1 ]; then # if stdout is a tty
      command jq -C "$@" | less -R
    else # if stdout is redirected to a pipe or file
      command jq "$@"
    fi
  }
  ```

  With that, I have just barely scratched the surface. There's so much more cool stuff in the [`jq` docs](https://jqlang.github.io/jq/manual/) with a more in depth explanation.

{{< /details >}}

## XML

XML is another broadly used format to store and carry structured data. I was never a big fan of XPath and XSLT for querying and transforming XML, but I found some alternatives that worked better for me.

### xml2 & 2xml

[xml2](https://github.com/mnhrdt/xml2) can transform a nested XML structure into separate `/path/to/key=value` lines. This enables us to use tools such as `grep` to efficiently find some specific patterns within large XML files and unveil their location in the XML structure.

{{< details "Examples:" >}}

  **Flatten an XML:**
  
  input.xml:
  ```xml
  <project>
    <groupId>com.mycompany.app</groupId>
    <artifactId>my-app</artifactId>
    <version>1.0</version>
  </project>
  ```
  command:
  ```sh
  <input.xml xml2
  ```
  output:
  ```xml
  /project/groupId=com.mycompany.app
  /project/artifactId=my-app
  /project/version=1.0
  ```

  **Unflatten a flattened XML:**
  
  `2xml` can also unflatten the `xml2` flattened (+ optionally grepped) XML output back to an XML, keeping its nested structure.

  command:
  ```sh
  <input.xml xml2 | grep version | 2xml
  ```
  output:
  ```xml
  <project><version>1.0</version></project>
  ```

  `2xml` doesn't format the returned XML, but we can do that with `xq` (more in the next section).

{{< /details >}}

### xq

The [kislyuk/yq](https://github.com/kislyuk/yq) project provides `xq` (and `yq`), a tool built on top of `jq` that can help to convert XML to JSON, and also supports `jq` queries and flags.

{{< details "Examples:" >}}

  **Format an XML:**

  ```sh
  xq -x
  ```

  **XML to JSON:**

  With this shell function+alias we can convert XML to JSON and use the same `jq` queries mentioned above:
  ```sh
  xq() {
    if [ -t 1 ]; then # if stdout is a tty
      command xq -C "$@" | less -R
    else # if stdout is redirected to a pipe or file
      command xq "$@"
    fi
  }

  alias xml2json=xq
  ```

  **JSON to XML:**

  **NOTE:** This is an undocumented option with limited functionality. E.g. it doesn't work with JSON array inputs. If the JSON input object has multiple keys, it will result in a multi-root XML which is invalid, but in this case we can pass the `--xml-root=root` option to wrap the output into a `root` element, making it a single-root XML.
  **NOTE:** `bat -l XML` provides XML syntax highlighting in addition to paging, but it can be replaced with the more generally available `less` command if [bat](https://github.com/sharkdp/bat) is not installed.

  With this shell function we can convert JSON to XML:
  ```sh
  json2xml() {
    if [ -t 1 ]; then # if stdout is a tty
      command yq -x "$@" | bat -l xml
    else # if stdout is redirected to a pipe or file
      command yq -x "$@"
    fi
  }
  ```
{{< /details >}}

## YAML

YAML is a common choice for config files and _Infrastructure as Code_ tools because it is (arguably) more human-readable and easier to write than some other data serialization languages.

### yq

The [kislyuk/yq](https://github.com/kislyuk/yq) project also provides `yq`, a tool built on top of `jq` that can convert YAML to JSON, and also supports `jq` queries and flags.

{{< details "Examples:" >}}

  **YAML to JSON:**

  With this shell function+alias we can convert YAML to JSON and use the same `jq` queries mentioned above:
  ```sh
  yq() {
    if [ -t 1 ]; then # if stdout is a tty
      command yq -C "$@" | less -R
    else # if stdout is redirected to a pipe or file
      command yq "$@"
    fi
  }

  alias yaml2json=yq
  ```

  **JSON to YAML:**

  **NOTE:** by default, custom YAML tags and styles in the input are ignored. Use the `-Y` option instead of `-y` to preserve YAML tags and styles by representing them as extra items in their enclosing mappings and sequences while in JSON

  With this shell function we can convert JSON to YAML:
  ```sh
  json2yaml() {
    if [ -t 1 ]; then # if stdout is a tty
      command yq -y "$@" | bat -l yaml
    else # if stdout is redirected to a pipe or file
      command yq -y "$@"
    fi
  }
  ```
{{< /details >}}

## CSV & TSV

CSV (Comma Separated Values) and TSV (Tab Separated Values) are widely used plain text formats for storing tabular data. Many applications provide a CSV export/import feature for the end user.

### csvtk

[csvtk](https://github.com/shenwei356/csvtk) is a command-line tool for processing and manipulating CSV & TSV files with a plethora of features. It has a terrific [documentation](https://bioinf.shenwei.me/csvtk/) with many examples, so I only list here a few features/sub-commands that I find the most useful without going into too much detail.

{{< details "Examples:" >}}

  ```sh
  csvtk pretty -S bold # pretty print the CSV in an aligned table
  csvtk headers # print the CSV header fields
  csvtk del-headers # remove the CSV header
  csvtk rename -f Field1,Field2 -n field1,field2 # rename `Field1` to `field1` and `Field2` to `field2`
  csvtk cut -f1 -f-1 -f Field -Ff FuzzyField # get the first, last fields by their index, the field with the exact header name, and the field with the fuzzy/glob matching header name
  csvtk grep -Ff 'FuzzyField*' -rp RegexVal -i -v # select the row where the fuzzy/glob matching field's value matches the regex, ignoring case and inverting matches
  csvtk filter -f 'Field>10' # filter the rows by values of selected fields with an arithmetic expression
  csvtk filter2 -f 'Field>10 && len(Field2)<100' # filter the rows by awk-like arithmetic/string expressions
  csvtk transpose # transpose the data matrix
  csvtk join -f 'username;user' -O/-L # join CSV files by selected fields using inner/outer/left join
  csvtk freq -f Field -n # get the frequencies of the selected fields, sorting by frequency
  csvtk summary -f 2:min,2:max,2:sum,2:mean,2:median,2:stdev | csvtk transpose | csv -H pretty # fetch some statistics
  csvtk csv2xlsx # convert CSV to XLSX (Excel)
  csvtk xlsx2csv # convert XLSX (Excel) to CSV
  csvtk csv2json # convert CSV to JSON
  csvtk plot box/hist/line # plotting
  ```

  **Interactive CSV viewer with a fixed header:**

  **NOTE:** the `--header` option that keeps the first n lines fixed when scrolling is only supported in newer `less` versions

  ```sh
  csv() {
    csvtk pretty -S bold -n 1024 "$@" | less -S --header=3
  }
  ```

  input.csv:
  ```
  firstName,middleName,lastName
  John,Michael,Smith
  Emily,Jane,Doe
  David,,Johnson
  ```
  command:
  ```sh
  <input.csv csv
  ```
  output:
  ```
  ┏━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━┓
  ┃ firstName ┃ middleName ┃ lastName ┃
  ┣━━━━━━━━━━━╋━━━━━━━━━━━━╋━━━━━━━━━━┫
  ┃ John      ┃ Michael    ┃ Smith    ┃
  ┣━━━━━━━━━━━╋━━━━━━━━━━━━╋━━━━━━━━━━┫
  ┃ Emily     ┃ Jane       ┃ Doe      ┃
  ┣━━━━━━━━━━━╋━━━━━━━━━━━━╋━━━━━━━━━━┫
  ┃ David     ┃            ┃ Johnson  ┃
  ┗━━━━━━━━━━━┻━━━━━━━━━━━━┻━━━━━━━━━━┛
  ```

{{< /details >}}

### sqlite3

`sqlite3` can import a CSV to an in-memory db, making it possible to run SQL queries against the CSV data.

**NOTE:** older `sqlite3` versions might not support the mentioned features

{{< details "Examples:" >}}

  **Wrapper function for convenience:**
  ```sh
  csv2sqlite() {
    sqlite3 -column :memory: '.import --csv /dev/stdin csv' "$@" | less
    # alternative if /dev/stdin is not available: ".import --csv '|cat -' csv"
    # or directly pass in the file, but I prefer to use the stdin as it's more flexible
  }
  ```

  input.csv:
  ```csv
  h1,h2,h3
  r1c1,r1c2,r1c3
  r2c1,r2c2,r2c3
  r3c1,r3c2,r3c3
  ```

  **Query a CSV using SQL, use table-like output:**

  command:
  ```sh
  <input.csv csv2sqlite 'select h1,h3 from csv where h2!="r1c2"'
  ```
  output:
  ```csv
  h1    h3
  ----  ----
  r2c1  r2c3
  r3c1  r3c3
  ```

  By default, `sqlite3` uses the column output, but one can pass in the `-table`, `-box`, etc. flags for other output formats.

  **Query a CSV using SQL, use CSV output:**

  command:
  ```sh
  <input.csv csv2sqlite 'select h1,h3 from csv where h2!="r1c2"' -csv
  ```
  output:
  ```csv
  h1,h3
  r2c1,r2c3
  r3c1,r3c3
  ```

  **Query a CSV using SQL, use JSON output:**

  command:
  ```sh
  <input.csv csv2sqlite 'select h1,h3 from csv where h2!="r1c2"' -json
  ```
  output:
  ```json
  [{"h1":"r2c1","h3":"r2c3"},
  {"h1":"r3c1","h3":"r3c3"}]
  ```

{{< /details >}}

## Arbitrary text

Numerous tools are available for extracting data from plain text files, such as log files, and subsequently transforming and analyzing it.

### Basic UNIX tools

These classic tools are usually installed by default on many UNIX-like OSes. These can be useful for arbitrary texts, but generally not well-suited for more complex file formats such as JSON, XML and CSV.

{{< details "Examples:" >}}

  ```sh
  head -n1 # get the first line
  tail -n1 # get the last line
  cut -d: -f1,3 # get the 1st and 3rd columns of a : sepearated input
  paste -sd, # join the line with commas
  sort -nk1 # sort by the first field using numeric sort
  sort -u # get the sorted and unique lines
  sort | uniq -c # sort the lines and then group-by and count the number of consecutive occurences of the same lines
  tr -s ' ' '\n' # replaces spaces with newlines, squeezing consequtive spaces
  column -ts$'\t' # format a TSV file so it's columns are aligned
  ```

{{< /details >}}

### less

`less` is an interactive pager that can be used to easily navigate long chunks of text with (mostly) the keyboard.

{{< details "Examples:" >}}

  It supports the arrow keys and the VI-like `j`/`k` keys for vertical scrolling, but not the `h`/`l` keys out of the box.  
  But it's easy to fix this by putting the following key mapping into the `~/.lesskey` file:
  ```sh
  #command
  h left-scroll
  l right-scroll
  ```
  and then running this command (this step is obsolete for newer `less` versions):
  ```sh
  lesskey
  ```

  Other useful shortcut keys:
  * `f`/`b`: jump to next/previous page
  * `/`/`?`: search forward/backward
  * `&`: display only lines matching the pattern
  * `n`/`N`: jump to next/previous match
  * `gg`/`G`: jump to the top/bottom of the text
  * `F`: scroll to bottom and watch for new lines (e.g. to follow a log file)

  CLI flags to configure `less`:
  ```sh
  export LESS='-iSRF --mouse --incsearch -Q --no-vbell' # NOTE: some of the options won't work with older less versions
  ```
  * `-i`: case-insensitive searching
  * `-S`: chop (do not wrap) long lines
  * `-R`: keep ANSI color
  * `-F`: quit if the entire text can be displayed on the screen
  * `--mouse`: enable mouse scrolling (only in newer `less` versions)
  * `--incsearch`: search as we type (only in newer `less` versions)
  * `-Q`: do not beep/ring the terminal bell e.g. when reaching the end of file, and use the visual bell instead (unless we use `--no-vbell`)
  * `--no-vbell`: disable the visual bell (only in newer `less` versions)

{{< /details >}}

### grep

`grep` is a line-oriented tool to search for text patterns within files, widely available on many UNIX-like OS-es.

**NOTE:** there are slight differences in the different (e.g. GNU, BSD, busybox, etc.) `grep` implementations.

{{< details "Examples:" >}}

  ```sh
  grep '^ *PATTERN' # select lines that matches a Basic Regex pattern
  grep -i 'PATTERN' # select lines that matches a pattern, ignoring the case
  grep -w 'PATTERN' # select lines that matches a whole word
  grep -x 'PATTERN' # select lines that matches the whole line
  grep -F 'PATTERN' # select lines that matches a fixed substring
  grep -e 'PATTERN1' -e 'PATTERN2' # select lines that matches either PATTERN1 or PATTERN2
  grep -f PATTERN_FILE # select lines that matches any of the patterns in the provided PATTERN_FILE
  grep -v 'PATTERN' # select lines that DO NOT matches a pattern
  grep -o 'PATTERN' # select lines that matches a pattern, and only print the matched chars
  grep -m1 'PATTERN' # select only the first line that matches the pattern
  grep -c 'PATTERN' # print the count of the lines that matches a pattern (instead of the matched lines)
  grep -q 'PATTERN' # quiet mode, only return the exit code whether there was a match or no
  grep -E '^ +PATTERN(-OPT-SUFFIX)?$' # use extended regex with more regex features / less escaping
  grep -Po '^PREFIX\KPATTERN(?=-SUFFIX)$' # use Perl regex with even more regex features
  grep -A1 'PATTERN' # include 1 context lines before the matches
  grep -B1 'PATTERN' # include 1 context lines after the matches
  grep -C1 'PATTERN' # include 1 context lines before+after the matches
  grep -r 'PATTERN' DIRECTORY # recursively grep files and show the filenames too
  grep -rh 'PATTERN' DIRECTORY # recursively grep files and hide the filenames
  grep -rl 'PATTERN' DIRECTORY # recursively grep files and only list the matched filenames
  ```

{{< /details >}}

### ripgrep

[ripgrep](https://github.com/BurntSushi/ripgrep) is a modern `grep` alternative. It supports most `grep` flags and features, but it's significantly faster than `grep`, uses smart-case search (case-insensitive search unless the pattern contains uppercase characters), respects the `.gitignore` and other ignore files to reduce the noise and further improve the performance, has better compatibility between the different platforms, and many additional features.

{{< details "Examples:" >}}

  Some additional features over `grep`:
  ```sh
  rg -U 'PATTERN' # match patterns across multiple lines
  rg -z 'PATTERN' # recursively grep compressed files too (e.g. rotated log files)
  rg --pre fastgron --pre-glob '*.json' 'PATTERN' # use fastgron as a preprocessor to flatten the JSON files, and then grep the flattened output 
  ```

  `rg` with auto-pager:
  ```sh
  rg() {
    if [ -t 1 ]; then # if stdout is a tty
      command rg --color=always "$@" | less -R
    else # if stdout is redirected to a pipe or file
      command rg "$@"
    fi
  }
  ```

{{< /details >}}

### sed

`sed` (stream editor), is a command-line utility used for transforming text streams. It can be used for text substitution, deletion, insertion, and more.

**NOTE:** there are some differences between the different `sed` flavors (e.g. GNU, BSD, etc.).

{{< details "Examples:" >}}

  ```sh
  sed 's/PATTERN/REPLACEMENT/' # replace the first occurence of Basic Regex PATTERN with REPLACEMENT in each line
  sed 's/PATTERN/REPLACEMENT/g' # replace all occurences of PATTERN with REPLACEMENT in each line
  sed -i.orig 's/PATTERN/REPLACEMENT/' FILE... # edit the file(s) in-place, create a backup with the .orig extension
  sed -E 's/PATTERN/REPLACEMENT/' # use Extended Regex
  sed 's/PATTERN1/REPLACEMENT1/; s/PATTERN2/REPLACEMENT2/' # use multiple expressions v1
  sed -e 's/PATTERN1/REPLACEMENT1/' -e 's/PATTERN2/REPLACEMENT2/' # use multiple expressions v2
  sed -n '/^PATTERN1/ s/PATTERN2/REPLACEMENT/p' # only replace PATTERN2 and print the modified line if also matched PATTERN1
  sed -e '/PATTERN/a\' -e 'NEW_LINE' # append NEW_LINE after line with PATTERN
  ```

{{< /details >}}

### awk

`awk` is a powerful tool that processes the input line by line and can perform various operations, including pattern matching, text extraction, data manipulation, and report generation.

**NOTE:** there are some differences between the different `awk` variants (`gawk`, `mawk`, etc.).

{{< details "Examples:" >}}

  Get the nth column/field:
  ```sh
  awk '{print $1}' # get the 1st column
  awk '{print $NF}' # get the last column
  awk '{print $((NF-1))}' # get the column before the last one
  awk -F: '{print $1}' # get the first column, using : as the field separator instead of whitespace
  ```

  Get the unique lines from one or more input files without sorting:
  ```sh
  union() {
    awk '!seen[$0]++' "$@"
  }
  ```

  Get the intersection / lines that are in every input file:
  ```sh
  inter() {
    awk 'FNR==1{if (NR!=1) delete seen_file; files++}
      !($0 in seen_file) {seen_file[$0]=1; seen[$0]++}
      END {for (e in seen) if (seen[e]==files) print e}' "$@"
  }
  ```

  Get the lines from first file that are not in the 2nd+ files:
  ```sh
  minus() {
    awk 'FNR==1 {file++}
    file==1 {seen[$0]=1}
    file>=2 {delete seen[$0]}
    END {for (e in seen) print e}' "$@"
  }
  ```

  Get the min of line or space separated numbers from the stdin:
  ```sh
  min() {
    awk '{if(min==""){min=$1};
      for (i=1; i<=NF; i++) if (min>$i) min=$i}
      END {if (min!="") print min}'
  }
  ```
  
  Get the max of line or space separated numbers from the stdin:
  ```sh
  max() {
    awk '{if(max==""){max=$1};
      for (i=1; i<=NF; i++) if (max<$i) max=$i}
      END {if (max!="") print max}'
  }
  ```
  
  Get the sum of line or space separated numbers from the stdin:
  ```sh
  sum() {
    awk '{for (i=1; i<=NF; i++) sum+=$i}
      END {if (sum!="") print sum}'
  }
  ```

  Get the average of line or space separated numbers from the stdin:
  ```sh
  avg() {
    awk '{for (i=1; i<=NF; i++) {sum+=$i;count++}}
      END {if (count>0) print sum/count}'
  }
  ```

  Get the median of line or space separated numbers from the stdin:
  ```sh
  median() {
    # only GNU awk has a sorting function, so we use the more compatible `sort -g` instead
    tr -s '[:space:]' '\n' \
    | sort -g \
    | awk '{a[NR]=$1}
        END {if (NR%2==1) {print a[(NR+1)/2]} else {print (a[NR/2] + a[NR/2+1]) / 2.0}}'
  }
  ```
{{< /details >}}

### perl

`perl` is a general-purpose scripting language with strong text-processing capabilities. There are a couple of use-cases when it can be handy: 
* If `sed` or `awk` is not sufficient and we need a powerful programming language, or feature (e.g. PCRE regex)
* When the task requires multi-platform compatibility (e.g. `sed` and `awk` have multiple flavours with some differences)
* There are some other edge cases, like UTF8 uppercasing/lowercasing (some `tr` versions only work with ASCII).

{{< details "Examples:" >}}
  ```sh
  perl -pe 's/pattern/replacement/g' # replace pattern with replacement using PCRE regex
  perl -Mopen=locale -Mutf8 -pe '$_=uc' # uppercase UTF-8 text
  perl -Mopen=locale -Mutf8 -pe '$_=lc' # lowercase UTF-8 text
  perl -ne '(/start/../end/) && print' # print out the lines between two matching lines
  perl -MO=Deparse # see what a perl one-liner does under the hood
  ```
{{< /details >}}
