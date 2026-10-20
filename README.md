# rubocop-fuzz

Fuzzing harness for [RuboCop](https://github.com/rubocop/rubocop). Runs
`rubocop -A` over real-world Ruby code with generated config variants and
catches cop crashes, infinite correction loops, and broken autocorrects.

## Installation

```sh
git clone https://github.com/Starlexxx/rubocop-fuzz
cd rubocop-fuzz
bundle install
```

## Usage

```sh
# scan installed gems with the default config
rubocop-fuzz scan --rubocop path/to/rubocop

# fuzz cross-cop config interactions
rubocop-fuzz scan --rubocop path/to/rubocop --tier interactions --shards-per-config 3

# all cops on, non-default options spread over a few configs (reshuffled by --seed)
rubocop-fuzz scan --rubocop path/to/rubocop --tier packed

# fuzz a plugin checkout together with core (repeat --plugin for several)
rubocop-fuzz scan --rubocop path/to/rubocop --plugin rubocop-performance=path/to/rubocop-performance

# add the last day's newly published gems to a corpus
script/fetch-fresh-corpus corpus-gems 100

# shrink findings to a minimal repro
rubocop-fuzz minimize --rubocop path/to/rubocop --findings fuzz-out/findings.jsonl
```

Findings are written to `fuzz-out/findings.jsonl` and `fuzz-out/report.md`.

```sh
# collapse known findings and keep only groups that involve a plugin cop
rubocop-fuzz triage --findings fuzz-out/findings.jsonl --known known_issues.yml --cops '^Performance/'
```

The `nightly` workflow fuzzes core; `nightly-plugins` fuzzes core together with
the plugin checkouts and files its findings under the `nightly-plugins` label.

## Development

```sh
bundle exec rspec
```

## License

MIT
