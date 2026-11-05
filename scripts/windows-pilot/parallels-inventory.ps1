# Read-only pre-install inventory. Does not scan, install, download, or change policy.
$ErrorActionPreference = 'Stop'
$report = [ordered]@{ captured_at = (Get-Date).ToString('o'); environment = 'Existing Parallels user VM; not clean' }
function Read-Check($Name, [scriptblock]$Action) {
    try { $report[$Name] = & $Action } catch { $report[$Name] = @{ error = $_.Exception.Message } }
}
Read-Check architecture { [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
Read-Check windows { Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture,LastBootUpTime }
Read-Check cpu { Get-CimInstance Win32_Processor | Select-Object Name,Architecture,NumberOfCores,NumberOfLogicalProcessors }
Read-Check memory { Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory,Domain,PartOfDomain }
Read-Check disk { Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object Size,FreeSpace,FileSystem }
Read-Check token {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    @{ elevated_admin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); administrators_sid_in_token = @($identity.Groups.Value) -contains 'S-1-5-32-544' }
}
Read-Check defender { Get-MpComputerStatus | Select-Object AMRunningMode,AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,BehaviorMonitorEnabled,IsTamperProtected,AntivirusSignatureVersion,AntivirusSignatureLastUpdated,AntivirusSignatureAge,NISEnabled,NISSignatureVersion }
Read-Check security_center { Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct | Select-Object displayName,productState }
Read-Check uac { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' | Select-Object EnableLUA,ConsentPromptBehaviorAdmin,ConsentPromptBehaviorUser,PromptOnSecureDesktop }
Read-Check smartscreen { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' | Select-Object SmartScreenEnabled }
Read-Check sac { Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' | Select-Object VerifiedAndReputablePolicyState }
Read-Check policy_system { Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' | Select-Object EnableSmartScreen,ShellSmartScreenLevel }
Read-Check policy_defender { Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' | Select-Object DisableAntiSpyware,DisableAntiVirus }
Read-Check applocker { Get-AppLockerPolicy -Effective -Xml }
Read-Check installed_apps {
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') |
        ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
        Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,Publisher | Sort-Object DisplayName
}
Read-Check thoughtvault_existing {
    foreach ($base in @($env:LOCALAPPDATA,$env:APPDATA)) {
        $path = Join-Path $base 'nl.prezent.transcript-studio'
        @{ path = $path; exists = (Test-Path $path); files = if(Test-Path $path){ @(Get-ChildItem $path -File -Recurse -ErrorAction SilentlyContinue).Count }else{0} }
    }
}
Read-Check available_tools { Get-Command codex,node,npm,winget,ollama,ffprobe -ErrorAction SilentlyContinue | Select-Object Name,Source }
Read-Check execution_policy { Get-ExecutionPolicy -List | Select-Object Scope,ExecutionPolicy }
Read-Check documents_path { [Environment]::GetFolderPath('MyDocuments') }
Read-Check desktop_path { [Environment]::GetFolderPath('Desktop') }
$report | ConvertTo-Json -Depth 7
