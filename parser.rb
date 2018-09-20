# frozen_string_literal: true

require "json"
require "strscan"

# Transforms a string into a form
module Parser
  class UnexpectedEofError < StandardError
  end
  class BadParseError < StandardError
  end

  @token_regexp = /^(?:\s+|;.*$)*(,@|[()'`,]|"(?:\\.|[^\\"])*"|[^\s;()'`,]+)/
  @number_regexp = /^(?:-)?[0-9]*(?:.[0-9]+)?(?:e[0-9]+(?:.[0-9]+)?)?$/
  @string_regexp = /^"(?:\\.|[^\\"])*"$/

  def self.parse(str)
    tokens = lex(str)
    forms = [:begin]
    forms << read_form!(tokens) until tokens.empty?
    forms.freeze
  end

  private_class_method def self.lex(str)
    scanner = StringScanner.new(str)
    tokens = []

    until scanner.eos?
      break unless scanner.scan(@token_regexp)
      tokens << scanner[1]
    end

    tokens
  end

  private_class_method def self.read_form!(tokens)
    raise UnexpectedEofError if tokens.empty?
    token = tokens.shift

    case token
    when ""
      raise BadParseError
    when "("
      read_list!(tokens)
    when "nil"
      []
    when "#t"
      true
    when "#f"
      false
    when "'"
      [:quote, read_form!(tokens)]
    when "`"
      [:quasiquote, read_form!(tokens)]
    when ","
      [:unquote, read_form!(tokens)]
    when ",@"
      [:'unquote-splicing', read_form!(tokens)]
    when @number_regexp
      token.to_f
    when @string_regexp
      JSON.parse(token)
    else
      token.to_sym
    end.freeze
  end

  private_class_method def self.read_list!(tokens)
    res = []
    until tokens.first == ")"
      raise UnexpectedEofError if tokens.first.nil?
      res << read_form!(tokens)
    end
    tokens.shift
    res
  end
end
