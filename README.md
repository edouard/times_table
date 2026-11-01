# Times Table

A small command-line script to help primary-school kids practice their multiplication tables.

Single Ruby file, standard library only — no gems to install.

## Usage

```sh
ruby times_table.rb
```

It asks which tables to practice: type a few numbers (`2 5 7`) or `all` for 1 to 10.

Skip the question with options:

```sh
ruby times_table.rb --tables 2,5,7 --questions 30
```

| Option | Short | Default | Description |
| --- | --- | --- | --- |
| `--tables LIST` | `-t` | asked at start | Tables to practice, e.g. `2,5,7` or `all` |
| `--questions N` | `-n` | 20 | Number of questions |
| `--help` | `-h` | | Show help |

Type `q` at any prompt to quit (Ctrl-C and Ctrl-D work too).

## How it works

- Questions are picked at random from the chosen tables, with multipliers from 1 to 10.
- A right answer gets a cheer in green. A wrong answer shows the correct result in red, and the question comes back a few questions later until it's answered correctly.
- At the end you see the score (right on the first try), total time, average time per answer, and the questions that were missed.
- Missed questions are saved to `~/.times_table.json` and asked first next session. They're removed once answered correctly on the first try.

Colors are turned off when output isn't a terminal or when `NO_COLOR` is set.

## Requirements

Ruby 3.0 or later.
