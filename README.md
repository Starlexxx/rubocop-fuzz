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

# shrink findings to a minimal repro
rubocop-fuzz minimize --rubocop path/to/rubocop --findings fuzz-out/findings.jsonl
```

Findings are written to `fuzz-out/findings.jsonl` and `fuzz-out/report.md`.

## Development

```sh
bundle exec rspec
```

## License

MIT
