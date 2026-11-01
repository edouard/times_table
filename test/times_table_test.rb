# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "stringio"
require "tmpdir"
require_relative "../times_table"

# Answers questions by reading the last prompt written to the output.
# The block gets the correct answer and the prompt, and returns what to type.
class Responder
  attr_reader :prompts

  def initialize(output, clock: nil, seconds_per_answer: 1, &block)
    @output = output
    @clock = clock
    @seconds = seconds_per_answer
    @block = block || ->(answer, _prompt) { answer }
    @prompts = []
  end

  def tty? = false

  def gets
    prompt = @output.string.lines.last.to_s
    @prompts << prompt
    @clock&.advance(@seconds)
    reply = @block.call(Responder.solve(prompt), prompt)
    reply.nil? ? nil : "#{reply}\n"
  end

  def self.solve(prompt)
    case prompt
    when /(\d+) x (\d+) = \? \z/ then $1.to_i * $2.to_i
    when /\? x (\d+) = (\d+) \z/ then $2.to_i / $1.to_i
    when /(\d+) x \? = (\d+) \z/ then $2.to_i / $1.to_i
    when /(\d+) ÷ (\d+) = \? \z/ then $1.to_i / $2.to_i
    end
  end
end

class FakeClock
  def initialize = @now = 0.0
  def advance(seconds) = @now += seconds
  def call = @now
end

module Helpers
  def setup
    @dir = Dir.mktmpdir
    @file = File.join(@dir, "progress.json")
    @clock = FakeClock.new
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def run_cli(*args, seconds_per_answer: 1, &block)
    output = StringIO.new
    input = Responder.new(output, clock: @clock, seconds_per_answer:, &block)
    TimesTable::CLI.run(TimesTable::CLI.parse(args), input:, output:, file: @file,
                                                     clock: @clock, rng: Random.new(42))
    [output.string, input]
  end

  def saved = JSON.parse(File.read(@file))
  def saved_profile(name = TimesTable::DEFAULT_PROFILE) = saved.dig("profiles", name)
  def questions(input) = input.prompts.grep(/ = /)
end

class ParseTablesTest < Minitest::Test
  def test_accepts_spaces_commas_and_all
    assert_equal [2, 5, 7], TimesTable.parse_tables("7 2,5 5")
    assert_equal (1..10).to_a, TimesTable.parse_tables("All")
    assert_equal (1..10).to_a, TimesTable.parse_tables("todo")
  end

  def test_rejects_invalid_input
    [nil, "", "0", "11", "2 x", "-3", "2.5"].each do |text|
      assert_nil TimesTable.parse_tables(text), text.inspect
    end
  end
end

class OptionsTest < Minitest::Test
  def test_defaults
    options = TimesTable::CLI.parse([])
    assert_equal 20, options[:questions]
    assert_equal "multiply", options[:mode]
    assert_equal "en", options[:lang]
    assert_nil options[:tables]
    assert_nil options[:challenge]
  end

  def test_all_options
    options = TimesTable::CLI.parse(%w[-t 2,5 -n 30 -m mixed -c --think 5 -p Ana -l es --no-animations])
    assert_equal [2, 5], options[:tables]
    assert_equal 30, options[:questions]
    assert_equal "mixed", options[:mode]
    assert_equal 60, options[:challenge]
    assert_equal 5, options[:think]
    assert_equal "Ana", options[:name]
    assert_equal "es", options[:lang]
    refute options[:animate]
  end

  def test_no_timer
    assert TimesTable::CLI.parse([])[:timer]
    refute TimesTable::CLI.parse(%w[--no-timer])[:timer]
    refute TimesTable::CLI.parse(%w[--no-timer --think 5])[:timer]
  end

  def test_invalid_options
    [%w[-t 11], %w[-n 0], %w[-n x], %w[-m foo], %w[-c 0], %w[-l fr], %w[extra], %w[-p], ["-p", " "]].each do |args|
      assert_raises(OptionParser::ParseError, args.inspect) { TimesTable::CLI.parse(args) }
    end
  end
end

class QuestionTest < Minitest::Test
  Q = TimesTable::Question

  def test_kinds
    assert_equal ["7 x 8 = ?", 56], [Q.new(a: 7, b: 8, kind: :multiply).then { [_1.template, _1.answer] }].flatten
    assert_equal ["? x 8 = 56", 7], [Q.new(a: 7, b: 8, kind: :missing_a).then { [_1.template, _1.answer] }].flatten
    assert_equal ["7 x ? = 56", 8], [Q.new(a: 7, b: 8, kind: :missing_b).then { [_1.template, _1.answer] }].flatten
    assert_equal ["56 ÷ 7 = ?", 8], [Q.new(a: 7, b: 8, kind: :divide).then { [_1.template, _1.answer] }].flatten
  end

  def test_solved_and_flipped
    question = Q.new(a: 7, b: 8, kind: :missing_a)
    assert_equal "7 x 8 = 56", question.solved
    assert_equal Q.new(a: 8, b: 7, kind: :missing_b), question.flipped
    assert_equal "56 ÷ 7 = 8", Q.new(a: 7, b: 8, kind: :divide).solved
  end
end

class ProfileTest < Minitest::Test
  def profile = @profile ||= TimesTable::Profile.new("default", {})

  def test_mastered_after_three_fast_answers_in_spaced_sessions
    refute profile.record_right(7, 8, 1)
    refute profile.record_right(7, 8, 1), "only one promotion per session"
    assert_equal :learning, profile.status(7, 8)
    refute profile.record_right(7, 8, 2)
    assert_equal 1, profile.fact(7, 8)["box"], "not due yet: no promotion"
    refute profile.record_right(7, 8, 3)
    assert_equal 2, profile.fact(7, 8)["box"]
    refute profile.record_right(7, 8, 6)
    assert profile.record_right(7, 8, 7)
    assert_equal :mastered, profile.status(7, 8)
    assert_equal 7 + 8, profile.fact(7, 8)["due"]
  end

  def test_wrong_answer_resets_the_box
    profile.record_right(7, 8, 1)
    profile.record_right(7, 8, 2)
    profile.record_wrong(7, 8, 3)
    assert_equal :shaky, profile.status(7, 8)
    assert_equal [[7, 8]], profile.due_facts(4)
  end

  def test_slow_answer_keeps_the_box_and_comes_back_next_session
    profile.record_right(7, 8, 1)
    profile.record_slow(7, 8, 2)
    assert_equal 1, profile.fact(7, 8)["box"]
    assert_equal 3, profile.fact(7, 8)["due"]
  end

  def test_records
    assert_empty profile.add_session("best_streak" => 3, "challenge" => nil, "right" => 3)
    assert_equal({ streak: true }, profile.add_session("best_streak" => 6, "challenge" => nil, "right" => 6))
    assert_equal({ challenge: true }, profile.add_session("best_streak" => 2, "challenge" => 60, "right" => 9))
    assert_empty profile.add_session("best_streak" => 2, "challenge" => 60, "right" => 9)
    assert_equal 4, profile.sessions.size
    assert_equal 5, profile.session_number
  end

  def test_ignores_bad_data
    profile = TimesTable::Profile.new("x", "facts" => { "7x8" => { "box" => 9, "due" => "soon" }, "0x3" => {}, "zz" => 1 },
                                           "sessions" => [1, {}], "best_streak" => "a")
    assert_equal ["7x8"], profile.instance_variable_get(:@data)["facts"].keys
    assert_equal :mastered, profile.status(7, 8)
    assert_equal 0, profile.fact(7, 8)["due"]
    assert_equal 1, profile.sessions.size
    assert_equal 0, profile.best_streak
  end
end

class KeyReaderTest < Minitest::Test
  def keys(*chunks)
    reader = TimesTable::LiveInput::KeyReader.new
    chunks.flat_map { |chunk| [].tap { |keys| reader.feed(chunk) { keys << _1 } } }
  end

  def test_escape_sequences_are_swallowed
    # fn+Delete, PgUp, F5, Ctrl+Left, an arrow split across two reads, SS3 F1
    assert_equal ["5", :enter], keys("5\e[3~\e[5~\e[15~\e[1;5D\e[", "A\eOP", "\r")
  end

  def test_control_keys_and_lone_escape
    assert_equal [:backspace, :quit, :quit, "7", :enter], keys("\u007f\u0003\u0004", "\e", "7\n")
  end
end

class StoreTest < Minitest::Test
  include Helpers

  def test_missing_file_starts_empty
    store = TimesTable::Store.new(@file)
    refute store.corrupt?
    assert_equal 1, store.profile("default").session_number
  end

  def test_round_trip_and_separate_profiles
    store = TimesTable::Store.new(@file)
    store.profile("ana", "Ana").record_wrong(7, 8, 1)
    store.profile("leo", "Leo")
    assert_nil store.save
    reloaded = TimesTable::Store.new(@file)
    assert_equal :shaky, reloaded.profile("ana").status(7, 8)
    assert_equal :unseen, reloaded.profile("leo").status(7, 8)
    assert_equal "Ana", reloaded.profile("ana").display_name
  end

  def test_migrates_version_1
    File.write(@file, JSON.generate("missed" => [[7, 8], [3, 4], "bad"]))
    profile = TimesTable::Store.new(@file).profile("default")
    assert_equal %i[shaky shaky], [profile.status(7, 8), profile.status(3, 4)]
  end

  def test_damaged_file_is_set_aside
    File.write(@file, "{ not json")
    store = TimesTable::Store.new(@file)
    assert store.corrupt?
    backup = store.save
    assert_match(/\A#{Regexp.escape(@file)}\.\d{8}-\d{6}\.bak\z/, backup)
    assert_equal "{ not json", File.read(backup)
    assert_equal 2, saved["version"]
  end
end

class PlannerTest < Minitest::Test
  def planner(profile, tables) = TimesTable::Planner.new(profile:, tables:, rng: Random.new(1))

  def test_due_facts_first_weakest_first
    profile = TimesTable::Profile.new("default", {})
    profile.record_right(2, 3, 0)  # box 1, due at session 2
    profile.record_wrong(2, 4, 0)  # box 0, due at session 1
    profile.record_wrong(9, 9, 0)  # other table, but shaky: still asked
    profile.record_right(8, 8, 0)  # other table, learning: not asked
    priority = planner(profile, [2]).priority(10)
    assert_equal [[2, 4], [9, 9]].sort, priority.sort
  end

  def test_fresh_has_no_repeats_until_the_pool_runs_out
    profile = TimesTable::Profile.new("default", {})
    facts = planner(profile, [3]).fresh(10)
    assert_equal 10, facts.uniq.size
    assert(facts.all? { |a, _| a == 3 })
  end

  def test_mastered_facts_come_last
    profile = TimesTable::Profile.new("default", {})
    (1..9).each { |b| [0, 2, 6].each { |session| profile.record_right(5, b, session) } }
    assert_equal [[5, 10]], planner(profile, [5]).tap { _1.priority(0) }.fresh(1)
  end
end

class SessionTest < Minitest::Test
  include Helpers

  def test_all_right
    output, input = run_cli("-t", "4", "-n", "5")
    assert_equal 5, questions(input).size
    assert_includes output, "Score: 5 / 5 right on the first try"
    assert_includes output, "Best streak this session: 5 in a row"
    assert_includes output, "🔥 5 in a row!"
    assert_includes output, "No mistakes at all!"
    profile = saved_profile
    assert_equal 1, profile["session_count"]
    assert_equal 5, profile["facts"].size
    assert(profile["facts"].values.all? { _1["box"] == 1 })
  end

  def test_wrong_answer_is_retried_flipped_and_confirmed
    first = true
    output, input = run_cli("-t", "7", "-n", "4") do |answer, _prompt|
      if first
        first = false
        answer + 1
      else
        answer
      end
    end
    missed = questions(input).first[/\d+ x \d+/]
    a, b = missed.split(" x ").map(&:to_i)
    asked = questions(input).map { _1[/\d+ x \d+/] }
    assert_equal 3, asked.count(missed), "asked, retried, then confirmed"
    assert_includes asked, "#{b} x #{a}" unless a == b
    assert_includes output, "Almost... #{a} x #{b} = #{a * b}."
    assert_includes output, "Well done! You got it now!"
    assert_includes output, "To practice a little more:\n  #{a} x #{b} = #{a * b}"
    assert_equal 0, saved_profile.dig("facts", "#{a}x#{b}", "box")
  end

  def test_flip_replaces_a_pending_question_on_the_same_fact
    first = nil
    _, input = run_cli("-t", "2,3", "-n", "20") do |answer, prompt|
      next answer if first

      first = prompt[/\d+ x \d+/]
      0
    end
    a, b = first.split(" x ")
    flipped = questions(input).count { _1.start_with?("#{b} x #{a} =") }
    assert_equal(a == b ? 3 : 1, flipped, "#{b} x #{a} asked once as the flip")
  end

  def test_misses_come_first_next_session
    missed = nil
    run_cli("-t", "6", "-n", "3") do |answer, prompt|
      next answer if missed

      missed = prompt[/\d+ x \d+/]
      0
    end
    output, input = run_cli("-t", "2", "-n", "3")
    assert_includes output, "First, 1 to review from last time."
    assert_equal missed, questions(input).first[/\d+ x \d+/]
  end

  def test_slow_answer_is_accepted_but_not_automatic
    output, = run_cli("-t", "3", "-n", "2", "--think", "5", seconds_per_answer: 6)
    assert_includes output, "Right! Next time, try to answer before the timer runs out."
    assert_includes output, "Score: 2 / 2"
    assert_includes output, "Right, but not automatic yet:"
    assert(saved_profile["facts"].values.all? { _1["box"].zero? && _1["slow"] == 1 })
  end

  def test_no_timer_counts_slow_answers_like_fast_ones
    output, = run_cli("-t", "3", "-n", "2", "--no-timer", seconds_per_answer: 60)
    refute_includes output, "not automatic"
    refute_includes output, "before the timer runs out"
    assert(saved_profile["facts"].values.all? { _1["box"] == 1 && _1["slow"].zero? })
  end

  def test_invalid_input_is_asked_again
    replies = ["abc", "", "-1"]
    output, = run_cli("-t", "2", "-n", "1") { |answer, _| replies.shift || answer }
    assert_equal 3, output.scan("Please type just a number.").size
    assert_includes output, "Score: 1 / 1"
  end

  def test_quit_saves_progress
    count = 0
    output, = run_cli("-t", "5", "-n", "10") { |answer, _| (count += 1) > 3 ? "q" : answer }
    assert_includes output, "See you soon!"
    assert_includes output, "Score: 3 / 3"
    assert_equal 3, saved_profile["facts"].size
  end

  def test_quit_at_the_tables_prompt
    output, = run_cli { nil }
    assert_includes output, "Which tables"
    assert_includes output, "See you soon!"
    refute File.exist?(@file)
  end

  def test_tables_prompt_asks_again
    replies = %w[nope 3]
    output, input = run_cli("-n", "2") { |answer, _| replies.shift || answer }
    assert_includes output, "I didn't get that."
    assert(questions(input).all? { _1.start_with?("3 x") })
  end

  def test_division_and_missing_number_modes
    _, input = run_cli("-t", "8", "-n", "3", "-m", "divide")
    assert(questions(input).all? { _1.include?("÷ 8 = ?") })
    output, input = run_cli("-t", "8", "-n", "6", "-m", "missing")
    assert(questions(input).all? { _1.include?("x ?") || _1.start_with?("? x") })
    assert_includes output, "Score: 6 / 6"
  end

  def test_challenge
    output, input = run_cli("-t", "9", "-c", "30", seconds_per_answer: 4)
    assert_equal 8, questions(input).size
    assert_includes output, "Time's up!"
    assert_includes output, "Right answers: 7 in 30 seconds", "the answer at 32 s is too late"
    assert_includes output, "🏆 New record!"
    assert_equal 7, saved_profile.dig("challenge_best", "30")
    output, = run_cli("-t", "9", "-c", "30", seconds_per_answer: 4)
    assert_includes output, "Your record: 7 right answers."
  end

  def test_mastered_today
    6.times { run_cli("-t", "1", "-n", "10") }
    output, = run_cli("--stats")
    assert_includes output, "Mastered: 0/100", "right answers in sessions 1, 3, 7 are needed"
    output, = run_cli("-t", "1", "-n", "10")
    assert_includes output, "⭐ Mastered today:"
    output, = run_cli("--stats")
    assert_includes output, "Mastered: 10/100"
    assert_includes output, "Recent sessions:"
    assert_equal 7, saved_profile["session_count"]
    assert_equal 10, saved_profile["sessions"].last["mastered"].size
  end

  def test_profiles_and_spanish
    output, = run_cli("-t", "2", "-n", "2", "-p", "Ana", "-l", "es")
    assert_includes output, "¡Hola Ana!"
    assert_includes output, "Puntuación: 2 / 2 a la primera"
    assert saved_profile("ana")
    assert_nil saved_profile
    output, = run_cli("--stats", "-p", "ana", "-l", "es")
    assert_includes output, "Progreso de Ana"
  end
end

# Drives the real script in a pseudo-terminal to check the live countdown and animations.
class TerminalTest < Minitest::Test
  include Helpers

  def test_live_answer_in_a_terminal
    require "pty"
    script = File.expand_path("../times_table.rb", __dir__)
    env = { "TIMES_TABLE_FILE" => @file }
    transcript = +""
    PTY.spawn(env, RbConfig.ruby, script, "-t", "6", "-n", "2", "--think", "30") do |reader, writer, pid|
      wrong = true
      loop do
        screen = read_until(reader, transcript, /(\d+ x \d+ = \?|Score)/)
        break if screen.include?("Score")

        a, b = screen.scan(/(\d+) x (\d+) = \?/).last.map(&:to_i)
        writer.write(wrong ? "9x#{a * b + 1}\r" : "#{a * b}\r") # junk keys are ignored
        read_until(reader, transcript, wrong ? /Almost/ : /⭐/)
        wrong = false
      end
      read_until(reader, transcript, /average/i)
      Process.wait(pid)
    end
    plain = transcript.gsub(/\e\[[\d;?]*[A-Za-z]/, "")
    assert_match(/█+░*\s+\d+s  6 x \d+ = \?/, plain, "countdown bar")
    assert_includes plain, "✗  Almost..."
    assert_includes plain, "✓ "
    right, asked = plain[%r{Score: (\d+ / \d+) right on the first try}, 1].split(" / ").map(&:to_i)
    assert_equal asked - 1, right, "only the first answer was wrong"
    assert_includes transcript, "\e[?25h", "cursor shown again"
  end

  def test_no_timer_hides_the_countdown
    require "pty"
    script = File.expand_path("../times_table.rb", __dir__)
    transcript = +""
    PTY.spawn({ "TIMES_TABLE_FILE" => @file }, RbConfig.ruby, script, "-t", "4", "-n", "1", "--no-timer") do |reader, writer, pid|
      screen = read_until(reader, transcript, /\d+ x \d+ = \?/)
      a, b = screen.scan(/(\d+) x (\d+) = \?/).last.map(&:to_i)
      writer.write("#{a * b}\r")
      read_until(reader, transcript, /average/i)
      Process.wait(pid)
    end
    refute_match(/[█░]|take your time/, transcript)
    assert_includes transcript, "Score"
  end

  private

  def read_until(reader, transcript, pattern, timeout: 10)
    deadline = Time.now + timeout
    start = @seen || 0
    until (plain = transcript[start..].gsub(/\e\[[\d;?]*[A-Za-z]/, "")).match?(pattern)
      raise "timed out waiting for #{pattern.inspect}:\n#{plain}" if Time.now > deadline
      next unless IO.select([reader], nil, nil, 0.1)

      transcript << reader.read_nonblock(4096).force_encoding(Encoding::UTF_8)
    end
    @seen = transcript.length
    plain
  rescue EOFError, Errno::EIO
    plain
  end
end
