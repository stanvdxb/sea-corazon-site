#!/usr/bin/env python3
"""Contact-form receiver for corazon-tech.com. Python 3 standard library only.

POST /api/contact  (JSON or form-encoded)  ->  200 {"ok": true}
                                            ->  4xx {"ok": false, "error": "..."}
Validates, drops bots via the honeypot, and emails the submission over SMTP.
Runs behind nginx on 127.0.0.1:8787 (see contact-api.service); nginx does rate limiting."""
import json, os, re, smtplib, sys, time, html
from email.message import EmailMessage
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

BIND = os.environ.get("BIND", "127.0.0.1"); PORT = int(os.environ.get("PORT", "8787"))
SMTP_HOST = os.environ["SMTP_HOST"]; SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER", ""); SMTP_PASS = os.environ.get("SMTP_PASS", "")
MAIL_TO = os.environ.get("MAIL_TO", "ops@corazon-tech.com"); MAIL_FROM = os.environ.get("MAIL_FROM", MAIL_TO)
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

def send(p, ip):
    m = EmailMessage()
    m["Subject"] = f"Website enquiry from {p['name']}"
    m["From"] = MAIL_FROM; m["To"] = MAIL_TO
    if p["email"]: m["Reply-To"] = p["email"]
    body = (f"Name:    {p['name']}\nPhone:   {p['phone'] or '-'}\nEmail:   {p['email'] or '-'}\n"
            f"Form:    {p['form'] or '-'}  on  {p['page'] or '-'}\nIP:      {ip}\n\n{p['message'] or '(no message — call back requested)'}\n")
    m.set_content(body)
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as s:
        s.starttls()
        if SMTP_USER: s.login(SMTP_USER, SMTP_PASS)
        s.send_message(m)

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
            if "json" in self.headers.get("Content-Type", ""): d = json.loads(raw or b"{}")
            else: d = {k: v[0] for k, v in parse_qs(raw.decode("utf-8", "replace")).items()}
        except Exception: return self._json(400, {"ok": False, "error": "bad request"})
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

if __name__ == "__main__":
    log(f"contact-api listening on {BIND}:{PORT}, mail to {MAIL_TO} via {SMTP_HOST}:{SMTP_PORT}")
    ThreadingHTTPServer((BIND, PORT), H).serve_forever()
