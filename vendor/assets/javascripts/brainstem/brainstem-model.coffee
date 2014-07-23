#= require ./loading-mixin

# Extend Backbone.Model to include associations.
class window.Brainstem.Model extends Backbone.Model
  # Parse ISO8601 attribute strings into date objects
  @parse: (modelObject) ->
    for k,v of modelObject
      # Date.parse will parse ISO 8601 in ECMAScript 5, but we include a shim for now
      if /\d{4}-\d{2}-\d{2}T\d{2}\:\d{2}\:\d{2}[-+]\d{2}:\d{2}/.test(v)
        modelObject[k] = Date.parse(v)
    return modelObject

  # Handle create and update responses with JSON root keys
  parse: (resp, xhr) ->
    @updateStorageManager(resp)
    modelObject = @_parseResultsResponse(resp)
    super(@constructor.parse(modelObject), xhr)

  updateStorageManager: (resp) ->
    results = resp['results']
    return if _.isEmpty(results)

    keys = _.reject(_.keys(resp), (key) -> key == 'count' || key == 'results')
    primaryModelKey = results[0]['key']
    keys.splice(keys.indexOf(primaryModelKey), 1)
    keys.push(primaryModelKey)

    for underscoredModelName in keys
      models = resp[underscoredModelName]
      for id, attributes of models
        @constructor.parse(attributes)
        collection = base.data.storage(underscoredModelName)
        collectionModel = collection.get(id)
        if collectionModel
          collectionModel.set(attributes)
        else
          if @brainstemKey == underscoredModelName && (@isNew() || @id == attributes.id)
            @set(attributes)
            collection.add(this)
          else
            collection.add(attributes)

  _parseResultsResponse: (resp) ->
    return resp unless resp['results']

    if resp['results'].length
      key = resp['results'][0].key
      id = resp['results'][0].id
      resp[key][id]
    else
      {}


  # Retreive details about a named association.  This is a class method.
  #     Model.associationDetails("project") # => {}
  #     timeEntry.constructor.associationDetails("project") # => {}
  @associationDetails: (association) ->
    @associationDetailsCache ||= {}
    if @associations && @associations[association]
      @associationDetailsCache[association] ||= do =>
        associator = @associations[association]
        isArray = _.isArray associator
        if isArray && associator.length > 1
          {
            type: "BelongsTo"
            collectionName: associator
            key: "#{association}_ref"
            polymorphic: true
          }
        else if isArray
          {
            type: "HasMany"
            collectionName: associator[0]
            key: "#{association.singularize()}_ids"
          }
        else
          {
            type: "BelongsTo"
            collectionName: associator
            key: "#{association}_id"
          }

  # This method determines if all of the provided associations have been loaded for this model.  If no associations are
  # provided, all associations are assumed.
  #   model.associationsAreLoaded(["project", "task"]) # => true|false
  #   model.associationsAreLoaded() # => true|false
  associationsAreLoaded: (associations) ->
    associations ||= _.keys(@constructor.associations)
    associations = _.select associations, (association) => @constructor.associationDetails(association)

    _.all associations, (association) =>
      details = @constructor.associationDetails(association)
      if details.type == "BelongsTo"
        @attributes.hasOwnProperty(details.key) &&
        (@attributes[details.key] == null ||
        base.data.storage(details.collectionName).get(@attributes[details.key]))
      else
        @attributes.hasOwnProperty(details.key) && _.all(@attributes[details.key], (id) ->
          base.data.storage(details.collectionName).get(id))

  # Override Model#get to access associations as well as fields.
  get: (field, options = {}) ->
    if details = @constructor.associationDetails(field)
      if details.type == "BelongsTo"
        value = super(details.key) # project_id
        if value?
          if details.polymorphic
            id = value.id
            collectionName = value.key
          else
            id = value
            collectionName = details.collectionName

          model = base.data.storage(collectionName).get(id)

          if not model && not options.silent
            Brainstem.Utils.throwError("Unable to find #{field} with id #{id} in our cached #{details.collectionName} collection.  We know about #{base.data.storage(details.collectionName).pluck("id").join(", ")}")

          model
      else
        ids = super(details.key) # time_entry_ids
        models = []
        notFoundIds = []
        if ids
          for id in ids
            model = base.data.storage(details.collectionName).get(id)
            models.push(model)
            notFoundIds.push(id) unless model
          if notFoundIds.length && not options.silent
            Brainstem.Utils.throwError("Unable to find #{field} with ids #{notFoundIds.join(", ")} in our cached #{details.collectionName} collection.  We know about #{base.data.storage(details.collectionName).pluck("id").join(", ")}")
        if options.order
          comparator = base.data.getCollectionDetails(details.collectionName).klass.getComparatorWithIdFailover(options.order)
          collectionOptions = { comparator: comparator }
        else
          collectionOptions = {}
        base.data.createNewCollection(details.collectionName, models, collectionOptions)
    else
      super(field)

  invalidateCache: ->
    for cacheKey, cacheObject of base.data.getCollectionDetails(@brainstemKey).cache
      if _.find(cacheObject.results, (result) => result.id == @id)
        cacheObject.valid = false

  className: ->
    @paramRoot

  defaultJSONBlacklist: ->
    ['id', 'created_at', 'updated_at']

  createJSONBlacklist: ->
    []

  updateJSONBlacklist: ->
    []

  toServerJSON: (method, options) ->
    json = @toJSON(options)
    blacklist = @defaultJSONBlacklist()

    switch method
      when "create"
        blacklist = blacklist.concat @createJSONBlacklist()
      when "update"
        blacklist = blacklist.concat @updateJSONBlacklist()

    for blacklistKey in blacklist
      delete json[blacklistKey]

    json