#!/usr/bin/env python3
"""Convert MultiBridge/wav2vec-LnNor-IPA-ft (wav2vec2-base phoneme CTC) to Core ML.

Outputs into tools/models/:
  PhonemeRecognizer.mlpackage  - FP16 Core ML program, flexible audio length
  phoneme_labels.json          - id -> IPA token, plus preprocessing metadata

Validates Core ML logits against PyTorch on random audio before saving.
"""
import json
import pathlib
import sys

import numpy as np
import torch
import coremltools as ct
from transformers import Wav2Vec2Processor, Wav2Vec2ForCTC

MODEL_ID = "MultiBridge/wav2vec-LnNor-IPA-ft"
OUT = pathlib.Path(__file__).parent / "models"
OUT.mkdir(exist_ok=True)

print(f"loading {MODEL_ID} …", flush=True)
processor = Wav2Vec2Processor.from_pretrained(MODEL_ID)
model = Wav2Vec2ForCTC.from_pretrained(MODEL_ID)
model.eval()

fe = processor.feature_extractor
vocab = processor.tokenizer.get_vocab()  # token -> id
id_to_token = {v: k for k, v in vocab.items()}
print(f"vocab size {len(vocab)}, sample rate {fe.sampling_rate}, "
      f"do_normalize {fe.do_normalize}", flush=True)

meta = {
    "model": MODEL_ID,
    "sample_rate": fe.sampling_rate,
    "do_normalize": bool(fe.do_normalize),
    "pad_token": processor.tokenizer.pad_token,        # CTC blank
    "pad_token_id": processor.tokenizer.pad_token_id,
    "word_delimiter_token": getattr(processor.tokenizer, "word_delimiter_token", None),
    "labels": [id_to_token[i] for i in range(len(vocab))],
}
(OUT / "phoneme_labels.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
print("labels written", flush=True)


class LogitsOnly(torch.nn.Module):
    def __init__(self, inner):
        super().__init__()
        self.inner = inner

    def forward(self, audio):
        return self.inner(audio).logits


wrapped = LogitsOnly(model)
example = torch.randn(1, 80000)  # 5 s at 16 kHz
with torch.no_grad():
    traced = torch.jit.trace(wrapped, example)

print("converting …", flush=True)
audio_shape = ct.Shape(shape=(1, ct.RangeDim(1600, 480000, default=80000)))
mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="audio", shape=audio_shape, dtype=np.float32)],
    outputs=[ct.TensorType(name="logits", dtype=np.float32)],
    minimum_deployment_target=ct.target.iOS17,
    compute_precision=ct.precision.FLOAT16,
    convert_to="mlprogram",
)

# Validate on random audio at two lengths, normalized the way the app will.
def normalize(x):
    if not fe.do_normalize:
        return x
    return (x - x.mean()) / np.sqrt(x.var() + 1e-7)

ok = True
for seconds in (2.0, 5.0):
    n = int(16000 * seconds)
    audio = normalize(np.random.randn(1, n).astype(np.float32) * 0.1)
    with torch.no_grad():
        ref = wrapped(torch.from_numpy(audio)).numpy()
    got = mlmodel.predict({"audio": audio})["logits"]
    ref_ids = ref.argmax(-1)[0]
    got_ids = np.asarray(got).argmax(-1)[0]
    agree = (ref_ids == got_ids).mean()
    max_err = np.abs(np.asarray(got) - ref).max()
    print(f"{seconds}s: frames {ref.shape[1]}, argmax agreement {agree:.3f}, "
          f"max |Δlogit| {max_err:.3f}", flush=True)
    if agree < 0.98:
        ok = False

if not ok:
    print("VALIDATION FAILED", flush=True)
    sys.exit(1)

path = OUT / "PhonemeRecognizer.mlpackage"
mlmodel.save(str(path))
size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
print(f"saved {path} ({size / 1e6:.1f} MB)", flush=True)
