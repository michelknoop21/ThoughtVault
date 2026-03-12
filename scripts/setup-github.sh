#!/bin/bash
# Setup GitHub remote and configure secrets for automated releases
set -e

REPO_NAME="transcript-studio-native"

echo "=== GitHub Setup voor TranscriptStudio ==="
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) is niet geïnstalleerd."
    echo "Installeer met: brew install gh"
    exit 1
fi

# Check if logged in
if ! gh auth status &> /dev/null; then
    echo "Je bent niet ingelogd bij GitHub."
    echo "Draai: gh auth login"
    exit 1
fi

# Step 1: Create private repo (if not exists)
echo "--- Stap 1: GitHub repository ---"
if gh repo view "$REPO_NAME" &> /dev/null; then
    echo "  Repo bestaat al: $(gh repo view $REPO_NAME --json url -q .url)"
else
    echo "  Repository aanmaken..."
    gh repo create "$REPO_NAME" --private --source=. --push
    echo "  Repo aangemaakt!"
fi

# Step 2: Add github remote (if not exists)
echo ""
echo "--- Stap 2: Git remote ---"
GITHUB_URL=$(gh repo view "$REPO_NAME" --json sshUrl -q .sshUrl 2>/dev/null)
if git remote get-url github &> /dev/null; then
    echo "  Remote 'github' bestaat al: $(git remote get-url github)"
else
    git remote add github "$GITHUB_URL"
    echo "  Remote 'github' toegevoegd: $GITHUB_URL"
fi

# Step 3: Setup SSH key secret
echo ""
echo "--- Stap 3: SSH key voor server deploy ---"
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
fi

if [ -f "$SSH_KEY_PATH" ]; then
    echo "  SSH key gevonden: $SSH_KEY_PATH"
    read -p "  Deze key toevoegen als GitHub secret? (j/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        gh secret set SSH_PRIVATE_KEY < "$SSH_KEY_PATH"
        echo "  Secret SSH_PRIVATE_KEY toegevoegd!"
    fi
else
    echo "  Geen SSH key gevonden. Voeg handmatig toe:"
    echo "  gh secret set SSH_PRIVATE_KEY < ~/.ssh/jouw_key"
fi

# Step 4: Push to GitHub
echo ""
echo "--- Stap 4: Push naar GitHub ---"
read -p "  Nu pushen naar GitHub? (j/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    git push github main --tags
    echo "  Gepusht!"
fi

echo ""
echo "=== Setup compleet! ==="
echo ""
echo "Gebruik:"
echo "  git push github main --tags    # Push naar GitHub (triggert build bij tags)"
echo "  git push --all                 # Push naar alle remotes"
echo ""
echo "Of configureer git om naar beide remotes te pushen:"
echo "  git remote set-url --add --push origin $(git remote get-url origin)"
echo "  git remote set-url --add --push origin $GITHUB_URL"
echo ""
echo "Dan pusht 'git push' automatisch naar GitLab EN GitHub."
