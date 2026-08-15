# Shared web MCP

`web_search_mcp.py` is independent of a serving runtime. It starts as a standard MCP stdio server and exposes `web_search` through a private SearXNG instance plus `read_url` for bounded public-page extraction.

The Llama router profile registers it automatically. Other clients or runtimes can use the same command and arguments from their MCP configuration once a local SearXNG service is running.
