#!/usr/bin/env python3
import json                 # dict -> JSON text (for the log line)
import os                   # follow the /opt/llama/current link
import socket               # get this machine's name
import threading            # NEW: lock, so parallel requests don't mix up the counters
import time                 # current time, and how long a request took
import urllib.error         # error types we catch
import urllib.request       # send a request to llama-server
import uuid                 # make a random request ID
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer   # ready-made web server

UPSTREAM = "http://127.0.0.1:8081"   # llama-server on the same VM
PORT = 8080                          # gateway listens here
HOST = socket.gethostname()          # node-a or node-b

LOCK = threading.Lock()                        # NEW: only one request updates the numbers at a time
REQUESTS = {}                                  # NEW: status code -> count, e.g. {200: 15, 502: 2}
BUCKETS = [0.1, 0.25, 0.5, 1, 2, 5, 10, 30]    # NEW: time limits in seconds
BUCKET_COUNTS = [0] * len(BUCKETS)             # NEW: how many requests took <= each limit
LATENCY_SUM = 0.0                              # NEW: total seconds of all requests
LATENCY_COUNT = 0                              # NEW: number of requests timed


def release():
    # /opt/llama/current -> /opt/llama/releases/b11154  ->  "b11154"
    return os.path.basename(os.path.realpath("/opt/llama/current"))


def log_json(**fields):
    # fields = everything passed in, e.g. request_id="abc", status=200
    fields["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())   # add the time (UTC)
    fields["host"] = HOST                                               # add node-a / node-b
    print(json.dumps(fields), flush=True)   # print as one JSON line; flush = write now. systemd saves it in the journal


def record(status, seconds):                   # NEW: called after every request
    global LATENCY_SUM, LATENCY_COUNT
    with LOCK:
        REQUESTS[status] = REQUESTS.get(status, 0) + 1     # NEW: +1 for this status code
        LATENCY_SUM += seconds                             # NEW: add its time
        LATENCY_COUNT += 1                                 # NEW: +1 request
        for i, limit in enumerate(BUCKETS):
            if seconds <= limit:                           # NEW: a 0.8 s request counts in 1, 2, 5, 10, 30
                BUCKET_COUNTS[i] += 1


def metrics_text():                            # NEW: build the /metrics page
    lines = ["# TYPE llama_gateway_requests_total counter"]
    with LOCK:
        for status, n in sorted(REQUESTS.items()):
            lines.append(f'llama_gateway_requests_total{{status="{status}"}} {n}')
        lines.append("# TYPE llama_gateway_request_seconds histogram")
        for limit, n in zip(BUCKETS, BUCKET_COUNTS):
            lines.append(f'llama_gateway_request_seconds_bucket{{le="{limit}"}} {n}')
        lines.append(f'llama_gateway_request_seconds_bucket{{le="+Inf"}} {LATENCY_COUNT}')
        lines.append(f"llama_gateway_request_seconds_sum {LATENCY_SUM}")
        lines.append(f"llama_gateway_request_seconds_count {LATENCY_COUNT}")
    text = "\n".join(lines) + "\n"
    try:                                       # NEW: then add llama-server's own metrics (tokens/sec etc.)
        with urllib.request.urlopen(UPSTREAM + "/metrics", timeout=2) as resp:
            text += resp.read().decode()
    except OSError:
        pass
    return text


class Gateway(BaseHTTPRequestHandler):      # our request handler, built on Python's ready-made one

    def log_message(self, *args):
        pass                                # turn off Python's own text log; we write JSON instead

    def do_GET(self):                       # Python calls this for every GET request
        self.forward()

    def do_POST(self):                      # Python calls this for every POST request (chat)
        self.forward()

    def forward(self):
        # 0. NEW: /metrics is answered by the gateway itself, not forwarded
        if self.path == "/metrics":
            body = metrics_text().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        # 1. Request ID: keep the caller's, or make a new 12-character one
        rid = self.headers.get("X-Request-ID") or uuid.uuid4().hex[:12]
        start = time.time()                 # remember when we started, to measure duration

        # 2. Read the body the client sent (the prompt). GET has none.
        length = int(self.headers.get("Content-Length") or 0)
        data = self.rfile.read(length) if length else None

        # 3. Build the same request for llama-server: same path, same method, same body
        req = urllib.request.Request(UPSTREAM + self.path, data=data, method=self.command,
                                     headers={"Content-Type": "application/json", "X-Request-ID": rid})

        # 4. Send it and get the answer
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:   # wait up to 300 s
                code, body = resp.status, resp.read()                # e.g. 200 + the JSON answer
        except urllib.error.HTTPError as e:
            code, body = e.code, e.read()                            # llama-server answered with an error: pass it on
        except OSError:
            code, body = 502, b'{"error":"upstream unavailable"}'   # llama-server not running: 502

        # 5. Send the answer back to the client, with 3 extra headers
        self.send_response(code)                                     # status line, e.g. 200
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Request-ID", rid)                        # so the client can find this request in logs
        self.send_header("X-Served-By", HOST)                        # which node answered
        self.send_header("X-Release", release())                     # which version answered
        self.end_headers()
        self.wfile.write(body)                                       # the answer itself

        # 6. One log line per request, but not for /health (HAProxy calls it every 2 s)
        if self.path != "/health":
            record(code, time.time() - start)                        # NEW: count + time this request
            log_json(request_id=rid, method=self.command, path=self.path, status=code,
                     duration_ms=round((time.time() - start) * 1000, 1), release=release())


if __name__ == "__main__":                  # runs only when started as a program
    log_json(msg="listening", port=PORT, upstream=UPSTREAM)            # one startup log line
    ThreadingHTTPServer(("0.0.0.0", PORT), Gateway).serve_forever()    # listen on all addresses, port 8080; one thread per request; never stop
