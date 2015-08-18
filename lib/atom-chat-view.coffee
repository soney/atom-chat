_ = require 'underscore-plus'
{$, ScrollView, View, TextEditorView} = require 'atom-space-pen-views'
{CompositeDisposable, TextEditor, TextBuffer} = require 'atom'
MessageView = require './message-view'
socket = require('socket.io-client')('https://atom-chat-server.herokuapp.com');

module.exports =
  class AtomChatView extends ScrollView
    panel = null

    @content: ->
      chatEditor = new TextEditor
        mini: true
        tabLength: 2
        softTabs: true
        softWrapped: true
        buffer: new TextBuffer
        placeholderText: 'Type here'

      @div class: 'atom-chat-wrapper', outlet: 'wrapper', =>
        @div class: 'chat', =>
          @div class: 'chat-header list-inline tab-bar inset-panel', =>
            @div "Atom Chat", class: 'chat-title', outlet: 'title'
          @div class: 'chat-input', =>
            @subview 'chatEditor', new TextEditorView(editor: chatEditor)
          @div class: 'chat-messages', outlet: 'messages', =>
            @ul tabindex: -1, outlet: 'list'
        @div class: 'atom-chat-resize-handle', outlet: 'resizeHandle'

    initialize: () ->
      @subscriptions = new CompositeDisposable

      @uuid = Math.floor(Math.random() * 1000)
      if atom.config.get('atom-chat.username') is "User"
        @username = "User"+@uuid
      else
        @username = atom.config.get('atom-chat.username')

      @handleSockets()
      @handleEvents()

    handleSockets: ->
      socket.on 'connect', =>
        console.log "Connected"
        socket.emit 'atom:user', @username, (id) =>
          @uuid = id

      socket.on 'atom:message', (message) =>
        console.log "New Message", message
        @list.prepend new MessageView(message)
        if atom.config.get('atom-chat.openOnNewMessage')
          unless @isVisible()
            @detach()
            @attach()

      socket.on 'atom:online', (online) =>
        console.log "Online:", online
        @toolTipDisposable?.dispose()
        if online > 0
          @title.html('Atom Chat ('+online+')')
          title = "Online: #{_.pluralize(online, 'user')}"
        else
          title = "Online: 0 user"
          @title.html('Atom Chat')
        @toolTipDisposable = atom.tooltips.add @title, title: title

    handleEvents: ->
      @on 'mousedown', '.atom-chat-resize-handle', (e) => @resizeStarted(e)
      @on 'keyup', '.chat-input .editor', (e) => @enterPressed(e)

      #on showOnRightSide setting change
      @subscriptions.add atom.config.onDidChange 'atom-chat.showOnRightSide', ({newValue}) =>
        @onSideToggled(newValue)

      #on username change
      @subscriptions.add atom.config.onDidChange 'atom-chat.username', ({newValue}) =>
        socket.emit 'atom:username', newValue
        @username = newValue

    onSideToggled: (newValue) ->
      @element.dataset.showOnRightSide = newValue
      if @isVisible()
        @detach()
        @attach()

    enterPressed: (e) ->
      key = e.keyCode || e.which
      if key == 13
        msg = @chatEditor.getText()
        @chatEditor.setText('')
        message =
          text: msg
          uuid: @uuid
          username: @username
        socket.emit 'atom:message', message

    resizeStarted: =>
      $(document).on('mousemove', @resizeChatView)
      $(document).on('mouseup', @resizeStopped)

    resizeStopped: =>
      $(document).off('mousemove', @resizeChatView)
      $(document).off('mouseup', @resizeStopped)

    resizeChatView: ({pageX, which}) =>
      return @resizeStopped() unless which is 1

      if atom.config.get('atom-chat.showOnRightSide')
        width = @outerWidth() + @offset().left - pageX
      else
        width = pageX - @offset().left
      @width(width)

    # Returns an object that can be retrieved when package is activated
    serialize: ->

    destroy: ->
      @detach()
      @subscriptions?.dispose()
      @subscriptions = null

    toggle: ->
      if @isVisible()
        @detach()
      else
        @show()

    show: ->
      @attach()
      @focus()

    attach: ->
      if atom.config.get('atom-chat.showOnRightSide')
        @removeClass('panel-left')
        @panel = atom.workspace.addRightPanel(item: this, className: 'panel-right')
      else
        @removeClass('panel-right')
        @panel = atom.workspace.addLeftPanel(item: this, className: 'panel-left')
      @chatEditor.focus()

    detach: ->
      @panel?.destroy()
      @panel = null
      @unfocus()

    unfocus: ->
      atom.workspace.getActivePane().activate()

    deactivate: ->
      @subscriptions.dispose()
      @detach() if @panel?

    detached: ->
      @resizeStopped()
