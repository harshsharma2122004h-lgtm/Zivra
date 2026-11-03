// ZIVRA customer-side error monitor.
// Technical errors are reported to the admin panel (Notifications) and customers only see a calm message.
(function () {
  var cfg = window.ZIVRA_SUPABASE_CONFIG || {};
  var FRIENDLY = 'Something went wrong on our side. Please try again in a moment. If it continues, contact ZIVRA Support.';
  // Messages a customer can fix themselves are shown as-is (wrong voucher, missing field, sold out...).
  var FIXABLE = /invalid (voucher|login|credentials|email|password)|insufficient stock|out of stock|unavailable|valid (delivery|email)|please (add|enter|provide|select|choose|fill|write|sign|check)|already (registered|exists)|email not confirmed|password (should|must)|at least \d+ characters|not found|no order|incorrect|expired|too many|rate limit|fill in/i;
  var sent = {}, count = 0;

  function text(err) { return String((err && (err.message || err.error_description || err.error)) || err || '').slice(0, 600); }

  async function rpc(name, args) {
    if (!cfg.url || !cfg.anonKey) return { ok: false, error: { message: 'Store configuration is missing' } };
    try {
      var res = await fetch(cfg.url + '/rest/v1/rpc/' + name, {
        method: 'POST', keepalive: true,
        headers: { apikey: cfg.anonKey, 'Content-Type': 'application/json' },
        body: JSON.stringify(args || {})
      });
      var body = null; try { body = await res.json(); } catch (_) {}
      if (!res.ok) return { ok: false, error: { message: (body && (body.message || body.error)) || ('HTTP ' + res.status) } };
      return { ok: true, data: body };
    } catch (e) { return { ok: false, error: { message: text(e) || 'Network error' } }; }
  }

  function report(source, err, details) {
    try {
      var msg = text(err); if (!msg) return;
      var key = source + '|' + msg;
      if (sent[key] || count >= 8) return;
      sent[key] = 1; count++;
      rpc('zivra_log_client_error', {
        p_source: source, p_message: msg, p_page: location.pathname + location.search,
        p_details: Object.assign({ stack: err && err.stack ? String(err.stack).slice(0, 800) : undefined, online: navigator.onLine }, details || {}),
        p_user_agent: navigator.userAgent
      });
    } catch (_) {}
  }

  // Returns the text a customer should see; logs technical failures for the admin.
  function handle(source, err, fallback, details) {
    var msg = text(err);
    if (msg && FIXABLE.test(msg)) return msg;
    report(source, err, details);
    return fallback || FRIENDLY;
  }

  window.zivraRpc = rpc;
  window.zivraReport = report;
  window.zivraHandle = handle;
  window.ZIVRA_FRIENDLY_ERROR = FRIENDLY;

  window.addEventListener('error', function (e) {
    var m = e && e.message || '';
    if (!m || /^Script error\.?$/i.test(m) || /ResizeObserver/i.test(m)) return;
    report('javascript', e.error || m, { file: e.filename, line: e.lineno });
  });
  window.addEventListener('unhandledrejection', function (e) {
    var r = e && e.reason; if (!text(r)) return;
    report('promise', r);
  });
})();
