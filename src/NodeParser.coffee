path = require 'path'


# Shell color manipulation tools.
colors =
  black: 30
  red: 31
  green: 32
  brown: 33
  blue: 34
  purple: 35
  cyan: 36
  gray: 37
  none: ''
  reset: 0


getColor = (color) ->
  colors[color.toString()] or colors.none


colorize = (text, color) ->
  "\x16[#{getColor(color)}m#{text}\x16[#{getColor('reset')}m"


spaces = (count) ->
  Array(+count + 1).join ' '


setter = (prop) -> (val) ->
  @[prop] = val
  this


booleanSetter = (prop) -> (val) ->
  @[prop] = !!val
  this


# Extends the object with properties from another object.
# Example
#   
#   extend {a: 5, b: 10}, {b: 15, c: 20, e: 50}
#   # => {a: 5, b: 15, c: 20, e: 50}
# 
extend = (obj, objects...) ->
  for object in objects
    obj[key] = val for own key, val of object
  obj


isEmptyObject = (object) ->
  return false for own key of object
  true


parseArgument = (str) ->
  charMatch = /^\-(\w+?)$/.exec str
  chars = charMatch and charMatch[1].split('')
  fullMatch = /^\-\-(no\-)?(.+?)(?:=(.+))?$/.exec str
  full = fullMatch and fullMatch[2]
  isValue = str? and (str is '' or /^[^\-].*/.test str)
  if isValue
    value = str
  else if full
    value = if fullMatch[1] then false else fullMatch[3]
  {str, chars, full, value, isValue}


parseOption = (opt = {}) ->
  strings = (opt.string or '').split(',')
  for string in strings
    string = string.trim()
    if matches = string.match /^\-([^-])(?:\s+(.*))?$/
      abbr = matches[1]
      metavar = matches[2]
    else if matches = string.match /^\-\-(.+?)(?:[=\s]+(.+))?$/
      full = matches[1]
      metavar or= matches[2]
  matches or= []
  abbr = opt.abbr or abbr
  full = opt.full or full
  metavar = opt.metavar or metavar
  if opt.string
    string = opt.string
  else if not opt.position?
    string = ''
    if abbr
      string += "-#{abbr}"
      string += " #{metavar}" if metavar
      string += ', '
    string += "--#{(full or opt.name)}"
    string += " #{metavar}" if metavar
  name = opt.name or full or abbr
  extend opt, {
    name, string, abbr, full, metavar,
    matches: (arg) ->
      arg in [opt.full, opt.abbr, opt.position, opt.name] or
      (opt.list and arg >= opt.position)
  }


class ArgumentParser
  constructor: ->
    return (new ArgumentParser arguments...) unless this instanceof ArgumentParser
    @commands = {}
    @commandAbbrs = {}
    @specs = {}

  command: (name) ->
    if name
      command = @commands[name] = 
        name: name
        specs: {}
    else
      command = @fallback = specs: {}

    chain = 
      options: (specs) ->
        command.specs = specs
        chain

      option: (name, spec) ->
        command.specs[name] = spec
        chain

      callback: (cb) ->
        command.cb = cb
        chain

      help: (help) ->
        command.help = help
        chain

      usage: (usage) ->
        command._usage = usage
        chain
        
      abbr: (abbr) =>
        command.abbr = abbr
        @commandAbbrs[abbr] = command
        chain

      # Old API.
      opts: (specs) ->
        @options specs
    chain

  nocommand: ->
    @command()

  options: setter "specs"
  usage: setter "_usage"
  printer: setter "print"
  script: setter "_script"
  help: setter "_help"
  withColors: booleanSetter "_withColors"
  commandRequired: booleanSetter "_commandRequired"

  option: (name, spec) ->
    @specs[name] = spec
    this

  _colorize: (text, color) ->
    if @_withColors then colorize(text, color) else text

  getUsage: ->
    return @command._usage if @command and @command._usage
    return @fallback._usage if @fallback and @fallback._usage
    return @_usage if @_usage

    indent = (str) -> spaces(2) + str
    str = "Usage: #{@_script}"

    positionals = @specs
      .filter((opt) -> opt.position?)
      .sort((left, right) -> left.position > right.position)
    options = @specs.filter (opt) -> not opt.position?

    if positionals.length
      for pos in positionals
        str += ' '
        posStr = pos.string or "<#{pos.name or "arg#{pos.position}"}>#{['...' if pos.list]}"
        str += posStr
    else if @_printAllCommands
      str += ' [command] [options]'
      str += '\n\nPossible commands are:\n'
      for name, command of @commands
        str += indent "#{@_script} #{command.name}"
        str += ": #{command.help}" if command.help
        str += " (short-cut alias: '#{command.abbr}')" if command.abbr
        str += '\n'
      str += "\nTo get help on individual command, execute '#{@_script} <command> --help'"

    str += @_colorize ' [options]', 'blue' if options.length
    str += '\n\n' if options.length or positionals.length

    # Get indentation of longest positional.
    longest = positionals.reduce ((max, pos) -> Math.max max, pos.name.length), 0
    for pos in positionals
      posStr = pos.string or pos.name
      str += posStr + spaces longest - posStr.length + 5
      str += @_colorize (pos.help or ''), 'gray'
      str += '\n'
    str += '\n' if positionals.length and options.length
    if options.length
      visible = (opt) -> not opt.hidden
      str += @_colorize 'Options:\n', 'blue'
      longest = options
        .filter(visible)
        .reduce ((max, opt) -> Math.max max, opt.string.length), 0
      str += options
        .filter(visible)
        .map (opt) =>
          indentation = spaces longest - opt.string.length
          help = @_colorize (opt.help or ''), 'gray'
          indent "#{opt.string} #{indentation} #{help}"
        .join('\n')
    str += "\n\nDescription:\n#{indent(@_help)}" if @_help
    str

  parse: (argv) ->
    @print ?= (str) ->
      console.log str
      process.exit 0

    @_help ?= ''
    @_script ?= "#{process.argv[0]} #{path.basename(process.argv[1])}"
    @specs ?= {}

    process.argv[2] = '--help' if @_commandRequired and not process.argv[2]

    argv ?= process.argv[2..]
    arg = parseArgument(argv[0]).isValue and argv[0]
    command = arg and @commands[arg] or @commandAbbrs[arg]
    commandExpected = not isEmptyObject @commands
    if commandExpected
      if command
        extend @specs, command.specs
        @_script += " #{command.name}"
        @_help = command.help if command.help
        @command = command
      else if arg
        return @print "#{@_script}: no such command '#{arg}'"
      else
        @_printAllCommands = yes
        if @fallback
          extend @specs, @fallback.specs
          @_help = @fallback.help
    unless @specs.length
      @specs = for key, value of @specs
        value.name = key
        value
    @specs = @specs.map parseOption

    return @print @getUsage() if '--help' in argv or '-h' in argv

    options = {}
    args = argv.map(parseArgument).concat parseArgument()
    positionals = []

    args.reduce (arg, val) =>
      if arg.isValue
        positionals.push arg.value
      else if arg.chars
        last = arg.chars.pop()
        for ch in arg.chars
          @setOption options, ch, true
        if @opt(last).flag
          @setOption options, last, true
        else if val.isValue
          @setOption options, last, val.value
          return parseArgument()
        else
          @print "'-#{(@opt(last).name or last)}' expects a value\n\n#{@getUsage()}"
      else if arg.full
        value = arg.value
        unless value?
          if @opt(arg.full).flag
            value = true
          else if val.isValue
            @setOption options, arg.full, val.value
            return parseArgument()
          else
            @print "'--#{(@opt(arg.full).name or arg.full)}' expects a value\n\n#{@getUsage()}"
        @setOption options, arg.full, value
      val

    for pos, index in positionals
      @setOption options, index, pos

    for opt in @specs when not options[opt.name]?
      if opt.default?
        options[opt.name] = opt.default
      else if opt.required
        @print "#{opt.name} argument is required\n\n#{@getUsage()}"
    if command?.cb?
      message = command.cb options
      @print message if typeof message is 'string'
    else if @fallback?.cb?
      @fallback.cb options
    options

  opt: (arg) ->
    match = parseOption()
    for opt in @specs when opt.matches arg
      match = opt
    match

  setOption: (options, arg, value) ->
    option = @opt arg
    if option.callback
      message = option.callback value
      @print message if typeof message is 'string'
    if option.type isnt 'string'
      try
        value = JSON.parse value
    name = option.name or arg
    if option.choices and value not in option.choices
      @print "#{name} must be one of: #{option.choices.join(', ')}"
    if option.list
      options[name] ?= []
      options[name].push value
    else
      options[name] = value

  # Old API.
  parseArgs: -> @parse arguments...
  scriptName: -> @script arguments...
  globalOpts: -> @options arguments...
  opts: -> @options arguments...
  colors: -> @withColors arguments...
  nom: (argv) -> @parse argv
  # Old API end.

  load: (config) ->
    for own name, data of config
      if name is 'commands'
        for own commandName, commandData of data
          command = @command commandName
          for own attrName, attrValue of commandData
            command[attrName] attrValue
      else
        try
          data = data this if typeof data is 'function'
          @[name] data
        catch error
    this


argumentParser = new ArgumentParser
for i, method of argumentParser when typeof method is 'function'
  ArgumentParser[i] = method.bind argumentParser

exports.ArgumentParser = ArgumentParser
exports.load = (config) ->
  (new ArgumentParser).load config
