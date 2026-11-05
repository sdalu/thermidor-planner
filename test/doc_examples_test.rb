# frozen_string_literal: true

require "test_helper"

# doc/'s examples run, and say what they give: each page's Ruby blocks
# naming the planner (P::) are evaluated after README's setup, page by
# page in one binding, and each `expr  # => value` is compared.
class DocExamplesTest < Minitest::Test
    ROOT   = File.expand_path("..", __dir__)
    README = File.read(File.join(ROOT, "README.md"))
    PAGES  = Dir[File.join(ROOT, "doc", "*.md")]

    def test_every_page_s_examples_give_what_they_say
        context = prelude
        checked = PAGES.sum { |page| check(page, context) }
        pages = PAGES.count { |page| examples(page).any? }
        assert_operator checked, :>=, pages
    end

    private

    # The claims checked on page, its blocks run in order.
    def check(page, context)
        examples(page).sum do |code|
            context.eval(code, page)
            claims(code).each do |expression, value|
                assert_equal context.eval(value), context.eval(expression),
                             "#{File.basename(page)}: #{expression}"
            end.size
        end
    end

    # A binding holding README example's setup: P, S, Caps and the two
    # sets of caps.
    def prelude
        context = Object.new.instance_eval { binding }
        context.eval(README[%r{^require "thermidor/planner"\n.*?(?=^valve =)}m])
        context
    end

    def examples(page)
        File.read(page).scan(/^```ruby\n(.*?)^```/m).flatten
            .select { it.include?("P::") }
    end

    # [[expression, value], ...] from "expr  # => value", the value going
    # on over the "#     ..." lines that follow.
    def claims(code)
        code.scan(/^(\S.*?)\s+# => (.*(?:\n#     .*)*)/).map do |expr, value|
            [expr, value.gsub(/\n#\s+/, " ")]
        end
    end
end
