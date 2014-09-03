#= require ./loading-mixin

class window.Brainstem.Collection extends Backbone.Collection

  @OPTION_KEYS = ['name', 'filters', 'page', 'perPage', 'limit', 'offset', 'order', 'search', 'cacheKey']

  @getComparatorWithIdFailover: (order) ->
    [field, direction] = order.split(":")
    comp = @getComparator(field)
    (a, b) ->
      [b, a] = [a, b] if direction.toLowerCase() == "desc"
      result = comp(a, b)
      if result == 0
        a.get('id') - b.get('id')
      else
        result

  @getComparator: (field) ->
    return (a, b) -> a.get(field) - b.get(field)

  @pickFetchOptions: (options) ->
    _.pick options, @OPTION_KEYS


  #
  # Properties

  lastFetchOptions: null
  firstFetchOptions: null


  #
  # Init

  constructor: (models, options) ->
    super
    @firstFetchOptions = Brainstem.Collection.pickFetchOptions(options) if options
    @setLoaded false


  #
  # Accessors

  getServerCount: ->
    @_getCacheObject()?.count

  getWithAssocation: (id) ->
    @get(id)


  #
  # Control

  fetch: (options) ->
    options = if options then _.clone(options) else {}
    
    options.parse = options.parse ? true
    options.name = options.name ? @model?.prototype.brainstemKey

    unless options.name
      Brainstem.Utils.throwError(
        'Either collection must have model with brainstemKey defined or name option must be provided'
      )

    unless @firstFetchOptions
      @firstFetchOptions = Brainstem.Collection.pickFetchOptions options

    Brainstem.Utils.wrapError(this, options)

    loader = base.data.loadObject(options.name, _.extend(@firstFetchOptions, options))

    loader.pipe(-> loader.internalObject.models)
      .done((response) =>
        if options.add
          method = 'add'
        else if options.reset
          method = 'reset'
        else
          method = 'set'

        @[method](response, options)
        @lastFetchOptions = loader.externalObject.lastFetchOptions

        @trigger('sync', this, response, options)
      ).promise()

  update: (models) ->
    models = models.models if models.models?
    for model in models
      model = this.model.parse(model) if this.model.parse?
      backboneModel = @_prepareModel(model)
      if backboneModel
        if modelInCollection = @get(backboneModel.id)
          modelInCollection.set backboneModel.attributes
        else
          @add backboneModel
      else
        Brainstem.Utils.warn "Unable to update collection with invalid model", model

  reload: (options) ->
    base.data.reset()
    @reset [], silent: true
    @setLoaded false
    loadOptions = _.extend({}, @lastFetchOptions, options, page: 1, collection: this)
    base.data.loadCollection @lastFetchOptions.name, loadOptions

  loadNextPage: (options = {}) ->
    if _.isFunction(options.success)
      success = options.success
      delete options.success

    @getNextPage(_.extend(options, add: true)).done(=> success?(this, @hasNextPage()))

  getPageIndex: ->
    return 1 unless @lastFetchOptions

    unless _.isUndefined(@lastFetchOptions.offset)
      Math.ceil(@lastFetchOptions.offset / @lastFetchOptions.limit) + 1
    else
      @lastFetchOptions.page

  getNextPage: (options = {}) ->
    @getPage(@getPageIndex() + 1, options)

  getPreviousPage: (options = {}) ->
    @getPage(@getPageIndex() - 1, options)

  getFirstPage: (options = {}) ->
    @getPage(1, options)

  getLastPage: (options = {}) ->
    @getPage(Infinity, options)

  getPage: (index, options = {}) ->
    @_canPaginate()

    options = _.extend(options, @lastFetchOptions)

    index = 1 if index < 1

    unless _.isUndefined(@lastFetchOptions.offset)
      max = @_maxOffset()
      offset = @lastFetchOptions.limit * index - @lastFetchOptions.limit
      options.offset = if offset < max then offset else max
    else
      max = @_maxPage()
      options.page = if index < max then index else max

    @fetch(options)

  hasNextPage: ->
    @_canPaginate()

    unless _.isUndefined(@lastFetchOptions.offset)
      if @_maxOffset() > @lastFetchOptions.offset then true else false
    else
      if @_maxPage() > @lastFetchOptions.page then true else false

  hasPreviousPage: ->
    @_canPaginate()

    unless _.isUndefined(@lastFetchOptions.offset)
      if @lastFetchOptions.offset > @lastFetchOptions.limit then true else false
    else
      if @lastFetchOptions.page > 1 then true else false

  invalidateCache: ->
    @_getCacheObject()?.valid = false

  toServerJSON: (method) ->
    @toJSON()


  #
  # Private

  _canPaginate: ->
    options = @lastFetchOptions
    throwError = Brainstem.Utils.throwError
    count = try @getServerCount()

    throwError('(pagination) collection must have been fetched once') unless options
    throwError('(pagination) collection must have a count') unless count
    throwError('(pagination) perPage or limit must be defined') unless options.perPage || options.limit

  _maxOffset: ->
    limit = @lastFetchOptions.limit
    Brainstem.Utils.throwError('(pagination) you must define limit when using offset') if _.isUndefined(limit)
    limit * Math.ceil(@getServerCount() / limit) - limit

  _maxPage: ->
    perPage = @lastFetchOptions.perPage
    Brainstem.Utils.throwError('(pagination) you must define perPage when using page') if _.isUndefined(perPage)
    Math.ceil(@getServerCount() / perPage)

  _getCacheObject: ->
    if @lastFetchOptions
      base.data.getCollectionDetails(@lastFetchOptions.name)?.cache[@lastFetchOptions.cacheKey]


# Mixins

_.extend(Brainstem.Collection.prototype, Brainstem.LoadingMixin)
