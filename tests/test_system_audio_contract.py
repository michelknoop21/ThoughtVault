from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[1]


def test_audio_capture_uses_tap_without_screen_capture():
    source = (ROOT / 'macos/Services/SystemAudioCapture.swift').read_text()
    assert 'AudioHardwareCreateProcessTap' in source
    assert 'AudioHardwareCreateAggregateDevice' in source
    assert 'kAudioTapPropertyUID' in source
    assert 'AudioDeviceCreateIOProcIDWithBlock' in source
    assert 'ScreenCaptureKit' not in source
    assert '.screen' not in source


def test_audio_permission_has_no_screen_request():
    sources = ''.join(path.read_text() for path in (ROOT / 'macos').rglob('*.swift'))
    assert 'CGRequestScreenCaptureAccess' not in sources
    info = plistlib.loads((ROOT / 'macos/Info.plist').read_bytes())
    assert info.get('NSAudioCaptureUsageDescription')
    assert 'NSScreenCaptureUsageDescription' not in info
