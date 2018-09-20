# frozen_string_literal: true

require "json"
require "strscan"

# Namespace for functions parsing strings into Sapphire forms
module Parser
  # Error raised when parsing expects content but finds end of file
  class UnexpectedEofError < StandardError
  end
  # Error raised when parsing receives unexpected or malformed content
  class BadParseError < StandardError
  end

  BINARY_DIGIT_REGEXP =  /[01]|(?:[01]_[01])/
  DECIMAL_DIGIT_REGEXP = /[0-9]|(?:[0-9]_[0-9])/
  HEX_DIGIT_REGEXP =     /[0-9a-f]|(?:[0-9a-f]_[0-9a-f])/i
  OCTAL_DIGIT_REGEXP =   /[0-7]|(?:_[0-7])/

  BINARY_NUMBER_REGEXP = /0b#{BINARY_DIGIT_REGEXP}+/i
  DECIMAL_NUMBER_REGEXP = /
    #{DECIMAL_DIGIT_REGEXP}*\.?#{DECIMAL_DIGIT_REGEXP}+
    (?:e[-+]?#{DECIMAL_DIGIT_REGEXP}*\.?#{DECIMAL_DIGIT_REGEXP}+)?
  /ix
  HEX_NUMBER_REGEXP = /0x#{HEX_DIGIT_REGEXP}+/i
  OCTAL_NUMBER_REGEXP = /0#{OCTAL_DIGIT_REGEXP}+/

  # Matches numbers, no distinction between integers and floats
  # @todo Figure out how to make e.g. (+1 2) => 3 work, right now
  #       `+1` parses as an integer, but do we want (-1 2) => 1 or
  #       (-1 2) => can't call integer -1?
  #       consider: integer call is implicitly add
  NUMBER_REGEXP = /
    \A
    [-+]?
    (?:
      #{BINARY_NUMBER_REGEXP}
    | #{DECIMAL_NUMBER_REGEXP}
    | #{HEX_NUMBER_REGEXP}
    | #{OCTAL_NUMBER_REGEXP}
    )
    \z
  /x

  # Matches ruby-style-delimited regular expression syntax
  REGEXP_REGEXP = /
    \A
    (?:
      \/(?:\\.|[^\\\/])*\/
    | %r\{(?:\\.|[^\\}])*}
    )[imxo]*
    \z
  /mx
  # Matches strings, including escaping
  STRING_REGEXP = /\A"(?:\\.|[^\\"])*"\z/

  # Matches comments and whitespace
  IGNORED_REGEXP = /\A(?:\s+|;.*$)*/

  # Matches any Sapphire token, skipping whitespace and comments
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

  # Parses a top-level Sapphire form into ruby objects
  # @param [String] str string to parse forms from
  # @return [Symbol, Array<Object>]
  # @raise [UnexpectedEofError]
  # @raise [BadParseError]
  def self.parse(str)
    tokens = lex(str)
    forms = [:begin]
    forms << read_form!(tokens) until tokens.empty?
    forms.freeze
  end

  # Parses a Sapphire form into a ruby object
  # @todo Don't lex the entire string just to read a form off the front
  # @param [String] str string to parse form from
  # @return [Array<Object>]
  # @raise [UnexpectedEofError]
  # @raise [BadParseError]
  def self.parse_single_form(str)
    tokens = lex(str)
    read_form!(tokens).freeze
  end

  # @param [String] str
  # @return [Array<String>]
  def self.lex(str)
    scanner = StringScanner.new(str)
    tokens = []

    until scanner.eos?
      if scanner.scan(TOKEN_REGEXP)
        tokens << scanner[1]
      else
        scanner.scan(IGNORED_REGEXP)
        scanner.eos? and break or raise BadParseError
      end
    end

    tokens
  end
  private_class_method :lex

  # @param [String] source
  # @return [Numeric] source parsed as a number
  def self.parse_number_source(source)
    if source.index(/[.e]/i) && !source.index(/x/i)
      Float(source)
    else
      Integer(source)
    end
  end

  # @param [String] options
  # @return [Numeric] regexp options suitable to pass to {Regexp.new}
  # @example
  #   nil => 0
  #   "ix" => {Regexp::IGNORECASE} | {Regexp::EXTENDED}
  def self.parse_regexp_options(options)
    options&.chars&.reduce(0) { |acc, c|
      case c
      when "i" then acc | Regexp::IGNORECASE
      when "m" then acc | Regexp::MULTILINE
      when "x" then acc | Regexp::EXTENDED
      else acc
      end
    }
  end
  private_class_method :parse_regexp_options

  # @param [String] source full regexp token
  # @return [Regexp] parsed regexp
  # @example
  #   "/abc/i" => /abc/i
  def self.parse_regexp_source(source)
    case source[0]
    when "/"
      split_idx = source.rindex("/")
      re = source[1..split_idx - 1]
    when "%"
      split_idx = source.rindex("}")
      re = source[3..split_idx - 1]
    else raise BadParseError
    end

    Regexp.new(re, parse_regexp_options(source[split_idx + 1..-1]))
  end
  private_class_method :parse_regexp_source

  # @param [String] source
  # @return [String] parsed string
  # @example
  #   '"a\\"b"' #=> 'a"b'
  def self.parse_string_source(source)
    JSON.parse(source)
  end
  private_class_method :parse_string_source

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/MethodLength
  # @param [Array<String>] tokens
  # @return [Object] tokens parsed into ruby objects
  def self.read_form!(tokens)
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
      parse_number_source(token)
    when REGEXP_REGEXP
      parse_regexp_source(token)
    when STRING_REGEXP
      parse_string_source(token)

    else
      token.to_sym
    end.freeze
  end
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
  private_class_method :read_form!

  # @param [Array<String>] tokens
  # @return [Array<Object>] tokens read into a list as forms
  def self.read_list!(tokens)
    res = []
    until tokens.first == ")"
      raise UnexpectedEofError if tokens.first.nil?

      res << read_form!(tokens)
    end
    tokens.shift
    res
  end
  private_class_method :read_list!
end
