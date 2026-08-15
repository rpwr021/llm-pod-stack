#!/usr/bin/env python3
"""Runtime-agnostic SearXNG search plus bounded, SSRF-safe page reader."""
from __future__ import annotations

import ipaddress
import os
import socket
from urllib.parse import urlparse

import lxml.html
import requests
from mcp.server.mcpserver import MCPServer

SEARX_URL = os.environ.get("SEARX_URL", "http://127.0.0.1:8889/search")
MAX_BYTES = int(os.environ.get("URL_READ_MAX_CONTENT_LENGTH_BYTES", "40000"))
server = MCPServer("pod-web-search")


def public_http_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("Only public http(s) URLs are allowed")
    if parsed.hostname.endswith(".local") or parsed.hostname == "localhost":
        raise ValueError("Local URLs are not allowed")
    for result in socket.getaddrinfo(parsed.hostname, None):
        if not ipaddress.ip_address(result[4][0]).is_global:
            raise ValueError("Private or special-use network addresses are not allowed")


@server.tool()
def web_search(query: str, max_results: int = 8) -> list[dict[str, str]]:
    """Search the live web. Returns titles, URLs, and snippets."""
    response = requests.get(
        SEARX_URL,
        params={"q": query, "format": "json", "language": "en"},
        timeout=15,
    )
    response.raise_for_status()
    maximum = min(max(1, max_results), 8)
    return [
        {"title": item.get("title", ""), "url": item.get("url", ""), "snippet": item.get("content", "")}
        for item in response.json().get("results", [])[:maximum]
    ]


@server.tool()
def read_url(url: str, max_chars: int = 12000) -> dict[str, str]:
    """Fetch and extract a public web page. Output is capped for tool safety."""
    public_http_url(url)
    response = requests.get(url, timeout=20, allow_redirects=False, stream=True,
                            headers={"User-Agent": "llm-pod-stack-web-reader/1.0"})
    if response.is_redirect:
        location = response.headers.get("location", "")
        public_http_url(location)
        response.close()
        response = requests.get(location, timeout=20, stream=True,
                                headers={"User-Agent": "llm-pod-stack-web-reader/1.0"})
    response.raise_for_status()
    content_type = response.headers.get("content-type", "").lower()
    if "text/html" not in content_type and "text/plain" not in content_type:
        raise ValueError(f"Unsupported content type: {content_type or 'unknown'}")
    raw = b""
    for chunk in response.iter_content(8192):
        raw += chunk
        if len(raw) > MAX_BYTES:
            response.close()
            raise ValueError(f"Content too large: exceeds {MAX_BYTES} byte limit")
    response.close()
    text = raw.decode(response.encoding or "utf-8", errors="replace")
    if "text/html" in content_type:
        tree = lxml.html.fromstring(text)
        for node in tree.xpath("//script|//style|//noscript"):
            node.drop_tree()
        text = tree.text_content()
    return {"url": url, "content": " ".join(text.split())[:min(max(1000, max_chars), 20000)]}


if __name__ == "__main__":
    server.run()
