
path = require 'path'

{SourceMapConsumer} = require 'source-map'
_ = require 'lodash'
chalk = require 'chalk'
stripPath = require 'strip-path'

class LintErrorOutput
  constructor: (@result, @options, @grunt) ->

  display: (importsToLint) ->
    sourceMap = new SourceMapConsumer(@result.sourceMap)

    # Keep track of number of errors & warnings displayed = total issues
    issueCounts = {
      warnings: 0,
      errors: 0
    }

    # Shorthand references to result values
    messages = @result.lint.messages
    less = @result.less
    file = path.resolve(@result.file)

    filePath = stripPath(file, process.cwd())
    fileContents = {}
    fileLines = {}

    # Filter out imports we didn't pass as options.import
    messages = messages.filter (message) =>
      # Account for 0 line and rollup errors (Too many selectors rules, global rules)
      return true if message.line == 0 or message.rollup

      {source} = sourceMap.originalPositionFor
        line: message.line,
        column: message.col

      # Skip if we couldnt find a source file for the error
      if source == null
        return false

      # Fix path delimiter issues
      if source
        source = path.resolve source

      isThisFile = source == file

      # Prepare two versions of file path for matching,
      # one with preceding slash and one without
      sourceArray = [
        stripPath(source, process.cwd()),
        stripPath(source, process.cwd() + '\\')
      ]

      return isThisFile or @grunt.file.isMatch(importsToLint, sourceArray)

    # Bug out if only import errors we don't care about
    return issueCounts if messages.length < 1

    # make sure the messages are filtered out for formatters
    @result.lint.messages = messages

    # Group the errors by message
    messageGroups = _.groupBy messages, ({message, rule, type}) ->
      fullMsg = "#{message}"
      fullMsg = "#{fullMsg}" if type? and type.length isnt 0
      fullMsg += " #{rule.desc}" if rule.desc and rule.desc isnt message
      fullMsg

    # Output how many rules broken
    @grunt.log.writeln("#{chalk.yellow(filePath)} (#{messages.length})")

    # For each rule message and messages
    for fullRuleMessage, ruleMessages of messageGroups
      # Parse the rule and description
      rule = ruleMessages[0].rule

      # Output the rule broken
      @grunt.log.writeln(fullRuleMessage + chalk.grey(" (#{rule.id})"))

      for message in ruleMessages
        # count all failed rules configured to "warning" vs "error"
        if message.type is 'error'
          issueCounts.errors += 1
        else
          issueCounts.warnings += 1

        # Account for global errors and rollup errors, don't show source line
        continue if message.line == 0 or message.rollup

        # Grab the original contents
        {line, column, source} = sourceMap.originalPositionFor
          line: message.line,
          column: message.col

        isThisFile = source == file

        # Store this for later access by reporters
        message.lessLine = { line, column }

        # Get the contents and split into lines if not already done
        unless fileContents[source]
          if isThisFile
            # We can avoid a file read if this is our current file
            fileContents[source] = less
          else
            # Otherwise, read from disk
            fileContents[source] = @grunt.file.read source

          # Pre-emptively split into lines
          fileLines[source] = fileContents[source].split('\n')

        filePath = stripPath(source, process.cwd())
        lessSource = fileLines[source][line-1].slice(column)

        # Output the source line
        output = chalk.gray("#{filePath} [Line #{line}, Column #{column+1}]:\t")+ " #{lessSource.trim()}"
        if @options.failOnError && (message.type is 'error' || @options.failOnWarning)
          @grunt.log.error(output)
        else
          @grunt.log.writeln("   " + output)

    issueCounts

module.exports = LintErrorOutput
