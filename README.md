# LLM pod stack

Reusable infrastructure for running local LLM profiles on fresh Linux GPU pods. It keeps the shared concerns—`uv`, Hugging Face Xet, private loopback services, logs, and SSH tunnelling—separate from each serving runtime.

Profiles currently included:

| Profile | Status | Purpose |
|---|---|---|
| `llama-router` | validated | Llama.app UI/router, Qwen 3.8 27B GGUF, embedded MTP, search and URL-reader MCP tools |
| `open-webui` | validated setup | Common browser UI for the three OpenAI-compatible serving backends |
| `vllm` | experimental | native Transformers/MXFP4 serving; model chosen explicitly at launch |
| `sglang` | experimental | SGLang serving; model chosen explicitly at launch |

No model weights, API tokens, caches, or binaries are in this repository.

## Quick start

```bash
git clone https://github.com/rpwr021/llm-pod-stack.git
cd llm-pod-stack
./bootstrap.sh llama-router
```

The Llama profile installs the official unified `llama` binary, uses `uv`, downloads Qwen 3.8 through Hugging Face Xet, and starts loopback-only services. Set `HF_TOKEN=...` if a future model revision needs authentication.

From your Mac, tunnel the UI (replace host/port with the RunPod direct TCP endpoint):

```bash
ssh -N -L 9932:127.0.0.1:8080 -p POD_PORT root@POD_HOST -i ~/.ssh/YOUR_PRIVATE_KEY
```

Then open `http://127.0.0.1:9932`.

## Profiles

### llama-router

```bash
./bootstrap.sh llama-router
```

Default model: Qwen 3.8 27B `UD-Q4_K_XL` with vision projector, CUDA offload, Flash Attention, 32K context, and embedded MTP cap 3. Its SearXNG-backed MCP server exposes `web_search` and safe, bounded `read_url`.

Validated RTX 5090 MTP sweep: 1 = 100.63 tok/s, 2 = 97.69, **3 = 101.68**, 4 = 84.21, 5 = 74.02. Set `MTP_DEPTH` to override.

### Open WebUI

```bash
./bootstrap.sh open-webui
```

Starts a private Open WebUI on port 3000. It registers the loopback Llama router, vLLM, and SGLang OpenAI-compatible endpoints with distinct model prefixes. The three 27B backends cannot fit concurrently on a 32 GB GPU; start the backend you want to use, then select its prefixed model in Open WebUI. Tunnel it with `ssh -N -L 9933:127.0.0.1:3000 ...`.

### vLLM

```bash
./bootstrap.sh vllm  # defaults to unsloth/Qwen3.8-27B-NVFP4
```

This is an explicit experimental profile for CUDA/Blackwell native Transformers weights, including MXFP4. It does not silently replace the Llama router or download a large model until `MODEL` is supplied. See [profiles/vllm](profiles/vllm).

### SGLang

```bash
MODEL=your-org/your-model ./bootstrap.sh sglang
```

This is likewise explicit and isolated. SGLang compatibility varies by architecture and quantization; its profile reports the launched command rather than claiming a universal optimum.

## Shared configuration

All profiles use `/workspace` for persistent models/stacks and `/tmp` for disposable `uv` and Xet caches by default. They use the transient pod's system Python and `uv --system --break-system-packages`—no virtual environments are created. Services bind to `127.0.0.1`; do not expose them without authentication.

Useful common overrides:

```bash
WORKSPACE=/workspace
UV_CACHE_DIR=/tmp/uv-cache
HF_XET_CACHE=/tmp/hf-xet
HF_TOKEN=...
```
