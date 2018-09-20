#!/usr/bin/env ruby
# frozen_string_literal: true

if $PROGRAM_NAME == __FILE__
  # running interactively, bootstrap into bundler context
  require "bundler/setup"
end

require_relative "parser"

# High-level REPL interface
module REPL
  def self.repl(source)
    if source.respond_to?(:readline)
      tty = source_is_tty?(source)

      loop do
        rep(source, tty: tty)
      end

      print "\n" if tty
    else
      noninteractive(source)
    end
  end

  private_class_method def self.source_is_tty?(source)
    source.respond_to?(:tty?) && source.tty? ||
    source.respond_to?(:file) && source.file&.tty?
  end

  private_class_method def self.rep(source, tty: source_is_tty?(source))
    print "user> " if tty
    raise StopIteration if source.eof?

    input = source.readline
    puts Parser.parse(input).inspect
  end

  private_class_method def self.noninteractive(source)
    source = source.read if source.respond_to?(:read)

    form = Parser.parse(source)
    puts form.inspect
  end
end

if $PROGRAM_NAME == __FILE__
  # running interactively, run repl
  REPL.repl(ARGF)
end
