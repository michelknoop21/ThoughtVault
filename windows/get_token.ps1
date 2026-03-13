# Haal het TranscriptStudio authToken uit de Windows Credential Manager
# Service: "nl.prezent.transcript-studio"
# Key: "authToken"

Write-Host "Zoek TranscriptStudio token in Windows Credential Manager..."

try {
    # Probeer via VaultCmd ( Credential Manager )
    $result = cmd /c "vaultcmd /listcreds:\"Windows Credentials\" /format:xml 2>nul" | Select-String -Pattern "transcript-studio" -Context 0,10

    if ($result) {
        Write-Host "Gevonden:"
        Write-Host $result
    } else {
        Write-Host "Geen token gevonden met vaultcmd"
    }
} catch {
    Write-Host "Fout: $_"
}

Write-Host ""
Write-Host "Alternatief: gebruik browser DevTools:"
Write-Host "1. Open de app in Chrome/Edge (http://localhost:1420)"
Write-Host "2. F12 → Application tab → Local Storage"
Write-Host "3. Zoek naar 'authStore' of 'token'"
Write-Host "4. Kopieer de token waarde"
