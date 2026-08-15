# vLLM profile

This profile is for CUDA-native Transformer weights, including MXFP4 on supported NVIDIA hardware. It intentionally requires `MODEL`; that avoids an accidental multi-gigabyte download or replacing another running stack.

Example:

```bash
../../bootstrap.sh vllm  # defaults to unsloth/Qwen3.8-27B-NVFP4
```

The profile first reuses the pod image's existing `python3`, CUDA Torch, and Jupyter runtime. If vLLM is absent it installs through `uv --system`; it does not create another Torch-heavy virtual environment. RTX 5090 uses the CUDA 13.2 Torch wheel by default (`TORCH_BACKEND=cu132`); force that replacement after a prior incompatible install with `REINSTALL_TORCH=1`. The server is loopback-only on port 8000 and uses Hugging Face Xet high-performance mode, FP8 KV cache, prefix caching, and Qwen 3.5 native MTP with one speculative token as the conservative first setting. Benchmark before raising `SPEC_TOKENS`.
