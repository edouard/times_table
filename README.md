# Times Table

[![Tests](https://github.com/edouard/times_table/actions/workflows/test.yml/badge.svg)](https://github.com/edouard/times_table/actions/workflows/test.yml)

A small command-line game to help primary-school kids learn their multiplication tables.

Single Ruby file, standard library only. No gems to install.

## Usage

```sh
ruby times_table.rb
```

It asks which tables to practice: type a few numbers (`2 5 7`) or `all` for 1 to 10. Type `q` and Enter at any time to quit (Ctrl-C works too); progress is saved either way.

```sh
ruby times_table.rb --tables 2,5,7 --questions 30   # skip the question
ruby times_table.rb --mode mixed                     # multiply, missing number and division
ruby times_table.rb --challenge                      # as many as possible in 60 seconds
ruby times_table.rb --name Ana                       # separate progress for each child
ruby times_table.rb --stats --name Ana               # see Ana's progress
ruby times_table.rb --lang es                        # en español
```

| Option | Short | Default | Description |
| --- | --- | --- | --- |
| `--tables LIST` | `-t` | asked at start | Tables to practice, e.g. `2,5,7` or `all` |
| `--questions N` | `-n` | 20 | Number of questions |
| `--mode MODE` | `-m` | `multiply` | `multiply` (7 x 8 = ?), `missing` (? x 8 = 56), `divide` (56 ÷ 7 = ?) or `mixed` |
| `--challenge [SECONDS]` | `-c` | 60 | Timed challenge: answer as many as you can |
| `--think SECONDS` | | 8 | Length of the countdown before an answer counts as not automatic |
| `--no-timer` | | | No countdown; slow answers count like fast ones |
| `--name NAME` | `-p` | | Player name; each child gets their own progress |
| `--stats` | `-s` | | Show progress and exit |
| `--lang LANG` | `-l` | `en` | `en` or `es` |
| `--no-animations` | | | Turn off animations |
| `--help` | `-h` | | Show help |

## How it works

**Countdown.** In a terminal, a bar counts down next to each question. An answer after the countdown is still accepted, but it's marked as *not automatic yet*: the fact isn't promoted and comes back next session. Use `--no-timer` to practice without any time pressure (the challenge clock still runs).

**Animations.** Right answers sparkle, wrong answers shake, and streaks of 5, 10, 15… flash on screen. A perfect session ends with confetti. Animations and colors only appear in a real terminal; colors also turn off with `NO_COLOR`.

**Mistakes.** A wrong answer shows the correct result, then the question comes back a couple of questions later, then later again until it's right. After a miss on 7 x 8, 8 x 7 is asked too, and once the child gets it right it's checked one more time near the end.

**Spaced repetition.** Every fact (like 7 x 8) sits in one of four boxes:

| Box | Meaning | Asked again |
| --- | --- | --- |
| 0 | needs practice (missed or slow) | next session |
| 1 | learning | 2 sessions later |
| 2 | learning | 4 sessions later |
| 3 | mastered ⭐ | 8 sessions later, as a review |

A fast, right, first-try answer moves a fact up one box once it's due, so mastering a fact takes three good answers in well-spaced sessions (for example sessions 1, 3 and 7). A wrong answer sends it back to box 0. Each session starts with the facts that are due, weakest first. Missed facts from other tables are included too.

**Progress.** At the end of a session you see the score, total and average time, best streak, facts mastered today, and what to practice. `--stats` shows a 10 x 10 grid of every fact, records and recent sessions:

```
  x    1  2  3  4  5  6  7  8  9 10
  1    ★  ★  ★  ★  ★  ★  ★  ★  ★  ★
  2    ★  ●  ●  ★  ●  ·  ·  ●  ✗  ★
  ...
★ mastered  ● learning  ✗ needs practice  · not seen yet
```

Progress is saved in `~/.times_table.json` (set `TIMES_TABLE_FILE` to use another file). Files from the first version of the script are upgraded automatically, and a damaged file is moved aside to `.bak` rather than overwritten.

## Development

```sh
ruby -w test/times_table_test.rb
```

The tests use Minitest, which ships with Ruby. They run in-process with a fake clock, plus one test that drives the real script in a pseudo-terminal to check the countdown and animations. GitHub Actions runs them on every push.

## Requirements

Ruby 3.3 or later. Only maintained Ruby versions are supported (3.3, 3.4 and 4.0); CI tests all three.

## License

MIT, see [LICENSE](LICENSE).
