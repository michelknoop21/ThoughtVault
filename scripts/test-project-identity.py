#!/usr/bin/env python3
"""Product naming and build ownership must not revert to the predecessor project."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
for relative in ('windows/package.json', 'windows/package-lock.json'):
    assert json.loads((root / relative).read_text())['name'] == 'thoughtvault-windows', relative
cargo = (root / 'windows/src-tauri/Cargo.toml').read_text()
assert 'name = "thoughtvault"' in cargo and 'name = "thoughtvault_lib"' in cargo
assert 'thoughtvault_lib::run()' in (root / 'windows/src-tauri/src/main.rs').read_text()
for name in ('deploy-dev.sh', 'deploy-production.sh'):
    source = (root / 'scripts' / name).read_text()
    assert 'michelknoop21/ThoughtVault' in source and 'gh workflow run' in source
    assert 'gitlab' not in source.lower() and 'git push' not in source
assert not (root / '.gitlab-ci.yml').exists()
assert 'ssh://gitea/michelk/ThoughtVault.git' in (root / 'README.md').read_text()
# Existing storage IDs and OAuth callback registrations are compatibility, not product labels.
old_brand = re.compile(r'(?i:Transcript Studio)|TranscriptStudio|transcript-studio-(?:native|windows|backend|expert)')
paths = [root / 'README.md', root / 'CLAUDE.md']
for directory, suffix in [('docs', '*.md'), ('macos', '*.swift'), ('windows/src', '*.tsx'), ('windows/src', '*.ts')]:
    paths.extend(p for p in (root / directory).rglob(suffix) if 'mcp' not in p.parts)
for path in paths:
    assert not old_brand.search(path.read_text()), f'Old product branding: {path.relative_to(root)}'
print('ThoughtVault branding and Windows build ownership passed')
