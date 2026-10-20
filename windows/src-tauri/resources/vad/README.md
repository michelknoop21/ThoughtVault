Silero VAD 5.1.2, converted to GGML by the whisper.cpp project.

Source: https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin
SHA256: 29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf
License: MIT, see LICENSE (also included in the installer).

The model is embedded so speech detection also works offline. whisper-rs uses
whisper_full_with_state, which does not run the built-in VAD path. We therefore
use its standalone detector and transcribe bounded speech ranges.
