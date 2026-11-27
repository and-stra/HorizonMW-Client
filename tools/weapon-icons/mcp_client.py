import json
import subprocess
import sys
import time

EXE = r"C:\Games\cod-hwm\hmw-workbench\build\bin\Release\hmw-workbench.exe"
ROOT = r"C:\Games\cod-hwm\hmw-workbench"


class Mcp:
    def __init__(self, exe=EXE, cwd=ROOT):
        self.p = subprocess.Popen([exe, "-mcp"], cwd=cwd, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                                  encoding="utf-8", bufsize=1)
        self.next_id = 1

    def _send(self, method, params=None):
        msg = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            msg["params"] = params
        self.next_id += 1
        self.p.stdin.write(json.dumps(msg) + "\n")
        self.p.stdin.flush()
        while True:
            line = self.p.stdout.readline()
            if not line:
                raise RuntimeError("workbench closed")
            line = line.strip()
            if not line:
                continue
            try:
                answer = json.loads(line)
            except Exception:
                continue
            if answer.get("id") == msg["id"]:
                return answer

    def initialize(self):
        r = self._send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                      "clientInfo": {"name": "mwx-icons", "version": "0"}})
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.p.stdin.flush()
        return r

    def call(self, name, arguments=None):
        return self._send("tools/call", {"name": name, "arguments": arguments or {}})

    def tools(self):
        return self._send("tools/list")


if __name__ == "__main__":
    m = Mcp()
    print("init", json.dumps(m.initialize())[:200])
    tools = m.tools()
    names = [t["name"] for t in tools["result"]["tools"]]
    print("tools:", ", ".join(names))
    r = m.call("load_model", {"model": "vm_crossbow_base"})
    print("load_model:", json.dumps(r)[:300])
    s = m.call("screenshot", {"path": "review/icons-test/crossbow.png", "view": "orbit",
                              "width": 512, "height": 256, "yaw": 35, "pitch": 12, "dist": 60, "fov": 35})
    print("screenshot:", json.dumps(s)[:300])
    m.p.stdin.close()
    m.p.terminate()
