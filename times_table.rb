#!/usr/bin/env ruby
# frozen_string_literal: true

# Times-table practice for primary-school kids.
#
# Usage:
#   ruby times_table.rb
#   ruby times_table.rb --tables 2,5,7 --questions 30
#
# Missed questions are saved to ~/.times_table.json and asked first next time.
# Type "q" at any prompt to quit.

require "json"
require "optparse"

module TimesTable
  SAVE_FILE = File.join(Dir.home, ".times_table.json")
  ALL_TABLES = (1..10).to_a
  MULTIPLIERS = (1..10).to_a
  DEFAULT_QUESTIONS = 20

  CHEERS = ["Well done!", "Great job!", "Awesome!", "Perfect!", "You're a star!"].freeze

  class Quit < StandardError; end

  module Color
    CODES = { green: 32, red: 31, yellow: 33, cyan: 36, bold: 1 }.freeze

    def self.enabled?
      $stdout.tty? && !ENV.key?("NO_COLOR")
    end

    CODES.each do |name, code|
      define_singleton_method(name) do |text|
        enabled? ? "\e[#{code}m#{text}\e[0m" : text.to_s
      end
    end
  end

  # Persists missed questions as [[a, b], ...].
  module Store
    def self.load
      data = JSON.parse(File.read(SAVE_FILE))
      Array(data["missed"]).filter_map do |pair|
        a, b = pair
        [a, b] if a.is_a?(Integer) && b.is_a?(Integer)
      end
    rescue Errno::ENOENT, JSON::ParserError, TypeError, NoMethodError
      []
    end

    def self.save(missed)
      File.write(SAVE_FILE, JSON.pretty_generate("missed" => missed.uniq))
    rescue SystemCallError => e
      warn "Could not save missed questions: #{e.message}"
    end
  end

  class Session
    def initialize(tables:, count:)
      @tables = tables
      @count = count
      @previous_misses = Store.load
      @missed = []           # questions missed this session (in order, unique)
      @mastered = []         # previous misses answered right this session
      @first_try_right = 0
      @asked = 0             # distinct questions seen at least once
      @answers = 0
      @queue = build_queue
      @total = @queue.size
    end

    def run
      puts
      puts Color.bold("Let's practice! #{@total} questions. (Type \"q\" to quit)")
      puts Color.yellow("First, #{@priority_count} you missed last time. You can do it!") if @priority_count.positive?
      puts

      @started_at = now
      ask_all
      finish(completed: true)
    rescue Quit
      finish(completed: false)
    end

    private

    def build_queue
      priority = @previous_misses.first(@count)
      @priority_count = priority.size
      # Draw from a shuffled pool so questions don't repeat until the pool runs out.
      pool = []
      fresh = Array.new(@count - priority.size) do
        pool = @tables.product(MULTIPLIERS).shuffle if pool.empty?
        pool.pop
      end
      # Each entry: [a, b, first_attempt?]
      (priority + fresh).map { |a, b| [a, b, true] }
    end

    def ask_all
      until @queue.empty?
        a, b, first = @queue.shift
        ask(a, b, first)
      end
    end

    def ask(a, b, first)
      answer = Input.number("#{a} x #{b} = ? ")
      @answers += 1
      @asked += 1 if first

      if answer == a * b
        @first_try_right += 1 if first
        @mastered << [a, b] if first && @previous_misses.include?([a, b])
        puts Color.green(first ? CHEERS.sample : "Well done! You got it now!")
      else
        puts Color.red("Almost... #{a} x #{b} = #{a * b}. We'll try it again later!")
        @missed << [a, b] unless @missed.include?([a, b])
        # Ask again later: a few questions from now, or at the end.
        @queue.insert([@queue.size, 3].min, [a, b, false])
      end
    end

    def finish(completed:)
      elapsed = @started_at ? now - @started_at : 0
      save_progress

      puts
      puts completed ? Color.bold("All done! 🎉") : Color.bold("See you soon!")
      puts "Score: #{Color.cyan("#{@first_try_right} / #{@asked}")} right on the first try" if @asked.positive?
      puts "Total time: #{format_time(elapsed)}"
      puts "Average time per answer: #{format_time(elapsed / @answers)}" if @answers.positive?

      if @missed.empty?
        puts Color.green("No mistakes at all! Amazing!") if @answers.positive?
      else
        puts "To practice a little more:"
        @missed.each { |a, b| puts "  #{a} x #{b} = #{Color.yellow(a * b)}" }
        puts "Next time we'll start with these. Keep it up!"
      end
    end

    # Keep this session's misses, plus old misses not yet answered right.
    def save_progress
      Store.save(@missed + (@previous_misses - @mastered))
    end

    def format_time(seconds)
      seconds = seconds.round(1)
      return "#{seconds} s" if seconds < 60

      minutes, secs = seconds.divmod(60)
      "#{minutes.to_i} min #{secs.round} s"
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  module Input
    # Reads a line; raises Quit on "q", Ctrl-D or Ctrl-C.
    def self.line(prompt)
      print prompt
      text = $stdin.gets
      raise Quit if text.nil?

      text = text.strip
      raise Quit if text.casecmp?("q")

      text
    rescue Interrupt
      puts
      raise Quit
    end

    def self.number(prompt)
      loop do
        text = line(prompt)
        return text.to_i if text.match?(/\A\d+\z/)

        puts Color.yellow("Please type just a number.")
      end
    end

    def self.tables
      loop do
        text = line("Which tables do you want to practice? (e.g. 2 5 7, or \"all\"): ")
        tables = TimesTable.parse_tables(text)
        return tables if tables

        puts Color.yellow("I didn't get that. Type numbers from 1 to 10, or \"all\".")
      end
    end
  end

  # Returns a sorted array of tables, or nil if the input is invalid.
  def self.parse_tables(text)
    text = text.to_s.strip.downcase
    return ALL_TABLES if %w[all todo tout].include?(text)

    parts = text.split(/[\s,;]+/).reject(&:empty?)
    return nil if parts.empty? || !parts.all? { |p| p.match?(/\A\d+\z/) }

    tables = parts.map(&:to_i).uniq.sort
    tables.all? { |t| ALL_TABLES.include?(t) } ? tables : nil
  end

  def self.parse_options(argv)
    options = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: ruby times_table.rb [--tables 2,5,7] [--questions 30]"
      opts.on("-t", "--tables LIST", "Tables to practice (e.g. 2,5,7 or all)") do |v|
        options[:tables] = parse_tables(v) or abort "Invalid tables: #{v} (use numbers from 1 to 10)"
      end
      opts.on("-n", "--questions N", Integer, "Number of questions (default #{DEFAULT_QUESTIONS})") do |v|
        abort "The number of questions must be greater than 0" unless v.positive?
        options[:questions] = v
      end
      opts.on("-h", "--help", "Show this help") do
        puts opts
        exit
      end
    end.parse!(argv)
    options
  rescue OptionParser::ParseError => e
    abort "#{e.message}\nUsage: ruby times_table.rb [--tables 2,5,7] [--questions 30]"
  end

  def self.main(argv)
    options = parse_options(argv)
    puts Color.bold("✖️  Hi! Let's practice the times tables.")
    tables = options[:tables] || Input.tables
    Session.new(tables: tables, count: options[:questions] || DEFAULT_QUESTIONS).run
  rescue Quit
    puts "See you soon!"
  end
end

$stdout.sync = true
TimesTable.main(ARGV) if $PROGRAM_NAME == __FILE__
