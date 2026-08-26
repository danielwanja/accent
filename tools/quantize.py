#!/usr/bin/env python3
"""Int8-quantize the converted phoneme model and validate argmax agreement."""
import pathlib

import numpy as np
import coremltools as ct
import coremltools.optimize.coreml as cto

OUT = pathlib.Path(__file__).parent / "models"
src = OUT / "PhonemeRecognizer.mlpackage"

print("loading fp16 model …", flush=True)
model = ct.models.MLModel(str(src))

config = cto.OptimizationConfig(
    global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8"))
quantized = cto.linear_quantize_weights(model, config)

ok = True
rng = np.random.default_rng(7)
for seconds in (2.0, 5.0):
    n = int(16000 * seconds)
    x = rng.standard_normal((1, n)).astype(np.float32) * 0.1
    x = (x - x.mean()) / np.sqrt(x.var() + 1e-7)
    ref = np.asarray(model.predict({"audio": x})["logits"])
    got = np.asarray(quantized.predict({"audio": x})["logits"])
    agree = (ref.argmax(-1) == got.argmax(-1)).mean()
    print(f"{seconds}s: argmax agreement fp16 vs int8 = {agree:.3f}", flush=True)
    if agree < 0.95:
        ok = False

if not ok:
    raise SystemExit("quantization degraded the model too much")

path = OUT / "PhonemeRecognizer-int8.mlpackage"
quantized.save(str(path))
size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
print(f"saved {path} ({size / 1e6:.1f} MB)", flush=True)
