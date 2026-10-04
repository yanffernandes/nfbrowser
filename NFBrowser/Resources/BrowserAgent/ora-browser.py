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


def prog_name():
    name = os.path.basename(sys.argv[0])
    return name if name and not name.endswith(".py") else "nf-browser"


def fail(message):
    print(f"{prog_name()}: {message}", file=sys.stderr)
    raise SystemExit(2)


def request(action, payload=None):
    endpoint = (os.environ.get("NF_BROWSER_ENDPOINT") or os.environ.get("ORA_BROWSER_ENDPOINT", "")).rstrip("/")
    token = os.environ.get("NF_BROWSER_TOKEN") or os.environ.get("ORA_BROWSER_TOKEN", "")
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
    parser = argparse.ArgumentParser(prog=prog_name(), description="Control the active NF Browser page")
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("tabs", help="List all tabs in the active Space")
    subparsers.add_parser("snapshot", help="Inspect active page structure and element references")
    subparsers.add_parser("back", help="Navigate active tab back")
    subparsers.add_parser("forward", help="Navigate active tab forward")
    subparsers.add_parser("reload", help="Reload active tab")
    subparsers.add_parser("text", help="Extract readable text and title from the active page")

    switch = subparsers.add_parser("switch", help="Switch to a tab by ID")
    switch.add_argument("tab_id", help="UUID of the tab to switch to")

    open_cmd = subparsers.add_parser("open", aliases=["new-tab"], help="Open a URL in a new tab")
    open_cmd.add_argument("url", help="HTTP or HTTPS URL to open")
    open_cmd.add_argument("--background", action="store_true", help="Do not focus the new tab")

    close_cmd = subparsers.add_parser("close-tab", aliases=["close"], help="Close a tab")
    close_cmd.add_argument("tab_id", nargs="?", default=None, help="Tab UUID to close (active tab if omitted)")

    search_cmd = subparsers.add_parser("search", help="Search the web with the default search engine")
    search_cmd.add_argument("query", help="Search query string")
    search_cmd.add_argument("--current-tab", action="store_true", help="Search in active tab instead of a new tab")

    navigate = subparsers.add_parser("navigate", help="Navigate the active tab to a URL")
    navigate.add_argument("url", help="HTTP or HTTPS URL")

    scroll = subparsers.add_parser("scroll", help="Scroll the active page")
    scroll.add_argument("direction", choices=("up", "down", "left", "right"))
    scroll.add_argument("pixels", type=int, nargs="?", default=600)

    click = subparsers.add_parser("click", help="Click an element reference from the snapshot")
    click.add_argument("reference", help="Element reference like @e1")
    click.add_argument("--confirm", action="store_true", help="Confirm click on state-changing controls")

    fill = subparsers.add_parser("fill", help="Fill an input or textarea element")
    fill.add_argument("reference", help="Element reference like @e2")
    fill.add_argument("text", help="Text to fill")

    screenshot = subparsers.add_parser("screenshot", help="Capture a viewport screenshot as PNG")
    screenshot.add_argument("--output", "-o", help="Target PNG file path")

    args = parser.parse_args()
    payload = {}
    action = args.action

    if args.action in ("open", "new-tab"):
        action = "open"
        payload = {"url": args.url, "focus": not args.background}
    elif args.action in ("close-tab", "close"):
        action = "close-tab"
        payload = {"tab_id": args.tab_id} if args.tab_id else {}
    elif args.action == "search":
        action = "search"
        payload = {"query": args.query, "new_tab": not args.current_tab}
    elif args.action == "text":
        action = "text"
        payload = {}
    elif args.action == "switch":
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

    result = request(action, payload)
    if action == "screenshot":
        image = base64.b64decode(result.pop("png_base64"))
        output = args.output or os.path.join(tempfile.gettempdir(), f"ora-browser-{int(time.time())}.png")
        with open(output, "wb") as image_file:
            image_file.write(image)
        result["screenshot_path"] = os.path.abspath(output)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
