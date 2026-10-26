"""Test dekodovani tela requestu (OpenClaw v2026.10+ posila ChatGPT requesty zstd)."""
import json

import zstandard

from proxy import _decode_request_body

payload = {"model": "gpt-6-astra", "input": [{"role": "user", "content": "Jan Novák"}]}
raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")

# Bez komprese
assert _decode_request_body(raw, "") == payload

# zstd stejne jako Node zlib.zstdCompressSync (frame bez content size i s nim)
assert _decode_request_body(zstandard.ZstdCompressor(level=3).compress(raw), "zstd") == payload
chunked = zstandard.ZstdCompressor(level=3, write_content_size=False).compress(raw)
assert _decode_request_body(chunked, "ZSTD") == payload

# Nepodporovane kodovani se nesmi tvarit jako JSON
try:
    _decode_request_body(raw, "br")
except ValueError:
    pass
else:
    raise AssertionError("br encoding must be rejected")

print("OK")
