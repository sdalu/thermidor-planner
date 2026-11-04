# frozen_string_literal: true

require "test_helper"

# README's example runs, and says what it gives: each `expr  # => value`
# line of it is evaluated and compared.
class ReadmeTest < Minitest::Test
    README = File.read(File.expand_path("../README.md", __dir__))

    def test_the_example_gives_what_it_says
        code = example
        context = binding
        context.eval(code)
        assert_equal 4, claims(code).size
        claims(code).each do |expression, value|
            assert_equal context.eval(value), context.eval(expression),
                         expression
        end
    end

    private

    # The Ruby block under "A room, its devices, a plan", its result
    # lines' comments kept.
    def example
        section = README[/^## A room, its devices, a plan\n(.*?)^## /m, 1]
        section[/^```ruby\n(.*?)^```/m, 1]
    end

    # [[expression, value], ...] from "expr  # => value", the value going
    # on over the "#     ..." lines that follow.
    def claims(code)
        code.scan(/^(\S.*?)\s+# => (.*(?:\n#     .*)*)/).map do |expr, value|
            [expr, value.gsub(/\n#\s+/, " ")]
        end
    end
end
