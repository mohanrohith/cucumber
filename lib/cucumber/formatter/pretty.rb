require 'cucumber/formatter/console'
require 'fileutils'

module Cucumber
  module Formatter
    # The formatter used for <tt>--format pretty</tt> (the default formatter).
    #
    # This formatter prints features to plain text - exactly how they were parsed,
    # just prettier. That means with proper indentation and alignment of table columns.
    #
    # If the output is STDOUT (and not a file), there are bright colours to watch too.
    #
    class Pretty
      include FileUtils
      include Console
      attr_writer :indent
      attr_reader :step_mother

      def initialize(step_mother, io, options)
        @step_mother, @io, @options = step_mother, io, options
        @exceptions = []
        @indent = 0
        @prefixes = options[:prefixes] || {}
      end

      def after_visit_features(features)
        print_summary(features) unless @options[:autoformat]
      end

      def before_visit_feature(feature)
        @exceptions = []
        @indent = 0
        if @options[:autoformat]
          file = File.join(@options[:autoformat], feature.file)
          dir = File.dirname(file)
          mkdir_p(dir) unless File.directory?(dir)
          @io = File.open(file, Cucumber.file_mode('w'))
        end
      end
      
      def after_visit_feature(*args)
        @io.close if @options[:autoformat]
      end

      def visit_comment_line(comment_line)
        @io.puts(comment_line.indent(@indent))
        @io.flush
      end

      def after_visit_tags(tags)
        if @indent == 1
          @io.puts
          @io.flush
        end
      end

      def visit_tag_name(tag_name)
        tag = format_string("@#{tag_name}", :tag).indent(@indent)
        @io.print(tag)
        @io.flush
        @indent = 1
      end

      def visit_feature_name(name)
        @io.puts(name)
        @io.puts
        @io.flush
      end

      def before_visit_feature_element(feature_element)
        record_tag_occurrences(feature_element, @options)
        @indent = 2
        @scenario_indent = 2
      end
      
      def after_visit_feature_element(feature_element)
        @io.puts
        @io.flush
      end

      def before_visit_background(background)
        @indent = 2
        @scenario_indent = 2
        @in_background = true
      end

      def after_visit_background(background)
        @in_background = nil
        @io.puts
        @io.flush
      end

      def visit_background_name(keyword, name, file_colon_line, source_indent)        
        print_feature_element_name(keyword, name, file_colon_line, source_indent)
      end

      def before_visit_examples_array(examples_array)
        @indent = 4
        @io.puts
        @visiting_first_example_name = true
      end
      
      def visit_examples_name(keyword, name)
        puts unless @visiting_first_example_name
        @visiting_first_example_name = false
        names = name.strip.empty? ? [name.strip] : name.split("\n")
        @io.puts("    #{keyword} #{names[0]}")
        names[1..-1].each {|s| @io.puts "      #{s}" } unless names.empty?
        @io.flush
        @indent = 6
        @scenario_indent = 6
      end
      
      def before_visit_outline_table(outline_table)
        @table = outline_table
      end

      def after_visit_outline_table(outline_table)
        @indent = 4
      end
      
      def visit_scenario_name(keyword, name, file_colon_line, source_indent)
        print_feature_element_name keyword, name, file_colon_line, source_indent
      end

      def before_visit_step(step)
        @current_step = step
        @indent = 6
      end

      def before_visit_step_result(keyword, step_match, multiline_arg, status, exception, source_indent, background)
        @hide_this_step = false
        if exception
          if @exceptions.include?(exception)
            @hide_this_step = true
            return
          end
          @exceptions << exception
        end
        if status != :failed && @in_background ^ background
          @hide_this_step = true
          return
        end
        @status = status
      end

      def visit_step_name(keyword, step_match, status, source_indent, background)
        return if @hide_this_step
        source_indent = nil unless @options[:source]
        formatted_step_name = format_step(keyword, step_match, status, source_indent)
        @io.puts(formatted_step_name.indent(@scenario_indent + 2))
      end

      def before_visit_multiline_arg(multiline_arg)
        return if @options[:no_multiline] or @hide_this_step
        @table = multiline_arg
      end

      def visit_exception(exception, status)
        return if @hide_this_step
        print_exception(exception, status, @indent)
        @io.flush
      end

      def before_visit_table_row(table_row)
        @col_index = 0
        @io.print '  |'.indent(@indent-2)
      end

      def after_visit_table_row(table_row)
        @io.puts
        if table_row.exception && !@exceptions.include?(table_row.exception)
          print_exception(table_row.exception, :failed, @indent)
        end
      end

      def visit_py_string(string)
        s = %{"""\n#{string}\n"""}.indent(@indent)
        s = s.split("\n").map{|l| l =~ /^\s+$/ ? '' : l}.join("\n")
        @io.puts(format_string(s, @current_step.status))
        @io.flush
      end

      def after_visit_table_cell(cell)
        @col_index += 1
      end

      def visit_table_cell_value(value, status)
        status ||= @status || :passed
        width = @table.col_width(@col_index)
        cell_text = value.to_s || ''
        padded = cell_text + (' ' * (width - cell_text.jlength))
        prefix = cell_prefix(status)
        @io.print(' ' + format_string("#{prefix}#{padded}", status) + ::Term::ANSIColor.reset(" |"))
        @io.flush
      end

      private
      
      def success?(status)
        status != :failed
      end
      
      def print_feature_element_name(keyword, name, file_colon_line, source_indent)
        @io.puts if @scenario_indent == 6
        names = name.empty? ? [name] : name.split("\n")
        line = "#{keyword} #{names[0]}".indent(@scenario_indent)
        @io.print(line)
        if @options[:source]
          line_comment = " # #{file_colon_line}".indent(source_indent)
          @io.print(format_string(line_comment, :comment))
        end
        @io.puts
        names[1..-1].each {|s| @io.puts "    #{s}"}
        @io.flush        
      end

      def cell_prefix(status)
        @prefixes[status]
      end

      def print_summary(features)
        print_stats(features)
        print_snippets(@options)
        print_passing_wip(@options)
        print_tag_limit_warnings(@options)
      end

    end
  end
end
