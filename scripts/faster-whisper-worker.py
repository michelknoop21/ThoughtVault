"""Bundled CPU Faster Whisper runner; stdout contains progress only, never speech."""
import argparse
import json
from pathlib import Path


def transcribe(model_path, audio_path, output_path, vocabulary=""):
    from faster_whisper import WhisperModel
    model = WhisperModel(str(model_path), device="cpu", compute_type="int8", cpu_threads=4, local_files_only=True)
    segments, info = model.transcribe(str(audio_path), language="nl", beam_size=5,
        vad_filter=True, initial_prompt=vocabulary or None, condition_on_previous_text=False)
    text = []
    for segment in segments:
        text.append(segment.text.strip())
        progress = min(99, int(segment.end / max(info.duration, 0.001) * 100))
        print(json.dumps({"progress": progress}), flush=True)
    Path(output_path).write_text(" ".join(text).strip(), encoding="utf-8")
    print(json.dumps({"progress": 100}), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--model")
    parser.add_argument("--audio")
    parser.add_argument("--output")
    parser.add_argument("--vocabulary", default="")
    args = parser.parse_args()
    if args.probe:
        import faster_whisper
        import ctranslate2
        print(json.dumps({"engine": "faster-whisper", "version": faster_whisper.__version__, "device": "cpu", "compute_type": "int8"}), flush=True)
    else:
        if not all((args.model, args.audio, args.output)):
            parser.error("model, audio and output are required")
        transcribe(args.model, args.audio, args.output, args.vocabulary)


if __name__ == "__main__":
    main()
