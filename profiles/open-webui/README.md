# Open WebUI profile

Open WebUI connects to all three local OpenAI-compatible endpoints with stable prefixes:

| Prefix | Endpoint | Runtime |
|---|---|---|
| `llama/` | `127.0.0.1:8080/v1` | Llama router / GGUF |
| `vllm/` | `127.0.0.1:8000/v1` | vLLM / native weights |
| `sglang/` | `127.0.0.1:30000/v1` | SGLang / native weights |

All endpoints and the UI bind to loopback. The profile uses Open WebUI's documented multi-connection environment variables and keeps upstream API passthrough disabled. On a 32 GB GPU, use one 27B inference backend at a time; Open WebUI remains running while you switch them.
