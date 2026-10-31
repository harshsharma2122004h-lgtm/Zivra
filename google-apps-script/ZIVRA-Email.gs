/**
 * ZIVRA transactional email relay for Google Apps Script.
 *
 * Deploy as a Web App:
 *   Execute as: Me
 *   Who has access: Anyone
 *
 * In Apps Script: Project Settings -> Script Properties, add:
 *   ZIVRA_RELAY_TOKEN = a long random secret (same value as GMAIL_SCRIPT_TOKEN in Supabase)
 *
 * The endpoint is protected by that shared secret. Do not publish the token.
 */
function doPost(e) {
  try {
    var payload = JSON.parse((e && e.postData && e.postData.contents) || "{}");
    var expected = PropertiesService.getScriptProperties().getProperty("ZIVRA_RELAY_TOKEN");
    if (!expected || !payload.token || !constantTimeEquals_(String(payload.token), String(expected))) {
      return json_({ ok: false, error: "Unauthorized relay request." });
    }

    var to = String(payload.to || "").trim();
    var subject = String(payload.subject || "").trim();
    var htmlBody = String(payload.htmlBody || "");
    var textBody = String(payload.textBody || "");
    if (!to || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) {
      return json_({ ok: false, error: "A valid recipient email is required." });
    }
    if (!subject || !htmlBody || !textBody) {
      return json_({ ok: false, error: "Email subject and body are required." });
    }
    if (subject.length > 250 || htmlBody.length > 90000 || textBody.length > 50000) {
      return json_({ ok: false, error: "Email content exceeds the allowed size." });
    }

    var options = {
      htmlBody: htmlBody,
      name: "ZIVRA Support",
      replyTo: String(payload.replyTo || "Zivrasupport@gmail.com")
    };
    GmailApp.sendEmail(to, subject, textBody, options);
    return json_({ ok: true, orderId: String(payload.orderId || ""), emailType: String(payload.emailType || "") });
  } catch (err) {
    console.error(err);
    return json_({ ok: false, error: "Gmail send failed: " + String(err && err.message || err) });
  }
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

function constantTimeEquals_(a, b) {
  if (a.length !== b.length) return false;
  var mismatch = 0;
  for (var i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}
