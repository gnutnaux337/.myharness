window.__ModuleLoader__.load({id:"dsh-whale-widget",factory:function(require){
var useEffect = require("react").useEffect;
// Session-bound bridge: only sanitized quota information crosses into the whale.
// Uses the same supported services as the subscriptions composer's usage badge.
function createQuotaReader(rpc, currentModel, publish, now) {
  now = now || Date.now
  var epoch = 0, lastKey = '', lastFetch = 0, cached = null, disposed = false, busy = false
  function isSubProvider(p) { return p === 'codex' || p === 'antigravity' }
  function matchesModel(scope, model) {
    if (!scope || !model) return !scope
    if (scope === model) return true
    var cleanModel = String(model).replace(/^[a-zA-Z0-9_-]+\//, '')
    var cleanScope = String(scope).replace(/^[a-zA-Z0-9_-]+\//, '')
    return cleanScope === cleanModel || model.endsWith('/' + scope) || scope.endsWith('/' + model)
  }
  async function call(endpoint, payload) {
    var result = await rpc.call('/api', 'subscriptions-auth.' + endpoint, payload)
    if (!result || !result.ok) throw new Error('Subscription information unavailable')
    return result.value
  }
  return {
    async poll() {
      if (disposed || busy) return
      busy = true
      var generation = ++epoch
      try {
        var selection = await currentModel()
        if (disposed || generation !== epoch) return
        var provider = selection && selection.provider
        var key = provider + ':' + (selection && selection.model)
        if (key !== lastKey) { cached = null; lastFetch = 0; lastKey = key }
        if (!isSubProvider(provider)) { publish({ provider: provider || 'unknown', status: 'other' }); return }
        if (lastFetch && now() - lastFetch < 60000) { publish(cached || { provider: provider, status: 'unavailable' }); return }
        publish(cached ? Object.assign({}, cached, { status: 'stale' }) : { provider: provider, status: 'loading' })
        var status = await call('status', {})
        if (disposed || generation !== epoch) return
        var statusSelection = await currentModel()
        if (disposed || generation !== epoch) return
        if (!statusSelection || statusSelection.provider !== provider || statusSelection.model !== selection.model) {
          cached = null; lastFetch = 0
          publish({ provider: statusSelection && statusSelection.provider || 'unknown', status: statusSelection && isSubProvider(statusSelection.provider) ? 'loading' : 'other' })
          return
        }
        var accounts = status.providers && status.providers[provider] && status.providers[provider].accounts || []
        var account = accounts.find(function (a) { return a.isDefault }) || accounts[0]
        if (!account) { cached = null; lastFetch = now(); publish({ provider: provider, status: 'unavailable' }); return }
        // Deliberately do not export account keys, email, OAuth credentials, or raw response.
        var usage = await call('usage', { provider: provider, account: account.key })
        if (disposed || generation !== epoch) return
        var latestSelection = await currentModel()
        if (disposed || generation !== epoch) return
        if (!latestSelection || latestSelection.provider !== provider || latestSelection.model !== selection.model) {
          cached = null; lastFetch = 0
          publish({ provider: latestSelection && latestSelection.provider || 'unknown', status: latestSelection && isSubProvider(latestSelection.provider) ? 'loading' : 'other' })
          return
        }
        var selModel = selection && selection.model
        var rawWindows = usage.supported && Array.isArray(usage.windows) ? usage.windows : []
        var windows = rawWindows.filter(function (w) {
          return matchesModel(w.scope, selModel) && typeof w.usedPercent === 'number' && Number.isFinite(w.usedPercent)
        }).map(function (w) {
          var kind = (w.kind === 'other' || w.kind === 'session' || w.kind === 'window') ? 'session' : String(w.kind || 'window')
          return { kind: kind, remaining: Math.round(100 - Math.min(100, Math.max(0, w.usedPercent))), resetsAt: typeof w.resetsAt === 'number' && Number.isFinite(w.resetsAt) ? w.resetsAt : null }
        }).sort(function (a, b) {
          if (a.kind === 'session' && b.kind !== 'session') return -1
          if (b.kind === 'session' && a.kind !== 'session') return 1
          return 0
        })
        lastFetch = now()
        cached = { provider: provider, status: windows.length ? 'ready' : 'unavailable', windows: windows, updatedAt: typeof usage.fetchedAt === 'number' && Number.isFinite(usage.fetchedAt) ? usage.fetchedAt : lastFetch, model: String(selection.model || '').slice(0, 120), scope: 'default-account' }
        publish(cached)
      } catch (error) {
        lastFetch = now()
        if (cached) cached = Object.assign({}, cached, { status: 'stale' })
        if (!disposed) publish(cached ? Object.assign({}, cached, { status: 'stale' }) : { provider: isSubProvider(provider) ? provider : 'unknown', status: 'unavailable' })
      } finally { busy = false }
    },
    dispose() { disposed = true; epoch++ }
  }
}
function apply(ctx) {
  var connection = ctx.get('connection')
  ctx.slots.inject('conversation.composer.dock', function () {
    return ctx.slots.register({ name: 'conversation.composer.dock', id: 'whale-active-chat', order: 99,
      inject: function (sessionId) { return { sessionId: sessionId } }
    }, function WhaleActiveChat(props) {
      useEffect(function () {
        var reader = createQuotaReader(connection.rpc, async function () {
          var models = ctx.get('modelDirectories')
          if (!models) throw new Error('Model selection unavailable')
          return (await models.directoryFor(props.sessionId).load()).current
        }, function (snapshot) {
          window.__dshWhaleActiveChat = snapshot
          window.dispatchEvent(new CustomEvent('dsh-whale-active-chat', { detail: snapshot }))
        })
        reader.poll()
        var timer = setInterval(function () { reader.poll() }, 3000)
        return function () {
          clearInterval(timer); reader.dispose()
          window.__dshWhaleActiveChat = { provider: 'unknown', status: 'other' }
          window.dispatchEvent(new CustomEvent('dsh-whale-active-chat', { detail: window.__dshWhaleActiveChat }))
        }
      }, [props.sessionId])
      return null
    })
  })
}

return {inject:["slots","connection"],apply:apply};
}});
