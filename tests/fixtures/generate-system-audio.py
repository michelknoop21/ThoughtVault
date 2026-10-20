"""Create the opt-in live audio fixture; this does not enable or play the test.

Run this script, then touch /tmp/thoughtvault-system-audio-test/enabled and run
AudioEnvelopeProcessorTests/testLiveSystemAudioDrivesWaveform. Pause other
system audio first. Remove the enabled marker afterwards.
"""
import math
from pathlib import Path
import struct
import wave

path = Path('/tmp/thoughtvault-system-audio-test/levels.wav')
path.parent.mkdir(parents=True, exist_ok=True)
rate = 48000
with wave.open(str(path), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(rate)
    for seconds, amplitude in [(3, 0), (4, .025), (4, .09), (4, .3), (4, 0)]:
        frames = bytearray()
        for i in range(seconds * rate):
            fade = min(1, i / (rate * .025), (seconds * rate - 1 - i) / (rate * .025))
            sample = amplitude * fade * math.sin(2 * math.pi * 440 * i / rate)
            frames.extend(struct.pack('<h', round(32767 * sample)))
        output.writeframes(frames)
print(path)
