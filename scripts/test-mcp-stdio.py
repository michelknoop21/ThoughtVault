#!/usr/bin/env python3
"""End-to-end check of the ThoughtVault MCP server, the way an MCP client uses it.

Starts `<app binary> --mcp` as a stdio server and talks JSON-RPC to it. ThoughtVault must be
running with the AI connection on. With --write, writing must be allowed too: the script then
creates one note titled "MCP-proef <time>", reads it back and renames it. Use a test install,
never one with real notes you do not want touched.

    python3 scripts/test-mcp-stdio.py /path/to/ThoughtVault [--write]
"""
import json
import subprocess
import sys
import time


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    binary, write = sys.argv[1], "--write" in sys.argv
    proc = subprocess.Popen([binary, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8")
    next_id = 0

    def request(method, params=None):
        nonlocal next_id
        next_id += 1
        message = {"jsonrpc": "2.0", "id": next_id, "method": method}
        if params is not None:
            message["params"] = params
        proc.stdin.write(json.dumps(message) + "\n")
        proc.stdin.flush()
        line = proc.stdout.readline()
        if not line:
            raise SystemExit(f"no answer to {method}; stderr: {proc.stderr.read().strip()}")
        reply = json.loads(line)
        assert reply.get("id") == next_id, reply
        return reply

    def call(name, arguments):
        result = request("tools/call", {"name": name, "arguments": arguments})["result"]
        assert not result.get("isError"), f"{name}: {result['content'][0]['text']}"
        return result["structuredContent"]

    init = request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                                  "clientInfo": {"name": "test-mcp-stdio", "version": "1"}})["result"]
    print("initialize:", init["serverInfo"], init["protocolVersion"])
    proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
    proc.stdin.flush()

    names = [tool["name"] for tool in request("tools/list")["result"]["tools"]]
    print(f"tools/list: {len(names)} tools")
    assert ("update_note" in names) == write, f"write tools listed: {'update_note' in names}, expected {write}"

    notes = call("list_notes", {"limit": 5})
    print(f"list_notes: total {notes['total']}")
    for name in ["list_library", "list_profiles", "list_people", "list_recordings", "get_glossary", "get_processing_status"]:
        value = call(name, {})
        print(f"{name}: {', '.join(f'{k}={len(v)}' for k, v in value.items() if isinstance(v, list))}")

    if write:
        title = f"MCP-proef {time.strftime('%H:%M:%S')}"
        created = call("create_note", {"title": title, "transcript": "Dit is een proef.",
                                       "notule_markdown": "# Proef\n\n- Actie: niets"})
        note = call("get_note", {"id": created["id"]})
        assert note["title"] == title and "Proef" in note["notule"], note
        updated = call("update_note", {"id": created["id"], "revision": note["revision"], "title": title + " (gewijzigd)"})
        stale = request("tools/call", {"name": "update_note", "arguments": {"id": created["id"], "revision": note["revision"], "title": "x"}})
        assert stale["result"].get("isError"), "stale revision was accepted"
        found = call("list_notes", {"query": "gewijzigd"})
        assert any(n["id"] == created["id"] for n in found["notes"]), found
        print(f"create/get/update_note: ok ({created['id']}, revision {note['revision']} -> {updated['revision']}), stale revision refused")

    proc.stdin.close()
    proc.wait(timeout=35)
    print("OK, bridge exit code", proc.returncode)
    return 0


if __name__ == "__main__":
    sys.exit(main())
