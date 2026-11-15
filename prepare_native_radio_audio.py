#!/usr/bin/env python3
"""Decode one owner stream to native-readable float PCM; output stays local."""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / "local-only/toolchains/python-audio"))
import soundfile as sf


def decode(source, destination):
    # Streaming prevents a long station show allocating its entire PCM in RAM.
    with sf.SoundFile(source) as incoming:
        if incoming.channels not in (1, 2) or incoming.samplerate != 32000:
            raise ValueError("Original station programs require 32000 Hz mono/stereo owner streams")
        with sf.SoundFile(destination, mode="w", samplerate=incoming.samplerate,
                          channels=incoming.channels, format="WAV", subtype="FLOAT") as outgoing:
            for block in incoming.blocks(blocksize=65536, dtype="float32", always_2d=True):
                outgoing.write(block)
        return {"frames": incoming.frames, "rate": incoming.samplerate,
                "channels": incoming.channels, "format": "float32-wav"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args()
    print(json.dumps(decode(args.input, args.output)))
