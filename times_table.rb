#!/usr/bin/env ruby
# frozen_string_literal: true

# Times-table practice for primary-school kids.
#
#   ruby times_table.rb                       # asks which tables to practice
#   ruby times_table.rb -t 2,5,7 -n 30        # skip the question
#   ruby times_table.rb --help                # all options
#
# Progress is saved to ~/.times_table.json (or $TIMES_TABLE_FILE).
# Type "q" at any prompt to quit.

if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")
  abort "times_table.rb needs Ruby 3.3 or later (this is Ruby #{RUBY_VERSION})."
end

require "io/console"
require "json"
require "optparse"

module TimesTable
  ALL_TABLES = (1..10).to_a.freeze
  MULTIPLIERS = (1..10).to_a.freeze
  DEFAULT_QUESTIONS = 20
  DEFAULT_THINK_SECONDS = 8        # slower answers are right, but not automatic yet
  DEFAULT_CHALLENGE_SECONDS = 60
  MASTERED_BOX = 3                 # Leitner box at which a fact counts as mastered
  BOX_INTERVALS = [1, 2, 4, 8].freeze # sessions before a fact is due again, by box
  STREAK_STEP = 5
  MODES = %w[multiply missing divide mixed].freeze
  LANGS = %w[en es].freeze
  DEFAULT_PROFILE = "default"
  MAX_SAVED_SESSIONS = 100

  MESSAGES = {
    "en" => {
      hello: "✖️  Hi%{name}! Let's practice the times tables.",
      which_tables: 'Which tables do you want to practice? (e.g. 2 5 7, or "all"): ',
      bad_tables: 'I didn\'t get that. Type numbers from 1 to 10, or "all".',
      number_only: "Please type just a number.",
      start: 'Let\'s practice! %{count} questions. (Type "q" to quit)',
      start_challenge: 'Challenge! Answer as many as you can in %{seconds} seconds. (Type "q" to quit)',
      challenge_record: "Your record: %{best} right answers.",
      review: "First, %{count} to review from last time. You can do it!",
      cheers: ["Well done!", "Great job!", "Awesome!", "Perfect!", "You're a star!"],
      slow: "Right! Next time, try to answer before the timer runs out.",
      take_your_time: "⏳ take your time",
      now_right: "Well done! You got it now!",
      wrong: "Almost... %{solved}. We'll try it again soon!",
      streak: "🔥 %{count} in a row!",
      mastered_now: "⭐ New fact mastered: %{fact}!",
      time_up: "⏰ Time's up!",
      done: "All done! 🎉",
      bye: "See you soon!",
      score: "Score: %{right} / %{asked} right on the first try",
      challenge_score: "Right answers: %{right} in %{seconds} seconds",
      new_challenge_record: "🏆 New record!",
      total_time: "Total time: %{time}",
      avg_time: "Average time per answer: %{time}",
      best_streak: "Best streak this session: %{count} in a row",
      new_streak_record: "🏆 New personal best: %{count} in a row!",
      mastered_today: "⭐ Mastered today: %{list}",
      no_mistakes: "No mistakes at all! Amazing!",
      to_practice: "To practice a little more:",
      slow_list: "Right, but not automatic yet: %{list}",
      next_time: "Next time we'll start with these. Keep it up!",
      stats_title: "Progress for %{name}",
      stats_title_default: "Your progress",
      legend: "%{mastered} mastered  %{learning} learning  %{shaky} needs practice  %{unseen} not seen yet",
      counts: "Mastered: %{mastered}/100 · Learning: %{learning} · Needs practice: %{shaky} · Not seen yet: %{unseen}",
      record_streak: "Best streak ever: %{count} in a row",
      record_challenge: "Challenge record (%{seconds} s): %{best}",
      recent: "Recent sessions:",
      no_sessions: "No sessions yet. Time to practice!",
      save_error: "Could not save progress: %{error}",
      corrupt: "The progress file was damaged, so it was moved to %{path} and a new one was started.",
      modes: { "multiply" => "multiply", "missing" => "missing number", "divide" => "divide", "mixed" => "mixed" }
    },
    "es" => {
      hello: "✖️  ¡Hola%{name}! Vamos a repasar las tablas de multiplicar.",
      which_tables: '¿Qué tablas quieres repasar? (ej: 2 5 7, o "todo"): ',
      bad_tables: 'No entendí. Escribe números del 1 al 10, o "todo".',
      number_only: "Escribe solo un número, por favor.",
      start: '¡Vamos a practicar! %{count} preguntas. (Escribe "q" para salir)',
      start_challenge: '¡Desafío! Responde todas las que puedas en %{seconds} segundos. (Escribe "q" para salir)',
      challenge_record: "Tu récord: %{best} respuestas correctas.",
      review: "Primero repasamos %{count} de la última vez. ¡Tú puedes!",
      cheers: ["¡Bien!", "¡Muy bien!", "¡Genial!", "¡Perfecto!", "¡Eres una estrella!"],
      slow: "¡Correcto! La próxima vez, intenta responder antes de que se acabe el tiempo.",
      take_your_time: "⏳ tómate tu tiempo",
      now_right: "¡Bien! ¡Ahora sí!",
      wrong: "Casi... %{solved}. ¡Lo volveremos a intentar pronto!",
      streak: "🔥 ¡%{count} seguidas!",
      mastered_now: "⭐ ¡Nueva tabla dominada: %{fact}!",
      time_up: "⏰ ¡Se acabó el tiempo!",
      done: "¡Terminaste! 🎉",
      bye: "¡Hasta pronto!",
      score: "Puntuación: %{right} / %{asked} a la primera",
      challenge_score: "Respuestas correctas: %{right} en %{seconds} segundos",
      new_challenge_record: "🏆 ¡Nuevo récord!",
      total_time: "Tiempo total: %{time}",
      avg_time: "Tiempo medio por respuesta: %{time}",
      best_streak: "Mejor racha de hoy: %{count} seguidas",
      new_streak_record: "🏆 ¡Nuevo récord personal: %{count} seguidas!",
      mastered_today: "⭐ Dominadas hoy: %{list}",
      no_mistakes: "¡No fallaste ninguna! ¡Increíble!",
      to_practice: "Para practicar un poco más:",
      slow_list: "Correctas, pero todavía no automáticas: %{list}",
      next_time: "La próxima vez empezaremos por estas. ¡Ánimo!",
      stats_title: "Progreso de %{name}",
      stats_title_default: "Tu progreso",
      legend: "%{mastered} dominada  %{learning} aprendiendo  %{shaky} por practicar  %{unseen} sin ver",
      counts: "Dominadas: %{mastered}/100 · Aprendiendo: %{learning} · Por practicar: %{shaky} · Sin ver: %{unseen}",
      record_streak: "Mejor racha: %{count} seguidas",
      record_challenge: "Récord del desafío (%{seconds} s): %{best}",
      recent: "Últimas sesiones:",
      no_sessions: "Todavía no hay sesiones. ¡A practicar!",
      save_error: "No se pudo guardar el progreso: %{error}",
      corrupt: "El archivo de progreso estaba dañado: se movió a %{path} y se empezó uno nuevo.",
      modes: { "multiply" => "multiplicar", "missing" => "número que falta", "divide" => "dividir", "mixed" => "mezcla" }
    }
  }.freeze

  class Quit < StandardError; end

  def self.default_file
    ENV.fetch("TIMES_TABLE_FILE") { File.join(Dir.home, ".times_table.json") }
  end

  def self.monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Returns a sorted array of tables, or nil if the input is invalid.
  def self.parse_tables(text)
    text = text.to_s.strip.downcase
    return ALL_TABLES.dup if %w[all todo todas].include?(text)

    parts = text.split(/[\s,;]+/).reject(&:empty?)
    return nil if parts.empty? || !parts.all? { |part| part.match?(/\A\d+\z/) }

    tables = parts.map(&:to_i).uniq.sort
    tables.all? { |table| ALL_TABLES.include?(table) } ? tables : nil
  end

  def self.format_time(seconds)
    seconds = seconds.round(1)
    return "#{seconds} s" if seconds < 60

    minutes, secs = seconds.divmod(60)
    "#{minutes.to_i} min #{secs.round} s"
  end

  # One question about the fact a x b, asked in one of several forms.
  Question = Data.define(:a, :b, :kind) do
    def self.kinds_for(mode)
      case mode
      when "multiply" then %i[multiply]
      when "missing" then %i[missing_a missing_b]
      when "divide" then %i[divide]
      else %i[multiply missing_a missing_b divide]
      end
    end

    def product = a * b

    def answer
      case kind
      when :multiply then product
      when :missing_a then a
      when :missing_b, :divide then b
      end
    end

    # The question with "?" where the answer goes.
    def template
      case kind
      when :multiply then "#{a} x #{b} = ?"
      when :missing_a then "? x #{b} = #{product}"
      when :missing_b then "#{a} x ? = #{product}"
      when :divide then "#{product} ÷ #{a} = ?"
      end
    end

    def fill(slot) = template.sub("?") { slot }
    def solved = fill(answer.to_s)
    def label = "#{a} x #{b}"

    def flipped
      swapped = { missing_a: :missing_b, missing_b: :missing_a }.fetch(kind, kind)
      with(a: b, b: a, kind: swapped)
    end
  end

  # Terminal output: messages, colors and animations.
  class UI
    STYLES = { green: 32, red: 31, yellow: 33, magenta: 35, cyan: 36, bold: 1, dim: 2 }.freeze
    FEEDBACK_COLORS = { right: :green, slow: :yellow, wrong: :red }.freeze
    BANNER_COLORS = { streak: :magenta, mastered: :yellow, time_up: :red }.freeze
    CLEAR_LINE = "\r\e[2K"

    attr_reader :input, :output

    def initialize(input:, output:, lang: "en", color: nil, animate: true, sleeper: nil)
      @input = input
      @output = output
      @messages = MESSAGES.fetch(lang)
      @color = color.nil? ? output.tty? && !ENV.key?("NO_COLOR") : color
      @animate = animate && interactive?
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    def interactive? = input.tty? && output.tty?
    def animate? = @animate

    def t(key, **vars)
      text = @messages.fetch(key)
      vars.empty? ? text : format(text, **vars)
    end

    def cheer(rng) = @messages[:cheers].sample(random: rng)
    def mode_name(mode) = @messages[:modes].fetch(mode, mode)

    def line(text = "") = output.puts(text)
    def say(key, *styles, **vars) = line(paint(t(key, **vars), *styles))

    def paint(text, *styles)
      codes = styles.compact.map { |style| STYLES.fetch(style) }
      return text.to_s if !@color || codes.empty?

      "\e[#{codes.join(';')}m#{text}\e[0m"
    end

    # Reads a line in normal (cooked) mode. Raises Quit on "q", Ctrl-C or Ctrl-D.
    def ask_line(prompt)
      output.print prompt
      text = input.gets
      raise Quit if text.nil?

      text = text.strip
      raise Quit if text.casecmp?("q")

      text
    rescue Interrupt
      line
      raise Quit
    end

    def ask_number(prompt)
      loop do
        text = ask_line(prompt)
        return text.to_i if text.match?(/\A\d+\z/)

        say(:number_only, :yellow)
      end
    end

    # Feedback after an answer, on the same line as the answered question.
    def feedback(answered, text, effect)
      color = FEEDBACK_COLORS.fetch(effect)
      unless animate?
        prefix = interactive? ? "  " : ""
        return line("#{prefix}#{paint(text, color)}")
      end

      quietly { effect == :wrong ? shake(answered, text) : sparkle(answered, text, effect) }
    end

    def banner(text, effect)
      color = BANNER_COLORS.fetch(effect)
      return line(paint(text, color, :bold)) unless animate?

      quietly do
        3.times do
          frame(paint(text, color, :bold))
          pause(0.12)
          frame(paint(text, :dim))
          pause(0.08)
        end
      end
      finish_frame(paint(text, color, :bold))
    end

    def confetti(rng)
      return unless animate?

      pieces = %w[* + • ✦ ·]
      colors = %i[green red yellow magenta cyan]
      quietly do
        8.times do
          frame(Array.new(32) { rng.rand < 0.5 ? " " : paint(pieces.sample(random: rng), colors.sample(random: rng)) }.join)
          pause(0.08)
        end
      end
      output.print CLEAR_LINE
    end

    def frame(text) = output.print("#{CLEAR_LINE}#{text}")
    def finish_frame(text) = output.print("#{CLEAR_LINE}#{text}\n")
    def pause(seconds) = @sleeper.call(seconds)

    private

    # Keys pressed during an animation are not echoed (LiveInput drops them).
    def quietly(&) = input.noecho(&)

    # Frames redraw one screen row, so a line that wraps can't be animated.
    def fits?(text)
      width = begin
        output.winsize[1]
      rescue StandardError
        0
      end
      width = 80 unless width.positive? # unknown size
      text.gsub(/\e\[[\d;?]*[A-Za-z]/, "").length + 3 < width
    end

    def sparkle(answered, text, effect)
      color = FEEDBACK_COLORS.fetch(effect)
      icon = effect == :slow ? "⏳" : "✓"
      message = ->(shown) { "#{answered}  #{paint("#{icon} #{shown}", color, :bold)}" }
      final = effect == :slow ? message.call(text) : "#{message.call(text)} ⭐"
      return finish_frame(final) unless fits?(final)

      1.upto(text.length) do |i|
        frame(message.call(text[0, i]))
        pause(0.012)
      end
      return finish_frame(final) if effect == :slow

      %w[✨ ⭐ 🌟 ✨].each do |star|
        frame("#{message.call(text)} #{star}")
        pause(0.07)
      end
      finish_frame(final)
    end

    def shake(answered, text)
      [2, 0, 2, 0, 1, 0].each do |offset|
        frame("#{' ' * offset}#{paint(answered, :red, :bold)}  ✗")
        pause(0.05)
      end
      finish_frame("#{paint(answered, :red, :bold)}  ✗  #{paint(text, :red)}")
    end
  end

  # Reads an answer key by key in a terminal, redrawing a countdown bar.
  class LiveInput
    TICK = 0.1
    BAR_WIDTH = 10
    HIDE_CURSOR = "\e[?25l"
    SHOW_CURSOR = "\e[?25h"

    def initialize(ui, clock)
      @ui = ui
      @clock = clock
    end

    # Returns the number typed, or nil if the challenge time ran out first.
    # Only digits are kept; "q" then Enter quits, and so do Ctrl-C and Ctrl-D.
    def read(question, think:, challenge_left: nil)
      buffer = +""
      timed_out = false
      started = @clock.call
      @ui.output.print HIDE_CURSOR
      @ui.input.iflush # drop keys pressed during the last animation
      @ui.input.raw do |io|
        keys = KeyReader.new
        loop do
          if challenge_left && challenge_left.call <= 0
            timed_out = true
            return nil
          end

          draw(question, buffer, @clock.call - started, think, challenge_left)
          next unless IO.select([io], nil, nil, TICK)

          keys.feed(io.read_nonblock(32, exception: false).to_s) do |key|
            case key
            when :enter
              raise Quit if buffer == "q"
              return buffer.to_i unless buffer.empty?
            when :quit then raise Quit
            when :backspace then buffer.chop!
            when "q", "Q" then buffer.replace("q")
            when /\A\d\z/
              buffer.clear if buffer == "q"
              buffer << key if buffer.size < 3
            end
          end
        end
      end
    ensure
      @ui.frame(question.fill(buffer.to_s.empty? ? "?" : buffer))
      @ui.output.print SHOW_CURSOR
      @ui.output.print "\n" if timed_out
    end

    # Turns raw terminal input into keys, swallowing escape sequences
    # (arrows, Delete, F-keys...) so their digits don't end up in the answer.
    class KeyReader
      def initialize = @escape = nil

      def feed(chunk)
        chunk.each_char do |char|
          key = translate(char)
          yield key if key
        end
        @escape = nil if @escape == :start # a lone Esc key, not a sequence
      end

      private

      def translate(char)
        case @escape
        when :start
          @escape = ["[", "O"].include?(char) ? :sequence : nil
          return nil
        when :sequence
          @escape = nil if char.ord.between?(0x40, 0x7e)
          return nil
        end

        case char
        when "\e"
          @escape = :start
          nil
        when "\r", "\n" then :enter
        when "\u0003", "\u0004" then :quit
        when "\u007f", "\b" then :backspace
        else char
        end
      end
    end

    private

    def draw(question, buffer, elapsed, think, challenge_left)
      slot = @ui.paint(buffer.empty? ? "?" : buffer, :bold, :cyan)
      text = "#{timer(think - elapsed, think)}  #{question.fill(slot)}"
      text += "   #{@ui.paint("⏰ #{challenge_left.call.ceil} s", :magenta)}" if challenge_left
      @ui.frame(text)
    end

    def timer(left, think)
      return @ui.paint(@ui.t(:take_your_time).ljust(BAR_WIDTH + 4), :dim) if left <= 0

      filled = (left / think * BAR_WIDTH).ceil.clamp(1, BAR_WIDTH)
      color = if filled > BAR_WIDTH / 2 then :green
              elsif filled > BAR_WIDTH / 4 then :yellow
              else :red
              end
      "#{@ui.paint('█' * filled, color)}#{@ui.paint('░' * (BAR_WIDTH - filled), :dim)} #{left.ceil.to_s.rjust(2)}s"
    end
  end

  # One child's progress: a Leitner box per fact, plus session history.
  class Profile
    FACT_KEY = /\A(\d+)x(\d+)\z/

    attr_reader :key

    def initialize(key, data)
      @key = key
      @data = data
      @data["facts"] = sanitize_facts(@data["facts"])
      @data["sessions"] = Array(@data["sessions"]).grep(Hash)
      @data["session_count"] = integer(@data["session_count"], @data["sessions"].size)
      @data["best_streak"] = integer(@data["best_streak"], 0)
      best = @data["challenge_best"]
      @data["challenge_best"] = best.is_a?(Hash) ? best.select { |_, value| value.is_a?(Integer) } : {}
    end

    def display_name = @data["display_name"]
    def session_number = @data["session_count"] + 1
    def sessions = @data["sessions"]
    def best_streak = @data["best_streak"]
    def challenge_best(seconds) = @data["challenge_best"][seconds.to_s]
    def challenge_records = @data["challenge_best"]
    def fact(a, b) = @data["facts"]["#{a}x#{b}"]

    def status(a, b)
      fact = fact(a, b)
      return :unseen unless fact
      return :mastered if fact["box"] >= MASTERED_BOX

      fact["box"].zero? ? :shaky : :learning
    end

    def due_facts(session = session_number)
      @data["facts"].filter_map do |key, fact|
        key.split("x").map(&:to_i) if fact["due"] <= session
      end
    end

    # Fast and right on the first try: move up one box, but only once the fact
    # is due, so a fact needs right answers in well-spaced sessions to be mastered.
    # Returns true when this makes the fact mastered.
    def record_right(a, b, session)
      fact = fact!(a, b)
      fact["seen"] += 1
      return false if fact["promoted"] == session || fact["due"] > session

      before = fact["box"]
      fact["box"] = [before + 1, MASTERED_BOX].min
      fact["promoted"] = session
      fact["due"] = session + BOX_INTERVALS[fact["box"]]
      before < MASTERED_BOX && fact["box"] == MASTERED_BOX
    end

    # Right but slow: not automatic yet, so it stays in its box and comes back soon.
    def record_slow(a, b, session)
      fact = fact!(a, b)
      fact["seen"] += 1
      fact["slow"] += 1
      fact["due"] = session + 1
    end

    def record_wrong(a, b, session)
      fact = fact!(a, b)
      fact["seen"] += 1
      fact["wrong"] += 1
      fact["box"] = 0
      fact["due"] = session + 1
    end

    # Stores the session and returns which records it broke.
    def add_session(record)
      records = {}
      if record["best_streak"] >= STREAK_STEP && record["best_streak"] > best_streak
        records[:streak] = true
        @data["best_streak"] = record["best_streak"]
      end
      if (seconds = record["challenge"]) && record["right"].positive?
        previous = challenge_best(seconds)
        if previous.nil? || record["right"] > previous
          records[:challenge] = true
          @data["challenge_best"][seconds.to_s] = record["right"]
        end
      end
      @data["session_count"] += 1
      @data["sessions"] = (sessions + [record]).last(MAX_SAVED_SESSIONS)
      records
    end

    private

    def fact!(a, b) = @data["facts"]["#{a}x#{b}"] ||= new_fact
    def new_fact = { "box" => 0, "due" => 0, "seen" => 0, "wrong" => 0, "slow" => 0 }
    def integer(value, default) = value.is_a?(Integer) ? value : default

    def sanitize_facts(facts)
      return {} unless facts.is_a?(Hash)

      facts.each_with_object({}) do |(key, fact), clean|
        match = FACT_KEY.match(key.to_s)
        next unless match && fact.is_a?(Hash)
        next unless ALL_TABLES.include?(match[1].to_i) && MULTIPLIERS.include?(match[2].to_i)

        values = fact.slice(*new_fact.keys).select { |_, value| value.is_a?(Integer) }
        entry = new_fact.merge(values)
        entry["box"] = entry["box"].clamp(0, MASTERED_BOX)
        entry["promoted"] = fact["promoted"] if fact["promoted"].is_a?(Integer)
        clean[key.to_s] = entry
      end
    end
  end

  # The progress file, with every child's profile.
  class Store
    VERSION = 2

    attr_reader :path

    def initialize(path)
      @path = path
      @corrupt = false
      @data = load
    end

    def corrupt? = @corrupt

    def profile(key, display_name = nil)
      data = (@data["profiles"][key] ||= {})
      data["display_name"] ||= display_name if display_name
      Profile.new(key, data)
    end

    # Writes atomically. Returns the backup path if a damaged file was set aside.
    def save
      backup = set_aside_damaged_file
      tmp = "#{path}.tmp"
      File.write(tmp, JSON.pretty_generate(@data))
      File.rename(tmp, path)
      backup
    end

    private

    def empty = { "version" => VERSION, "profiles" => {} }

    def load
      return empty unless File.exist?(path)

      migrate(JSON.parse(File.read(path)))
    rescue JSON::ParserError, EncodingError
      @corrupt = true
      empty
    end

    def migrate(raw)
      if raw.is_a?(Hash) && raw["version"] == VERSION && raw["profiles"].is_a?(Hash)
        raw["profiles"].select! { |_, profile| profile.is_a?(Hash) }
        raw
      elsif raw.is_a?(Hash) && raw["missed"].is_a?(Array)
        from_v1(raw["missed"])
      else
        @corrupt = true
        empty
      end
    end

    # Version 1 only kept a list of missed questions: [[7, 8], ...].
    def from_v1(missed)
      facts = missed.each_with_object({}) do |pair, result|
        next unless pair.is_a?(Array) && pair.size == 2 && pair.all?(Integer)

        result["#{pair[0]}x#{pair[1]}"] = { "box" => 0, "due" => 0, "seen" => 1, "wrong" => 1 }
      end
      { "version" => VERSION, "profiles" => { DEFAULT_PROFILE => { "facts" => facts } } }
    end

    def set_aside_damaged_file
      return unless @corrupt && File.exist?(path)

      backup = "#{path}.#{Time.now.strftime('%Y%m%d-%H%M%S')}.bak"
      File.rename(path, backup)
      @corrupt = false
      backup
    end
  end

  # Chooses which facts to ask.
  class Planner
    def initialize(profile:, tables:, rng:)
      @profile = profile
      @tables = tables
      @rng = rng
      @pool = []
      @used = []
    end

    # Facts due for review: weakest first. Misses from other tables count too.
    def priority(limit)
      due = @profile.due_facts.select do |a, b|
        @tables.include?(a) || (@profile.status(a, b) == :shaky && @profile.fact(a, b)["wrong"].positive?)
      end
      due = due.sort_by do |a, b|
        fact = @profile.fact(a, b)
        [fact["box"], -fact["wrong"], -fact["slow"], @rng.rand]
      end
      @used = due.first(limit)
    end

    # Random facts from the chosen tables, without repeats until the pool runs out.
    # Mastered facts come last.
    def fresh(count)
      Array.new(count) do
        if @pool.empty?
          @pool = build_pool
          @pool.rotate! if @pool.size > 1 && @pool.first == @last
        end
        @last = @pool.shift
      end
    end

    private

    def build_pool
      pairs = @tables.product(MULTIPLIERS) - @used
      @used = []
      pairs = @tables.product(MULTIPLIERS) if pairs.empty?
      mastered, rest = pairs.shuffle(random: @rng).partition { |a, b| @profile.status(a, b) == :mastered }
      rest + mastered
    end
  end

  # One practice session.
  class Session
    Item = Data.define(:question, :attempt, :tries) # attempt: :first, :flip, :retry or :confirm

    FIRST_ATTEMPTS = %i[first flip].freeze
    RETRY_GAP = 2     # questions before a missed one comes back (grows with each miss)
    FLIP_GAP = 4      # after missing 7 x 8, ask 8 x 7 this many questions later
    CONFIRM_GAP = 5   # after getting a miss right, check it once more later
    CHALLENGE_BATCH = 10

    attr_reader :asked, :first_try_right, :right_answers, :answers, :missed, :slow, :mastered_today, :best_streak

    def initialize(profile:, ui:, tables:, count: DEFAULT_QUESTIONS, mode: "multiply", challenge: nil,
                   think: DEFAULT_THINK_SECONDS, clock: TimesTable.method(:monotonic), rng: Random.new)
      @profile = profile
      @ui = ui
      @tables = tables
      @mode = mode
      @challenge = challenge
      @think = think
      @clock = clock
      @rng = rng
      @session = profile.session_number
      @planner = Planner.new(profile:, tables:, rng:)
      @live = ui.interactive? ? LiveInput.new(ui, clock) : nil
      @asked = @first_try_right = @right_answers = @answers = 0
      @streak = @best_streak = 0
      @missed = []
      @slow = []
      @mastered_today = []
      @flipped = {}
      @queue = initial_queue(count)
    end

    def run
      @started = @clock.call
      completed = begin
        intro
        while (item = next_item)
          ask(item)
        end
        @ui.banner(@ui.t(:time_up), :time_up) if challenge?
        true
      rescue Quit, Interrupt
        false
      end
      finish(completed:)
    end

    private

    def challenge? = !@challenge.nil?
    def challenge_left = @challenge - (@clock.call - @started)

    def initial_queue(count)
      size = challenge? ? CHALLENGE_BATCH : count
      priority = @planner.priority(size)
      @priority_count = priority.size
      (priority + @planner.fresh(size - priority.size)).map { |a, b| new_item(a, b) }
    end

    def new_item(a, b)
      Item.new(question: Question.new(a:, b:, kind: Question.kinds_for(@mode).sample(random: @rng)),
               attempt: :first, tries: 0)
    end

    def next_item
      if challenge?
        return nil if challenge_left <= 0

        @queue.concat(@planner.fresh(CHALLENGE_BATCH).map { |a, b| new_item(a, b) }) if @queue.empty?
      end
      @queue.shift
    end

    def intro
      @ui.line
      if challenge?
        @ui.say(:start_challenge, :bold, seconds: @challenge)
        best = @profile.challenge_best(@challenge)
        @ui.say(:challenge_record, :cyan, best:) if best
      else
        @ui.say(:start, :bold, count: @queue.size)
      end
      @ui.say(:review, :yellow, count: @priority_count) if @priority_count.positive?
      @ui.line
    end

    def ask(item)
      question = item.question
      started = @clock.call
      answer = read_answer(question)
      return if answer.nil? || (challenge? && challenge_left <= 0) # too late

      elapsed = @clock.call - started
      @answers += 1
      @asked += 1 if FIRST_ATTEMPTS.include?(item.attempt)
      answered = question.fill(answer.to_s)
      answer == question.answer ? right(item, elapsed, answered) : wrong(item, answered)
    end

    def read_answer(question)
      return @ui.ask_number("#{question.template} ") unless @live

      @live.read(question, think: @think, challenge_left: challenge? ? -> { challenge_left } : nil)
    end

    def right(item, elapsed, answered)
      question = item.question
      @right_answers += 1
      case item.attempt
      when :first, :flip
        @first_try_right += 1
        elapsed > @think ? slow_answer(question, answered) : fast_answer(question, answered)
      when :retry
        @ui.feedback(answered, @ui.t(:now_right), :right)
        schedule(item.with(attempt: :confirm, tries: 0), CONFIRM_GAP)
      when :confirm
        @ui.feedback(answered, @ui.cheer(@rng), :right)
      end
      bump_streak
    end

    def fast_answer(question, answered)
      @ui.feedback(answered, @ui.cheer(@rng), :right)
      return unless @profile.record_right(question.a, question.b, @session)

      @mastered_today << question.label
      @ui.banner(@ui.t(:mastered_now, fact: question.label), :mastered)
    end

    def slow_answer(question, answered)
      @ui.feedback(answered, @ui.t(:slow), :slow)
      @profile.record_slow(question.a, question.b, @session)
      @slow << question.label unless @slow.include?(question.label)
    end

    def wrong(item, answered)
      question = item.question
      @streak = 0
      @ui.feedback(answered, @ui.t(:wrong, solved: question.solved), :wrong)
      if FIRST_ATTEMPTS.include?(item.attempt)
        @profile.record_wrong(question.a, question.b, @session)
        @missed << question unless @missed.any? { |missed| missed.label == question.label }
        schedule_flip(question) if item.attempt == :first
      end
      tries = item.attempt == :retry ? item.tries + 1 : 1
      schedule(Item.new(question:, attempt: :retry, tries:), RETRY_GAP * tries)
    end

    def schedule_flip(question)
      flipped = question.flipped
      return if question.a == question.b || @flipped[question.label]

      @flipped[question.label] = @flipped[flipped.label] = true
      @queue.reject! { |item| item.attempt == :first && item.question.label == flipped.label }
      schedule(Item.new(question: flipped, attempt: :flip, tries: 0), FLIP_GAP)
    end

    def schedule(item, gap)
      @queue.insert([gap, @queue.size].min, item)
    end

    def bump_streak
      @streak += 1
      @best_streak = [@best_streak, @streak].max
      @ui.banner(@ui.t(:streak, count: @streak), :streak) if (@streak % STREAK_STEP).zero?
    end

    def finish(completed:)
      elapsed = @clock.call - @started
      @ui.line
      return @ui.say(completed ? :done : :bye, :bold) if @answers.zero?

      records = @profile.add_session(session_record(elapsed))
      summary(completed, elapsed, records)
    end

    # Progress is already recorded, so Ctrl-C here only cuts the summary short.
    def summary(completed, elapsed, records)
      @ui.confetti(@rng) if completed && (@missed.empty? || records[:challenge])
      @ui.say(completed ? :done : :bye, :bold)
      print_score(elapsed, records)
      print_streak(records)
      print_lists
    rescue Interrupt
      @ui.line
    end

    def session_record(elapsed)
      {
        "date" => Time.now.strftime("%Y-%m-%d %H:%M"), "mode" => @mode, "tables" => @tables,
        "challenge" => @challenge, "asked" => @asked, "first_try" => @first_try_right,
        "right" => @right_answers, "answers" => @answers, "seconds" => elapsed.round(1),
        "best_streak" => @best_streak, "mastered" => @mastered_today
      }
    end

    def print_score(elapsed, records)
      if challenge?
        @ui.say(:challenge_score, right: @ui.paint(@right_answers, :cyan, :bold), seconds: @challenge)
        @ui.say(:new_challenge_record, :yellow, :bold) if records[:challenge]
      else
        @ui.say(:score, right: @ui.paint(@first_try_right, :cyan, :bold), asked: @asked)
      end
      @ui.say(:total_time, time: TimesTable.format_time(elapsed))
      @ui.say(:avg_time, time: TimesTable.format_time(elapsed / @answers))
    end

    def print_streak(records)
      return unless @best_streak > 1

      @ui.say(:best_streak, count: @best_streak)
      @ui.say(:new_streak_record, :yellow, :bold, count: @best_streak) if records[:streak]
    end

    def print_lists
      @ui.say(:mastered_today, :yellow, list: @mastered_today.join(", ")) if @mastered_today.any?
      if @missed.empty?
        @ui.say(:no_mistakes, :green) unless challenge?
      else
        @ui.say(:to_practice)
        @missed.each { |question| @ui.line("  #{@ui.paint(question.solved, :yellow)}") }
        @ui.say(:next_time)
      end
      @ui.say(:slow_list, :yellow, list: @slow.join(", ")) if @slow.any?
    end
  end

  # The --stats report: a 10 x 10 grid of facts, records and recent sessions.
  class Stats
    SYMBOLS = {
      mastered: ["★", :green], learning: ["●", :yellow], shaky: ["✗", :red], unseen: ["·", :dim]
    }.freeze
    RECENT = 8

    def initialize(profile, ui)
      @profile = profile
      @ui = ui
    end

    def render
      name = @profile.display_name
      @ui.line(@ui.paint(name ? @ui.t(:stats_title, name:) : @ui.t(:stats_title_default), :bold))
      @ui.line
      counts = grid
      @ui.line
      @ui.say(:legend, **SYMBOLS.to_h { |status, (symbol, color)| [status, @ui.paint(symbol, color)] })
      @ui.say(:counts, **counts)
      records
      recent
    end

    private

    def grid
      counts = SYMBOLS.keys.to_h { |status| [status, 0] }
      @ui.line("  x  #{MULTIPLIERS.map { |b| b.to_s.rjust(3) }.join}")
      ALL_TABLES.each do |a|
        cells = MULTIPLIERS.map do |b|
          status = @profile.status(a, b)
          counts[status] += 1
          symbol, color = SYMBOLS.fetch(status)
          "  #{@ui.paint(symbol, color)}"
        end
        @ui.line("#{a.to_s.rjust(3)}  #{cells.join}")
      end
      counts
    end

    def records
      @ui.line
      @ui.say(:record_streak, count: @profile.best_streak) if @profile.best_streak.positive?
      @profile.challenge_records.sort_by { |seconds, _| seconds.to_i }.each do |seconds, best|
        @ui.say(:record_challenge, seconds:, best:)
      end
    end

    def recent
      @ui.line
      sessions = @profile.sessions.last(RECENT)
      return @ui.say(:no_sessions) if sessions.empty?

      @ui.say(:recent, :bold)
      sessions.reverse_each do |session|
        score = if session["challenge"]
                  "#{session['right']} ✓ (⏰ #{session['challenge']} s)"
                else
                  "#{session['first_try']}/#{session['asked']}"
                end
        @ui.line("  #{session['date']}  #{@ui.mode_name(session['mode'].to_s).ljust(16)} #{score.ljust(14)} " \
                 "#{TimesTable.format_time(session['seconds'].to_f)}")
      end
    end
  end

  module CLI
    USAGE = "Usage: ruby times_table.rb [options]   (see --help)"

    def self.parse(argv)
      options = { questions: DEFAULT_QUESTIONS, mode: "multiply", lang: "en", think: DEFAULT_THINK_SECONDS,
                  animate: true, stats: false }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: ruby times_table.rb [options]"
        opts.on("-t", "--tables LIST", "Tables to practice, e.g. 2,5,7 or all") do |value|
          options[:tables] = TimesTable.parse_tables(value) or
            raise OptionParser::InvalidArgument, "#{value} (use numbers from 1 to 10)"
        end
        opts.on("-n", "--questions N", Integer, "Number of questions (default #{DEFAULT_QUESTIONS})") do |value|
          options[:questions] = positive!(value)
        end
        opts.on("-m", "--mode MODE", MODES, "multiply (default), missing (? x 6 = 42), divide or mixed") do |value|
          options[:mode] = value
        end
        opts.on("-c", "--challenge [SECONDS]", Integer,
                "Timed challenge: as many as possible (default #{DEFAULT_CHALLENGE_SECONDS} s)") do |value|
          options[:challenge] = positive!(value || DEFAULT_CHALLENGE_SECONDS)
        end
        opts.on("--think SECONDS", Integer,
                "Countdown before an answer counts as not automatic (default #{DEFAULT_THINK_SECONDS} s)") do |value|
          options[:think] = positive!(value)
        end
        opts.on("-p", "--name NAME", "Player name: each child gets their own progress") do |value|
          name = value.strip
          raise OptionParser::InvalidArgument, "the name can't be empty" if name.empty?

          options[:name] = name
        end
        opts.on("-l", "--lang LANG", LANGS, "Language: en (default) or es") { |value| options[:lang] = value }
        opts.on("-s", "--stats", "Show progress and exit") { options[:stats] = true }
        opts.on("--[no-]animations", "Animations in the terminal (default on)") { |value| options[:animate] = value }
        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit
        end
      end
      rest = parser.parse(argv)
      raise OptionParser::NeedlessArgument, rest.join(" ") unless rest.empty?

      options
    end

    def self.positive!(value)
      raise OptionParser::InvalidArgument, "#{value} (must be greater than 0)" unless value.positive?

      value
    end

    def self.main(argv)
      run(parse(argv))
    rescue OptionParser::ParseError => e
      abort "#{e.message}\n#{USAGE}"
    end

    def self.run(options, input: $stdin, output: $stdout, file: TimesTable.default_file,
                 clock: TimesTable.method(:monotonic), rng: Random.new, sleeper: nil)
      ui = UI.new(input:, output:, lang: options[:lang], animate: options[:animate], sleeper:)
      store = begin
        Store.new(file)
      rescue SystemCallError => e
        abort "Could not read the progress file #{file}: #{e.message}"
      end
      name = options[:name]
      profile = store.profile(name ? name.downcase : DEFAULT_PROFILE, name)
      return Stats.new(profile, ui).render if options[:stats]

      ui.say(:hello, :bold, name: name ? " #{name}" : "")
      tables = options[:tables] || ask_tables(ui)
      Session.new(profile:, ui:, tables:, count: options[:questions], mode: options[:mode],
                  challenge: options[:challenge], think: options[:think], clock:, rng:).run
      save(store, ui)
    rescue Quit, Interrupt
      ui.line
      ui.say(:bye)
    end

    def self.ask_tables(ui)
      loop do
        tables = TimesTable.parse_tables(ui.ask_line(ui.t(:which_tables)))
        return tables if tables

        ui.say(:bad_tables, :yellow)
      end
    end

    def self.save(store, ui)
      backup = store.save
      ui.say(:corrupt, :yellow, path: backup) if backup
    rescue SystemCallError => e
      ui.say(:save_error, :red, error: e.message)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.sync = true
  TimesTable::CLI.main(ARGV)
end
