# frozen_string_literal: true

require "json"
require "strscan"

# Transforms a string into a form
module Parser
  class UnexpectedEofError < StandardError
  end
  class BadParseError < StandardError
  end

  IGNORED_REGEXP = /\A(?:\s+|;.*$)*/ # comments, whitespace
  NUMBER_REGEXP = /\A(?:-)?[0-9]*(?:.[0-9]+)?(?:e[0-9]+(?:.[0-9]+)?)?\z/
  REGEXP_REGEXP = /
    \A
    (?:
      \/(?:\\.|[^\\\/])*\/
    | %r\{(?:\\.|[^\\}])*}
    )[imxo]*
  /mx
  STRING_REGEXP = /\A"(?:\\.|[^\\"])*"\z/

  TOKEN_REGEXP = /
    #{IGNORED_REGEXP}
    (
      ,@ | [()'`,]      # unquote-splicing, parens, quote, quasiquote, unquote
    | #{NUMBER_REGEXP}
    | #{REGEXP_REGEXP}
    | #{STRING_REGEXP}
    | [^\s;()'`,]+      # identifiers
    )
  /x

  def self.parse(str)
    tokens = lex(str)
    forms = [:begin]
    forms << read_form!(tokens) until tokens.empty?
    forms.freeze
  end

  def self.parse_single_form(str)
    tokens = lex(str)
    read_form!(tokens).freeze
  end

  private_class_method def self.lex(str)
    scanner = StringScanner.new(str)
    tokens = []

    until scanner.eos?
      unless scanner.scan(TOKEN_REGEXP)
        break if IGNORED_REGEXP =~ scanner.rest

        raise BadParseError
      end

      tokens << scanner[1]
    end

    tokens
  end

  private_class_method def self.parse_regexp_source(source)
    case source[0]
    when "/"
      split_idx = source.rindex("/")
      re = source[1..split_idx - 1]
    when "%"
      split_idx = source.rindex("}")
      re = source[3..split_idx - 1]
    else
      raise BadParseError
    end

    options = source[split_idx + 1..-1]&.chars&.reduce(0) { |acc, c|
      case c
      when "i"
        acc | Regexp::IGNORECASE
      when "m"
        acc | Regexp::MULTILINE
      when "x"
        acc | Regexp::EXTENDED
      else
        acc
      end
    }

    Regexp.new(re, options)
  end

  private_class_method def self.parse_string_source(source)
    JSON.parse(source)
  end

  private_class_method def self.read_form!(tokens)
    raise UnexpectedEofError if tokens.empty?

    token = tokens.shift

    case token
    when "", ")"
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
    when NUMBER_REGEXP
      token.to_f
    when REGEXP_REGEXP
      parse_regexp_source(token)
    when STRING_REGEXP
      parse_string_source(token)
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
