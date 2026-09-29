import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
IDS = ['standaard', 'executive', 'projectoverleg', 'klantgesprek', 'een_op_een', 'brainstorm', 'promptnotitie']


def test_one_source_generates_both_desktop_bundles_and_backend():
    subprocess.run(['python3', 'scripts/generate_profile_templates.py', '--check'], cwd=ROOT, check=True)
    mac = json.loads((ROOT / 'macos/Resources/ProfileTemplates.json').read_text())
    win = json.loads((ROOT / 'windows/src/data/profileTemplates.json').read_text())
    assert mac == win
    assert [profile['id'] for profile in mac] == IDS
    assert len({profile['notulePrompt'] for profile in mac}) == len(IDS)
    for profile in mac:
        assert 'Verzin geen' in profile['systemPrompt']
        assert '<style' not in profile['template']
        assert 'Laat secties zonder inhoud weg' in profile['notulePrompt']
        assert '{{OUTPUT_TEMPLATE}}' in profile['notulePrompt']
    assert 'bedoeling' in mac[-1]['notulePrompt']


def test_no_fixed_heading_order_overrides_template():
    for path in ['macos/Services/LLMService.swift', 'windows/src/services/llm.ts']:
        assert 'Kernuitkomst (maximaal drie zinnen), Besluiten' not in (ROOT / path).read_text()


def test_fixed_transcript_reaches_each_local_and_cloud_profile_with_distinct_structure():
    import importlib.util
    backend_path = ROOT.parent / 'transcript-studio-backend/src/insanely_fast_whisper_api/app/profile_templates.py'
    if not backend_path.exists():
        import pytest
        pytest.skip('Backend checkout is not available beside the native repo')
    spec = importlib.util.spec_from_file_location('generated_profiles', backend_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    profiles = json.loads((ROOT / 'macos/Resources/ProfileTemplates.json').read_text())
    meeting = (ROOT / 'tests/fixtures/meeting-transcript.txt').read_text().strip()
    assert all(term in meeting for term in ['Akkoord', 'chatbot', 'geen eigenaar of deadline', 'Kunnen we'])
    for profile in profiles[:6]:
        cloud = module.PROFILE_DEFINITIONS[profile['id']]
        assert cloud['systemPrompt'] == profile['systemPrompt']
        assert cloud['notulePrompt'] == profile['notulePrompt']
        assert cloud['outputTemplate'] == profile['template']
        assembled = profile['notulePrompt'].replace('{{OUTPUT_TEMPLATE}}', profile['template']).replace('{{TRANSCRIPTION}}', meeting)
        assert meeting in assembled
        assert profile['template'] in assembled
        assert assembled.index('Transcriptie:') < assembled.index('Akkoord:')
    prompt = (ROOT / 'tests/fixtures/promptnote-transcript.txt').read_text().strip()
    prompt_profile = profiles[-1]
    assert prompt in prompt_profile['notulePrompt'].replace('{{TRANSCRIPTION}}', prompt)
    assert 'geen vergadersecties' in prompt_profile['notulePrompt']
