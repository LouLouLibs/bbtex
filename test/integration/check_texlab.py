#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Exercise installed TexLab over LSP using disposable LaTeX/BibTeX files."""
import json
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time

def main():
    executable = shutil.which("texlab")
    if not executable:
        raise SystemExit("texlab not found")
    with tempfile.TemporaryDirectory(prefix="bbtex-lsp-") as directory:
        root = Path(directory)
        source = "\\documentclass{article}\n\\begin{document}\n\\section{Test}\\label{sec:test}\nSee \\ref{sec:test}.\nSee \\cite{sample2026}.\n\\bibliography{refs}\n\\end{document}\n"
        bib = "@article{sample2026, author={Example, Alice}, title={Sample Paper}, year={2026}}\n"
        tex = root / "main.tex"
        bibliography = root / "refs.bib"
        tex.write_text(source)
        bibliography.write_text(bib)
        process = subprocess.Popen([executable], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        messages = queue.Queue()
        def receive():
            try:
                while True:
                    headers = {}
                    while True:
                        line = process.stdout.readline()
                        if not line:
                            return
                        if line == b"\r\n":
                            break
                        key, value = line.decode().split(":", 1)
                        headers[key.lower()] = value.strip()
                    messages.put(json.loads(process.stdout.read(int(headers["content-length"]))))
            finally:
                messages.put(None)
        threading.Thread(target=receive, daemon=True).start()
        def send(message):
            body = json.dumps({"jsonrpc": "2.0", **message}).encode()
            process.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
            process.stdin.flush()
        def response(identifier):
            deadline = time.monotonic() + 15
            while True:
                item = messages.get(timeout=max(.01, deadline - time.monotonic()))
                if item is None:
                    raise RuntimeError("TexLab exited unexpectedly")
                if "method" in item and "id" in item:
                    result = None
                    if item["method"] == "workspace/configuration":
                        result = [{} for _ in item["params"]["items"]]
                    send({"id": item["id"], "result": result})
                elif item.get("id") == identifier:
                    if "error" in item:
                        raise RuntimeError(item["error"])
                    return item.get("result")
                if time.monotonic() > deadline:
                    raise TimeoutError("TexLab response timeout")
        try:
            send({"id": 1, "method": "initialize", "params": {
                "processId": None, "rootUri": root.as_uri(),
                "capabilities": {"workspace": {"configuration": True}},
                "workspaceFolders": [{"uri": root.as_uri(), "name": "bbtex-test"}]}})
            capabilities = response(1)["capabilities"]
            assert capabilities.get("completionProvider"), "No completion capability"
            assert capabilities.get("definitionProvider"), "No definition capability"
            send({"method": "initialized", "params": {}})
            for file, language, text in [(bibliography, "bibtex", bib), (tex, "latex", source)]:
                send({"method": "textDocument/didOpen", "params": {"textDocument": {
                    "uri": file.as_uri(), "languageId": language, "version": 1, "text": text}}})
            for identifier, line, marker, expected in [(2, 3, "\\ref{", "sec:test"),
                                                        (3, 4, "\\cite{", "sample2026")]:
                offset = source.splitlines()[line].index(marker) + len(marker)
                send({"id": identifier, "method": "textDocument/completion", "params": {
                    "textDocument": {"uri": tex.as_uri()},
                    "position": {"line": line, "character": offset}}})
                result = response(identifier)
                items = result.get("items", []) if isinstance(result, dict) else result or []
                assert any(expected in item.get("label", "") for item in items), (expected, items)
                print("Completion verified:", expected)
            send({"id": 4, "method": "textDocument/definition", "params": {
                "textDocument": {"uri": tex.as_uri()},
                "position": {"line": 3, "character": 12}}})
            definitions = response(4)
            assert definitions, "Reference definition not found"
            location = definitions[0] if isinstance(definitions, list) else definitions
            assert location.get("uri", location.get("targetUri")) == tex.as_uri()
            print("Reference definition verified")
            send({"id": 5, "method": "shutdown"})
            response(5)
            send({"method": "exit"})
            process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)

if __name__ == "__main__":
    main()
