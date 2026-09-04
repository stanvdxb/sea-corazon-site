#!/usr/bin/env python3
"""Contact-form receiver for corazon-tech.com. Python 3 standard library only.

POST /api/contact  (JSON or form-encoded)  ->  200 {"ok": true}
                                            ->  4xx {"ok": false, "error": "..."}
Validates, drops bots via the honeypot, and emails the submission over SMTP.
Runs behind nginx on 127.0.0.1:8787 (see contact-api.service); nginx does rate limiting."""
import json, os, re, smtplib, ssl, sys, time, threading, urllib.parse, urllib.request, urllib.error
from email.message import EmailMessage
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

BIND = os.environ.get("BIND", "127.0.0.1"); PORT = int(os.environ.get("PORT", "8787"))

# graph (Microsoft 365, OAuth client credentials — the supported path) or smtp.
TRANSPORT = os.environ.get("MAIL_TRANSPORT", "graph").strip().lower()

# --- Microsoft Graph -------------------------------------------------------
GRAPH_TENANT = os.environ.get("GRAPH_TENANT_ID", "")
GRAPH_CLIENT = os.environ.get("GRAPH_CLIENT_ID", "")
GRAPH_SECRET = os.environ.get("GRAPH_CLIENT_SECRET", "")
GRAPH_SENDER = os.environ.get("GRAPH_SENDER", "")     # mailbox the mail is sent AS

# --- SMTP (alternative) ----------------------------------------------------
SMTP_HOST = os.environ.get("SMTP_HOST", ""); SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER", ""); SMTP_PASS = os.environ.get("SMTP_PASS", "")

MAIL_TO = os.environ.get("MAIL_TO", "ops@corazon-tech.com")
MAIL_FROM = os.environ.get("MAIL_FROM", GRAPH_SENDER or MAIL_TO)
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "https://corazon-tech.com")

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$")
PHONE_RE = re.compile(r"^\+?[\d\s().-]{6,24}$")

def log(*a): print(time.strftime("%Y-%m-%dT%H:%M:%S"), *a, flush=True)

def clean(v, limit):
    v = (v or "").strip()
    return v[:limit]

def validate(d):
    """Return (payload, error). Mirrors the checks main.js does client-side."""
    if clean(d.get("website"), 10):                       # honeypot: humans never see this field
        return None, "spam"
    name = clean(d.get("name"), 120); phone = clean(d.get("phone"), 40)
    email = clean(d.get("email"), 160); message = clean(d.get("message"), 4000)
    consent = str(d.get("consent", "")).lower() in ("on", "true", "1", "yes")
    if len(name) < 2: return None, "Please enter your name."
    if not phone and not email: return None, "Please give a phone number or an email address."
    if email and not EMAIL_RE.match(email): return None, "That email address doesn't look right."
    if phone and not PHONE_RE.match(phone): return None, "That phone number doesn't look right."
    if not consent: return None, "Please agree to the terms and conditions."
    return {"name": name, "phone": phone, "email": email, "message": message,
            "page": clean(d.get("page"), 200), "form": clean(d.get("form"), 40)}, None

def header_safe(v, limit=120):
    """A header value may not carry CR/LF, or a submitted name could inject headers."""
    return re.sub(r"[\r\n]", " ", (v or ""))[:limit].strip()

def body_text(p, ip):
    return (f"Name:    {p['name']}\n"
            f"Phone:   {p['phone'] or '-'}\n"
            f"Email:   {p['email'] or '-'}\n"
            f"Form:    {p['form'] or '-'}  on  {p['page'] or '-'}\n"
            f"IP:      {ip}\n\n"
            f"{p['message'] or '(no message - call back requested)'}\n")

# ---------------------------------------------------------------- Graph ----
_token = {"value": None, "expires": 0.0}
_token_lock = threading.Lock()

def graph_token():
    """Client-credentials token, cached until shortly before it expires."""
    with _token_lock:
        if _token["value"] and time.time() < _token["expires"] - 120:
            return _token["value"]
        data = urllib.parse.urlencode({
            "client_id": GRAPH_CLIENT,
            "client_secret": GRAPH_SECRET,
            "grant_type": "client_credentials",
            "scope": "https://graph.microsoft.com/.default",
        }).encode()
        req = urllib.request.Request(
            f"https://login.microsoftonline.com/{GRAPH_TENANT}/oauth2/v2.0/token",
            data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
        try:
            with urllib.request.urlopen(req, timeout=20, context=ssl.create_default_context()) as r:
                tok = json.loads(r.read())
        except urllib.error.HTTPError as e:
            # Entra answers with a JSON body naming the exact AADSTS code. Without it
            # a bare 401 is indistinguishable between a bad secret, a wrong tenant and
            # a wrong client id — three different fixes.
            raw = e.read().decode("utf-8", "replace")
            try:
                err = json.loads(raw)
                code = err.get("error", "?")
                desc = (err.get("error_description") or "").split("\r\n")[0]
            except Exception:
                code, desc = "?", raw[:300]
            raise RuntimeError(f"token request failed [{e.code} {code}] {desc}") from None
        _token["value"] = tok["access_token"]
        _token["expires"] = time.time() + int(tok.get("expires_in", 3600))
        return _token["value"]

def send_graph(p, ip):
    payload = {
        "message": {
            "subject": header_safe(f"Website enquiry from {p['name']}"),
            "body": {"contentType": "Text", "content": body_text(p, ip)},
            "toRecipients": [{"emailAddress": {"address": MAIL_TO}}],
        },
        "saveToSentItems": "false",
    }
    if p["email"] and EMAIL_RE.match(p["email"]):
        payload["message"]["replyTo"] = [{"emailAddress": {"address": p["email"]}}]
    sender = urllib.parse.quote(GRAPH_SENDER)
    req = urllib.request.Request(
        f"https://graph.microsoft.com/v1.0/users/{sender}/sendMail",
        data=json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + graph_token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=25, context=ssl.create_default_context()) as r:
            if r.status not in (202, 200):
                raise RuntimeError(f"graph returned {r.status}")
    except urllib.error.HTTPError as e:
        detail = e.read()[:400].decode("utf-8", "replace")
        if e.code in (401, 403):
            with _token_lock:
                _token["value"] = None          # force a fresh token next time
        raise RuntimeError(f"graph {e.code}: {detail}") from None

# ----------------------------------------------------------------- SMTP ----
def send_smtp(p, ip):
    m = EmailMessage()
    m["Subject"] = header_safe(f"Website enquiry from {p['name']}")
    m["From"] = MAIL_FROM; m["To"] = MAIL_TO
    if p["email"] and EMAIL_RE.match(p["email"]): m["Reply-To"] = header_safe(p["email"], 160)
    m.set_content(body_text(p, ip))
    ctx = ssl.create_default_context()
    ctx.check_hostname = True
    ctx.verify_mode = ssl.CERT_REQUIRED
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as srv:
        srv.ehlo(); srv.starttls(context=ctx); srv.ehlo()
        if SMTP_USER: srv.login(SMTP_USER, SMTP_PASS)
        srv.send_message(m)

def send(p, ip):
    (send_graph if TRANSPORT == "graph" else send_smtp)(p, ip)

class H(BaseHTTPRequestHandler):
    server_version = "contact-api/1.0"
    def _json(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b))); self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        if self.path != "/api/contact": return self._json(404, {"ok": False, "error": "not found"})
        origin = self.headers.get("Origin", "")
        if origin and origin != ALLOWED_ORIGIN: return self._json(403, {"ok": False, "error": "forbidden"})
        n = int(self.headers.get("Content-Length", "0") or 0)
        if n > 32_000: return self._json(413, {"ok": False, "error": "too large"})
        raw = self.rfile.read(n)
        try:
            if "json" in self.headers.get("Content-Type", ""):
                d = json.loads(raw or b"{}")
                if not isinstance(d, dict): raise ValueError("body is not an object")
                d = {str(k): ("" if v is None else v if isinstance(v, (str, bool, int, float)) else "")
                     for k, v in d.items()}
            else:
                d = {k: v[0] for k, v in parse_qs(raw.decode("utf-8", "replace")).items()}
        except Exception:
            return self._json(400, {"ok": False, "error": "bad request"})
        p, err = validate(d); ip = self.headers.get("X-Forwarded-For", self.client_address[0])
        if err == "spam": log("dropped honeypot hit from", ip); return self._json(200, {"ok": True})   # don't tip off bots
        if err: return self._json(422, {"ok": False, "error": err})
        try: send(p, ip); log("sent enquiry from", ip, "name=" + p["name"]); return self._json(200, {"ok": True})
        except Exception as e:
            log("SMTP failure:", repr(e)); return self._json(502, {"ok": False, "error": "We couldn't send your message right now."})
    def do_GET(self):
        if self.path == "/api/contact/health": return self._json(200, {"ok": True})
        self._json(405, {"ok": False, "error": "method not allowed"})
    def log_message(self, *a): pass

def preflight():
    """Refuse to start unconfigured: a per-request failure is worse than not starting."""
    if TRANSPORT == "graph":
        missing = [k for k, v in (("GRAPH_TENANT_ID", GRAPH_TENANT), ("GRAPH_CLIENT_ID", GRAPH_CLIENT),
                                  ("GRAPH_CLIENT_SECRET", GRAPH_SECRET), ("GRAPH_SENDER", GRAPH_SENDER)) if not v]
    elif TRANSPORT == "smtp":
        missing = [k for k, v in (("SMTP_HOST", SMTP_HOST),) if not v]
    else:
        log(f"REFUSING TO START - MAIL_TRANSPORT must be 'graph' or 'smtp', got {TRANSPORT!r}"); sys.exit(78)
    if missing:
        log("REFUSING TO START - missing in /etc/contact-api.env:", ", ".join(missing)); sys.exit(78)

if __name__ == "__main__":
    if "--selftest" in sys.argv:
        # Proves the credentials work, without a web server and without printing them.
        preflight()
        try:
            if TRANSPORT == "graph":
                graph_token(); log("OK: token acquired from Microsoft Entra")
                send({"name": "contact-api self test", "phone": "", "email": "",
                      "message": "This confirms the website contact form can deliver mail.",
                      "form": "selftest", "page": "-"}, "localhost")
            else:
                send_smtp({"name": "contact-api self test", "phone": "", "email": "",
                           "message": "This confirms the website contact form can deliver mail.",
                           "form": "selftest", "page": "-"}, "localhost")
            log(f"OK: test message accepted for delivery to {MAIL_TO}")
            sys.exit(0)
        except Exception as e:
            log("SELF TEST FAILED:", repr(e)); sys.exit(1)
    preflight()
    log(f"contact-api on {BIND}:{PORT} - transport={TRANSPORT}, to={MAIL_TO}"
        + (f", as={GRAPH_SENDER}" if TRANSPORT == "graph" else f" via {SMTP_HOST}:{SMTP_PORT}"))
    ThreadingHTTPServer((BIND, PORT), H).serve_forever()
