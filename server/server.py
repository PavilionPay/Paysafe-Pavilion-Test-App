"""Local test backend for CashierApp.

Serves web/ (cashier.html), hands Paysafe Checkout its config through an opaque session id,
and completes payments with the PRIVATE key so it never reaches the app or the browser.

Run:  python3 server/server.py        (reads server/.env; see .env.example)
TEST credentials only. Binds to all interfaces so a physical iPhone on the LAN can reach it.
"""
import base64
import json
import os
import secrets
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WEB_DIR = ROOT.parent / "web"
SESSION_TTL_SECONDS = 15 * 60


def load_env(path: Path) -> dict:
    env = {}
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                env[key.strip()] = value.strip().strip('"').strip("'")
    return {**env, **{k: v for k, v in os.environ.items() if k.startswith("PAYSAFE_")}}


ENV = load_env(ROOT / ".env")
PUBLIC_KEY = ENV.get("PAYSAFE_PUBLIC_API_KEY", "")
PRIVATE_KEY = ENV.get("PAYSAFE_PRIVATE_API_KEY", "")
API_BASE = ENV.get("PAYSAFE_API_BASE", "https://api.test.paysafe.com").rstrip("/")
ENVIRONMENT = ENV.get("PAYSAFE_ENVIRONMENT", "TEST")
CURRENCY = ENV.get("PAYSAFE_CURRENCY", "USD")
CONSUMER_ID = ENV.get("PAYSAFE_VIPP_CONSUMER_ID", "")
ACCOUNT_ID = ENV.get("PAYSAFE_VIPP_ACCOUNT_ID", "")
PORT = int(ENV.get("PORT", "8080"))
# TEST only. EXTERNAL routes VIP Preferred (incl. Plaid) to Pavilion's test system; Paysafe's default INTERNAL
# simulator fails Plaid and delays some amounts. Empty = omit. Never sent outside TEST.
SIMULATOR = ENV.get("PAYSAFE_SIMULATOR", "EXTERNAL") if ENVIRONMENT == "TEST" else ""

# VIP Preferred rejects setup without billing details ("Invalid fields: billingDetails").
# Fake TEST patron; override any field via PAYSAFE_TEST_* in .env.
_dob = ENV.get("PAYSAFE_TEST_DOB", "1985-01-15").split("-")
TEST_CUSTOMER = {
    "firstName": ENV.get("PAYSAFE_TEST_FIRST_NAME", "Test"),
    "lastName": ENV.get("PAYSAFE_TEST_LAST_NAME", "Patron"),
    "email": ENV.get("PAYSAFE_TEST_EMAIL", "test.patron@example.com"),
    "phone": ENV.get("PAYSAFE_TEST_PHONE", "2155550100"),
    "dateOfBirth": {"year": int(_dob[0]), "month": int(_dob[1]), "day": int(_dob[2])},
}
TEST_BILLING_ADDRESS = {
    "nickName": "Home",
    "street": ENV.get("PAYSAFE_TEST_STREET", "100 Test Street"),
    "city": ENV.get("PAYSAFE_TEST_CITY", "Philadelphia"),
    "state": ENV.get("PAYSAFE_TEST_STATE", "PA"),
    "zip": ENV.get("PAYSAFE_TEST_ZIP", "19103"),
    "country": ENV.get("PAYSAFE_TEST_COUNTRY", "US"),
}


def parse_patron(raw) -> tuple[dict | None, str | None]:
    """Validate a patron entered in the app. Returns (session patron, error). TEST only; never log the SSN."""
    if raw is None:
        return None, None
    if ENVIRONMENT != "TEST":
        return None, "Custom patrons are only allowed in the TEST environment"
    if not isinstance(raw, dict):
        return None, "patron must be an object"
    text = lambda k: str(raw.get(k) or "").strip()
    digits = lambda k: "".join(ch for ch in text(k) if ch.isdigit())
    if len(digits("ssn")) != 9:
        return None, "SSN must be 9 digits"
    kind = text("kind") or "new"
    if kind == "existing":
        # Enrolled patron: Pavilion keys on the SSN; Checkout still needs billing details, so use the defaults.
        return {"kind": kind, "consumerId": digits("ssn"),
                "customer": TEST_CUSTOMER, "billingAddress": TEST_BILLING_ADDRESS}, None
    if kind != "new":
        return None, "patron.kind must be existing or new"
    dob = raw.get("dateOfBirth") or {}
    try:
        dob = {"year": int(dob["year"]), "month": int(dob["month"]), "day": int(dob["day"])}
    except (KeyError, TypeError, ValueError):
        return None, "patron.dateOfBirth needs year, month and day"
    checks = [
        (text("firstName") and text("lastName"), "First and last name are required"),
        (len(digits("phone")) == 10, "Phone must be 10 digits"),
        ("@" in text("email"), "Email looks incomplete"),
        (text("street") and text("city"), "Street and city are required"),
        (len(text("state")) == 2, "State must be a 2-letter code"),
        (len(digits("zip")) == 5, "ZIP must be 5 digits"),
    ]
    for ok, message in checks:
        if not ok:
            return None, message
    return {
        "kind": kind,
        "consumerId": digits("ssn"),
        "customer": {
            "firstName": text("firstName"), "lastName": text("lastName"), "email": text("email"),
            "phone": digits("phone"), "dateOfBirth": dob,
        },
        "billingAddress": {
            "nickName": "Home", "street": text("street"), "city": text("city"),
            "state": text("state").upper(), "zip": digits("zip"), "country": "US",
        },
    }, None


def as_basic(key: str) -> str:
    """Accept either 'username:password' or its base64 form."""
    return base64.b64encode(key.encode()).decode() if ":" in key else key


sessions: dict = {}
balance_cents = 450_000
lock = threading.Lock()


def paysafe_request(method: str, path: str, body: dict | None = None, timeout: int = 90) -> tuple[int, dict]:
    headers = {
        "Authorization": f"Basic {as_basic(PRIVATE_KEY)}",
        "Content-Type": "application/json",
    }
    if SIMULATOR:
        headers["Simulator"] = SIMULATOR
    request = urllib.request.Request(
        f"{API_BASE}{path}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers=headers,
    )
    # Paysafe support traces requests by x-correlation-id; log it for every call.
    def log(status, headers):
        correlation = headers.get("x-internal-correlation-id") or headers.get("x-correlation-id") or "-"
        print(f"Paysafe {method} {path.split('?')[0]} -> HTTP {status} correlation-id={correlation} "
              f"cf-id={headers.get('x-amz-cf-id', '-')} at {time.strftime('%Y-%m-%d %H:%M:%S %Z')}")

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            log(response.status, response.headers)
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        log(error.code, error.headers)
        try:
            return error.code, json.loads(error.read() or b"{}")
        except ValueError:
            return error.code, {}


def find_payment(merchant_ref: str) -> dict:
    """Look up a payment by merchantRefNum; {} if none or the lookup fails."""
    try:
        status, body = paysafe_request(
            "GET", f"/paymenthub/v1/payments?merchantRefNum={urllib.parse.quote(merchant_ref)}", timeout=30)
    except (TimeoutError, urllib.error.URLError) as error:
        print(f"Paysafe lookup {merchant_ref} failed: {error!r}")
        return {}
    payments = body.get("payments") or []
    print(f"Paysafe lookup {merchant_ref}: HTTP {status}, {len(payments)} payment(s)")
    return payments[0] if payments else {}


def paysafe_payment(session: dict, payment_handle_token: str) -> tuple[int, dict]:
    body = {
        "merchantRefNum": session["merchantRefNum"],
        "amount": session["amount"],
        "currencyCode": CURRENCY,
        "dupCheck": True,
        "settleWithAuth": True,
        "paymentHandleToken": payment_handle_token,
        "description": "CashierApp deposit",
    }
    started = time.time()
    try:
        status, result = paysafe_request("POST", "/paymenthub/v1/payments", body)
    except (TimeoutError, urllib.error.URLError) as error:
        # Paysafe may still have taken the payment; check before reporting failure.
        print(f"Paysafe payment {session['merchantRefNum']} errored after {time.time() - started:.0f}s: {error!r}")
        found = find_payment(session["merchantRefNum"])
        if found:
            return 200, found
        return 504, {"error": {"message": "Paysafe did not respond in time. Check before retrying."}}
    print(f"Paysafe payment {session['merchantRefNum']} took {time.time() - started:.0f}s")
    return status, result


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def log_message(self, fmt, *args):
        # Paths only; query strings can carry session ids.
        print(f"{self.address_string()} {self.command} {self.path.split('?')[0]} -> {args[1] if len(args) > 1 else ''}")

    def send_json(self, status: int, payload: dict):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return {}

    def session_for(self, sid: str):
        with lock:
            session = sessions.get(sid)
            if session and time.time() - session["created"] > SESSION_TTL_SECONDS:
                sessions.pop(sid, None)
                session = None
            return session

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/balance":
            return self.send_json(200, {"balance": balance_cents / 100})
        if path.startswith("/api/cashier/session/"):
            session = self.session_for(path.rsplit("/", 1)[-1])
            if not session:
                return self.send_json(404, {"message": "Cashier session expired"})
            config = {
                "apiKey": as_basic(PUBLIC_KEY),
                "environment": ENVIRONMENT,
                "currency": CURRENCY,
                "amount": session["amount"],
                "locale": "en_US",
                "merchantRefNum": session["merchantRefNum"],
            }
            patron = session.get("patron")
            config["consumerId"] = patron["consumerId"] if patron else CONSUMER_ID
            config["customer"] = patron["customer"] if patron else TEST_CUSTOMER
            config["billingAddress"] = patron["billingAddress"] if patron else TEST_BILLING_ADDRESS
            if ACCOUNT_ID:
                config["accountId"] = ACCOUNT_ID
            if SIMULATOR:
                config["simulator"] = SIMULATOR
            return self.send_json(200, config)
        if path == "/cashier-return":
            # Only reached if nothing intercepts the return URL (e.g. opened in plain Safari).
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<p>Payment finished. Return to the app.</p>")
            return
        return super().do_GET()

    def do_POST(self):
        global balance_cents
        path = self.path.split("?")[0]
        if path == "/api/cashier/session":
            payload = self.read_json()
            amount = payload.get("amount")
            try:
                cents = round(float(amount) * 100)
            except (TypeError, ValueError):
                return self.send_json(400, {"message": "amount required"})
            if cents <= 0:
                return self.send_json(400, {"message": "amount must be positive"})
            patron, error = parse_patron(payload.get("patron"))
            if error:
                return self.send_json(400, {"message": error})
            sid = secrets.token_urlsafe(24)
            merchant_ref = f"cashier-{uuid.uuid4()}"
            with lock:
                sessions[sid] = {
                    "amount": cents,
                    "merchantRefNum": merchant_ref,
                    "created": time.time(),
                    "completed": False,
                    "patron": patron,
                }
            # SSN masked to last 4 so a run can be matched to downstream logs without exposing it.
            who = f"{patron['kind']} patron SSN ...{patron['consumerId'][-4:]}" if patron else "default patron"
            print(f"Session {merchant_ref}: {who}")
            return self.send_json(201, {"sid": sid})

        if path.startswith("/api/cashier/session/") and path.endswith("/complete"):
            sid = path.split("/")[-2]
            session = self.session_for(sid)
            if not session:
                return self.send_json(404, {"message": "Cashier session expired"})
            with lock:
                if session["completed"]:
                    return self.send_json(409, {"message": "Session already completed"})
                session["completed"] = True
            token = self.read_json().get("paymentHandleToken")
            if not token:
                return self.send_json(400, {"message": "paymentHandleToken required"})
            status, body = paysafe_payment(session, token)
            print(f"Paysafe payment HTTP {status} status={body.get('status')} id={body.get('id')} "
                  f"simulator={body.get('simulator')} error={body.get('error', {}).get('code')}")
            if 200 <= status < 300 and body.get("status") in ("COMPLETED", "PENDING", "PROCESSING"):
                with lock:
                    if body.get("status") == "COMPLETED":
                        balance_cents += session["amount"]
                return self.send_json(200, {"reference": body.get("id", ""), "status": body.get("status")})
            message = body.get("error", {}).get("message") or f"Payment failed (HTTP {status})"
            return self.send_json(402, {"message": message})

        return self.send_json(404, {"message": "Not found"})


def main():
    missing = [name for name, value in (
        ("PAYSAFE_PUBLIC_API_KEY", PUBLIC_KEY),
        ("PAYSAFE_PRIVATE_API_KEY", PRIVATE_KEY),
        ("PAYSAFE_VIPP_CONSUMER_ID", CONSUMER_ID),
    ) if not value]
    if missing:
        print(f"Missing in server/.env: {', '.join(missing)} (Checkout or payments will fail)")
    print(f"Paysafe {ENVIRONMENT} via {API_BASE} (simulator={SIMULATOR or 'default'}); serving {WEB_DIR} on http://0.0.0.0:{PORT}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
