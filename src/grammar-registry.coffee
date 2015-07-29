_ = require 'underscore-plus'
{Emitter} = require 'event-kit'
{includeDeprecatedAPIs, deprecate} = require 'grim'
FirstMate = require 'first-mate'
Token = require './token'
fs = require 'fs-plus'

PathSplitRegex = new RegExp("[/.]")

# Extended: Syntax class holding the grammars used for tokenizing.
#
# An instance of this class is always available as the `atom.grammars` global.
#
# The Syntax class also contains properties for things such as the
# language-specific comment regexes. See {::getProperty} for more details.
module.exports =
class GrammarRegistry extends FirstMate.GrammarRegistry
  @deserialize: ({grammarOverridesByPath}) ->
    grammarRegistry = new GrammarRegistry()
    grammarRegistry.grammarOverridesByPath = grammarOverridesByPath
    grammarRegistry

  atom.deserializers.add(this)

  constructor: ->
    super(maxTokensPerLine: 100)

  serialize: ->
    {deserializer: @constructor.name, @grammarOverridesByPath}

  createToken: (value, scopes) -> new Token({value, scopes})

  # Extended: Select a grammar for the given file path and file contents.
  #
  # This picks the best match by checking the file path and contents against
  # each grammar.
  #
  # * `filePath` A {String} file path.
  # * `fileContents` A {String} of text for the file path.
  #
  # Returns a {Grammar}, never null.
  selectGrammar: (filePath, fileContents) ->
    bestMatch = null
    highestScore = -Infinity
    for grammar in @grammars
      score = @getGrammarScore(grammar, filePath, fileContents)
      if score > highestScore or not bestMatch?
        bestMatch = grammar
        highestScore = score
      else if score is highestScore and bestMatch?.bundledPackage
        bestMatch = grammar unless grammar.bundledPackage
    bestMatch

  # Extended: Returns a {Number} representing how well the grammar matches the
  # `filePath` and `contents`.
  getGrammarScore: (grammar, filePath, contents) ->
    contents = fs.readFileSync(filePath, 'utf8') if not contents? and fs.isFileSync(filePath)

    if @grammarOverrideForPath(filePath) is grammar.scopeName
      2 + (filePath?.length ? 0)
    else if @grammarMatchesContents(grammar, contents)
      1 + (filePath?.length ? 0)
    else
      @getGrammarPathScore(grammar, filePath)

  getGrammarPathScore: (grammar, filePath) ->
    return -1 unless filePath
    filePath = filePath.replace(/\\/g, '/') if process.platform is 'win32'

    pathComponents = filePath.toLowerCase().split(PathSplitRegex)
    pathScore = -1

    fileTypes = grammar.fileTypes
    if customFileTypes = atom.config.get('core.fileTypesByScope')?[grammar.scopeName]
      fileTypes = fileTypes.concat(customFileTypes)

    for fileType, i in fileTypes
      fileTypeComponents = fileType.toLowerCase().split(PathSplitRegex)
      pathSuffix = pathComponents[-fileTypeComponents.length..-1]
      if _.isEqual(pathSuffix, fileTypeComponents)
        pathScore = Math.max(pathScore, fileType.length)
        if i >= grammar.fileTypes.length
          pathScore += 0.5

    pathScore

  grammarMatchesContents: (grammar, contents) ->
    return false unless contents? and grammar.firstLineRegex?

    escaped = false
    numberOfNewlinesInRegex = 0
    for character in grammar.firstLineRegex.source
      switch character
        when '\\'
          escaped = not escaped
        when 'n'
          numberOfNewlinesInRegex++ if escaped
          escaped = false
        else
          escaped = false
    lines = contents.split('\n')
    grammar.firstLineRegex.testSync(lines[0..numberOfNewlinesInRegex].join('\n'))

  # Public: Get the grammar override for the given file path.
  #
  # * `filePath` A {String} file path.
  #
  # Returns a {Grammar} or undefined.
  grammarOverrideForPath: (filePath) ->
    @grammarOverridesByPath[filePath]

  # Public: Set the grammar override for the given file path.
  #
  # * `filePath` A non-empty {String} file path.
  # * `scopeName` A {String} such as `"source.js"`.
  #
  # Returns a {Grammar} or undefined.
  setGrammarOverrideForPath: (filePath, scopeName) ->
    if filePath
      @grammarOverridesByPath[filePath] = scopeName

  # Public: Remove the grammar override for the given file path.
  #
  # * `filePath` A {String} file path.
  #
  # Returns undefined.
  clearGrammarOverrideForPath: (filePath) ->
    delete @grammarOverridesByPath[filePath]
    undefined

  # Public: Remove all grammar overrides.
  #
  # Returns undefined.
  clearGrammarOverrides: ->
    @grammarOverridesByPath = {}
    undefined

  clearObservers: ->
    @off() if includeDeprecatedAPIs
    @emitter = new Emitter

if includeDeprecatedAPIs
  PropertyAccessors = require 'property-accessors'
  PropertyAccessors.includeInto(GrammarRegistry)

  {Subscriber} = require 'emissary'
  Subscriber.includeInto(GrammarRegistry)

  # Support old serialization
  atom.deserializers.add(name: 'Syntax', deserialize: GrammarRegistry.deserialize)

  # Deprecated: Used by settings-view to display snippets for packages
  GrammarRegistry::accessor 'propertyStore', ->
    deprecate("Do not use this. Use a public method on Config")
    atom.config.scopedSettingsStore

  GrammarRegistry::addProperties = (args...) ->
    args.unshift(null) if args.length is 2
    deprecate 'Consider using atom.config.set() instead. A direct (but private) replacement is available at atom.config.addScopedSettings().'
    atom.config.addScopedSettings(args...)

  GrammarRegistry::removeProperties = (name) ->
    deprecate 'atom.config.addScopedSettings() now returns a disposable you can call .dispose() on'
    atom.config.scopedSettingsStore.removeProperties(name)

  GrammarRegistry::getProperty = (scope, keyPath) ->
    deprecate 'A direct (but private) replacement is available at atom.config.getRawScopedValue().'
    atom.config.getRawScopedValue(scope, keyPath)

  GrammarRegistry::propertiesForScope = (scope, keyPath) ->
    deprecate 'Use atom.config.getAll instead.'
    atom.config.settingsForScopeDescriptor(scope, keyPath)
