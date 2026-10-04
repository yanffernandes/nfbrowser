#!/usr/bin/env python3
"""Small authenticated client for NF Browser's loopback control endpoint."""

import argparse
import base64
import json
import os
import sys
import tempfile
import time
import urllib.error
import urllib.request


def fail(message):
    print(f"ora-browser: {message}", file=sys.stderr)
    raise SystemExit(2)


def request(action, payload=None):
    endpoint = os.environ.get("ORA_BROWSER_ENDPOINT", "").rstrip("/")
    token = os.environ.get("ORA_BROWSER_TOKEN", "")
    if not endpoint or not token:
        fail("no NF Browser session is connected; open the Browser Agent panel and start a terminal")

    body = json.dumps(payload or {}).encode("utf-8")
    req = urllib.request.Request(
        f"{endpoint}/browser/{action}",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Connection": "close",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        try:
            message = json.loads(detail).get("error", detail)
        except json.JSONDecodeError:
            message = detail
        fail(str(message))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        fail(f"could not reach NF Browser: {error}")

    if not result.get("ok", False):
        fail(result.get("error", "browser command failed"))
    return result


def main():
    parser = argparse.ArgumentParser(prog="ora-browser", description="Control the active NF Browser page")
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("tabs")
    subparsers.add_parser("snapshot")
    subparsers.add_parser("back")
    subparsers.add_parser("forward")
    subparsers.add_parser("reload")

    switch = subparsers.add_parser("switch")
    switch.add_argument("tab_id")

    navigate = subparsers.add_parser("navigate")
    navigate.add_argument("url")

    scroll = subparsers.add_parser("scroll")
    scroll.add_argument("direction", choices=("up", "down", "left", "right"))
    scroll.add_argument("pixels", type=int, nargs="?", default=600)

    click = subparsers.add_parser("click")
    click.add_argument("reference")
    click.add_argument("--confirm", action="store_true")

    fill = subparsers.add_parser("fill")
    fill.add_argument("reference")
    fill.add_argument("text")

    screenshot = subparsers.add_parser("screenshot")
    screenshot.add_argument("--output", "-o")

    args = parser.parse_args()
    payload = {}
    if args.action == "switch":
        payload = {"tab_id": args.tab_id}
    elif args.action == "navigate":
        payload = {"url": args.url}
    elif args.action == "scroll":
        payload = {"direction": args.direction, "pixels": args.pixels}
    elif args.action == "click":
        payload = {"reference": args.reference, "confirm": args.confirm}
    elif args.action == "fill":
        payload = {"reference": args.reference, "text": args.text}
    elif args.action == "screenshot":
        payload = {"output": args.output or ""}

    result = request(args.action, payload)
    if args.action == "screenshot":
        image = base64.b64decode(result.pop("png_base64"))
        output = args.output or os.path.join(tempfile.gettempdir(), f"ora-browser-{int(time.time())}.png")
        with open(output, "wb") as image_file:
            image_file.write(image)
        result["screenshot_path"] = os.path.abspath(output)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
