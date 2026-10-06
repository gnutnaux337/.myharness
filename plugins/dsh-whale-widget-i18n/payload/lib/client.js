window.__ModuleLoader__.load({id:"dsh-whale-widget",factory:function(require){
var useEffect = require("react").useEffect;
// Session-bound bridge: only sanitized quota information crosses into the whale.
// Uses the same supported services as the subscriptions composer's usage badge.
function createQuotaReader(rpc, currentModel, publish, now) {
  now = now || Date.now
  var epoch = 0, lastKey = '', lastFetch = 0, cached = null, disposed = false, busy = false
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
        if (provider !== 'codex') { publish({ provider: provider || 'unknown', status: 'other' }); return }
        if (lastFetch && now() - lastFetch < 60000) { publish(cached || { provider: 'codex', status: 'unavailable' }); return }
        publish(cached ? Object.assign({}, cached, { status: 'stale' }) : { provider: 'codex', status: 'loading' })
        var status = await call('status', {})
        if (disposed || generation !== epoch) return
        var statusSelection = await currentModel()
        if (disposed || generation !== epoch) return
        if (!statusSelection || statusSelection.provider !== provider || statusSelection.model !== selection.model) {
          cached = null; lastFetch = 0
          publish({ provider: statusSelection && statusSelection.provider || 'unknown', status: statusSelection && statusSelection.provider === 'codex' ? 'loading' : 'other' })
          return
        }
        var accounts = status.providers && status.providers.codex && status.providers.codex.accounts || []
        var account = accounts.find(function (a) { return a.isDefault }) || accounts[0]
        if (!account) { cached = null; lastFetch = now(); publish({ provider: 'codex', status: 'unavailable' }); return }
        // Deliberately do not export account keys, email, OAuth credentials, or raw response.
        var usage = await call('usage', { provider: 'codex', account: account.key })
        if (disposed || generation !== epoch) return
        var latestSelection = await currentModel()
        if (disposed || generation !== epoch) return
        if (!latestSelection || latestSelection.provider !== provider || latestSelection.model !== selection.model) {
          cached = null; lastFetch = 0
          publish({ provider: latestSelection && latestSelection.provider || 'unknown', status: latestSelection && latestSelection.provider === 'codex' ? 'loading' : 'other' })
          return
        }
        var windows = usage.supported && Array.isArray(usage.windows) ? usage.windows.filter(function (w) {
          return (!w.scope || w.scope === selection.model) && typeof w.usedPercent === 'number' && Number.isFinite(w.usedPercent)
        }).map(function (w) {
          return { kind: String(w.kind || 'window'), remaining: Math.round(100 - Math.min(100, Math.max(0, w.usedPercent))), resetsAt: typeof w.resetsAt === 'number' && Number.isFinite(w.resetsAt) ? w.resetsAt : null }
        }) : []
        lastFetch = now()
        cached = { provider: 'codex', status: windows.length ? 'ready' : 'unavailable', windows: windows, updatedAt: typeof usage.fetchedAt === 'number' && Number.isFinite(usage.fetchedAt) ? usage.fetchedAt : lastFetch, model: String(selection.model || '').slice(0, 120), scope: 'default-account' }
        publish(cached)
      } catch (error) {
        lastFetch = now()
        if (cached) cached = Object.assign({}, cached, { status: 'stale' })
        if (!disposed) publish(cached ? Object.assign({}, cached, { status: 'stale' }) : { provider: lastKey.indexOf('codex:') === 0 ? 'codex' : 'unknown', status: 'unavailable' })
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
