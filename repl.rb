#!/usr/bin/env ruby
# frozen_string_literal: true

if $PROGRAM_NAME == __FILE__
  # running interactively, bootstrap into bundler
  require "rubygems"
  require "bundler/setup"
end

require_relative "parser"

# Namespace for the high-level REPL interface
module REPL
  # Runs a repl
  # @param [#eof? & #readline, #read, String] source source to read from
  # @return [NilClass]
  # @raise [Parser::BadParseError]
  def self.repl(source)
    if source.respond_to?(:eof?) && source.respond_to?(:readline) &&
       source_is_tty?(source)
      loop do
        rep(source)
      end

      print "\n"
    else
      noninteractive(source)
    end
  end

  # @param [#tty?, #file, Object] source
  # @return [true] source is a tty
  # @return [false] source is not a tty
  def self.source_is_tty?(source)
    source.respond_to?(:tty?) && source.tty? ||
      source.respond_to?(:file) && source.file&.tty?
  end
  private_class_method :source_is_tty?

  # @param [#eof? & #readline] source
  # @param [String] input text prepended to what is read
  # @return [NilClass]
  def self.rep(source, input: +"")
    print "user#{input.size.zero? ? '>' : '*'} "
    raise StopIteration if source.eof?

    input << source.readline
    begin
      puts Parser.parse(input).inspect
    rescue Parser::UnexpectedEofError
      rep(source, input: input)
    end
  end
  private_class_method :rep

  # execute source noninteractively
  # @param [#read, String] source
  # @return [NilClass]
  def self.noninteractive(source)
    source = source.read if source.respond_to?(:read)

    form = Parser.parse(source)
    puts form.inspect
  end
  private_class_method :noninteractive
end

if $PROGRAM_NAME == __FILE__
  # running interactively, run repl
  REPL.repl(ARGF)
end
