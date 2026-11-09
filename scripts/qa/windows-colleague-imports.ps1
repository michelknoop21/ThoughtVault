param([switch]$VerifyOnly)
# Materialise candidate metadata before registering this standalone, hash-pinned scenario.
$ExpectedVersion='__CANDIDATE_VERSION__'
$ExpectedExeSha256='__CANDIDATE_EXE_SHA256__'
$ExpectedLlmModel='__CANDIDATE_LLM_MODEL__'
$ExpectedFixturePath='__IMPORT_FIXTURE_PATH__'
$ExpectedFixtureSha256='__IMPORT_FIXTURE_SHA256__'
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='--force-renderer-accessibility'
$exe='C:\Program Files\ThoughtVault\ThoughtVault.exe'
if((Get-Item $exe).VersionInfo.ProductVersion -ne $ExpectedVersion){throw 'Wrong candidate'}
if((Get-FileHash $exe -Algorithm SHA256).Hash -ne $ExpectedExeSha256){throw 'Candidate executable hash differs'}
if($VerifyOnly){Write-Output 'Candidate metadata verified';exit 0}
if(Get-Process ThoughtVault -ErrorAction SilentlyContinue){throw 'Existing app; do not interrupt'}
$report=@{version=$ExpectedVersion;started=[DateTime]::UtcNow.ToString('o');steps=@();exports=@();status='failed';scope='Candidate native recording/import and audited note; exports require separate assertions';pdf='not_tested_print_dialog_route'}
$p=$null
function Progress([string]$stage){
 $report.stage=$stage;$report.progressUtc=[DateTime]::UtcNow.ToString('o')
 $report|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $env:DALF_ARTIFACT_DIR 'progress.json')
}
function Find-Control([string]$name,[string]$type='') {
 $conditions=@((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$name)))
 if($type){$conditions+=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,([System.Windows.Automation.ControlType]::$type))}
 $c=if($conditions.Count -eq 1){$conditions[0]}else{New-Object System.Windows.Automation.AndCondition($conditions)}
 $deadline=[DateTime]::UtcNow.AddSeconds(15)
 do{
  $p.Refresh();$script:w=[System.Windows.Automation.AutomationElement]::FromHandle($script:mainHandle)
  $e=$script:w.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$c)
  if($e -and $e.Current.IsEnabled){return $e}
  Start-Sleep -Milliseconds 250
 }while([DateTime]::UtcNow -lt $deadline)
 throw "Control not found: $name"
}
function Activate([string]$name,[string]$type='') {
 Progress ('activate: '+$name)
 $e=Find-Control $name $type
 $pattern=$e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
 $pattern.Invoke()
 Start-Sleep -Milliseconds 500
 $report.steps+=@{action=$name;utc=[DateTime]::UtcNow.ToString('o');result='invoked'}
}
Add-Type @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class TVNativeDialog {
 public delegate bool EnumProc(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] public static extern IntPtr GetLastActivePopup(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h,int id);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc callback,IntPtr p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="SendMessageTimeoutW")] public static extern IntPtr SetText(IntPtr h,uint m,IntPtr w,string value,uint flags,uint timeout,out IntPtr result);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="SendMessageTimeoutW")] public static extern IntPtr GetText(IntPtr h,uint m,IntPtr w,StringBuilder value,uint flags,uint timeout,out IntPtr result);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 public static string Class(IntPtr h){var b=new StringBuilder(256);GetClassName(h,b,256);return b.ToString();}
 public static IntPtr[] Children(IntPtr h){var a=new List<IntPtr>();EnumChildWindows(h,(c,p)=>{a.Add(c);return true;},IntPtr.Zero);return a.ToArray();}
 public static IntPtr FilenameEdit(IntPtr dialog){
  var combo=GetDlgItem(dialog,1148);
  if(combo!=IntPtr.Zero){if(Class(combo)=="Edit")return combo;foreach(var h in Children(combo))if(Class(h)=="Edit")return h;}
  var edit=GetDlgItem(dialog,1152);
  if(edit!=IntPtr.Zero && Class(edit)=="Edit")return edit;
  foreach(var h in Children(dialog))if(Class(h)=="Edit" && GetDlgCtrlID(h)==1001 && Class(GetParent(h))=="ComboBox")return h;
  return IntPtr.Zero;
 }
}
'@
function Dialog-For-App {
 $h=[TVNativeDialog]::GetLastActivePopup($script:mainHandle)
 if($h -ne [IntPtr]::Zero -and $h -ne $script:mainHandle -and [TVNativeDialog]::Class($h) -eq '#32770'){
  return [System.Windows.Automation.AutomationElement]::FromHandle($h)
 }
 return $null
}
function Wait-Dialog {
 $deadline=[DateTime]::UtcNow.AddSeconds(15)
 do{$dialog=Dialog-For-App;if($dialog){return $dialog};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
 throw 'Native save dialog did not appear; no further export invoked'
}
function Native-Button($dialog,[string[]]$names){
 $h=[IntPtr]$dialog.Current.NativeWindowHandle
 $id=if('Save' -in $names -or 'Open' -in $names){1}else{2}
 $button=[TVNativeDialog]::GetDlgItem($h,$id)
 if($button -eq [IntPtr]::Zero -or ![TVNativeDialog]::IsWindowEnabled($button)){throw "Native dialog button unavailable: $id"}
 if(![TVNativeDialog]::PostMessage($h,0x111,[IntPtr]$id,$button)){throw 'Native button invocation failed'}
}
function Combo-Value($element){$element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value}
function Select-Combo([string]$name,[string]$label){
 Progress ('select: '+$name)
 $combo=Find-Control $name 'ComboBox'
 $value=$combo.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
 if($value.Current.Value -eq $label){return}
 if($value.Current.Value -ne $label){ # Use the real option action: ValuePattern.SetValue did not update the controlled select.
  $expand=$combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
  $expand.Expand()
  try{
   $conditions=New-Object System.Windows.Automation.AndCondition @(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$label)),
    (New-Object System.Windows.Automation.OrCondition @((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty,([int]$combo.Current.ProcessId))),(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty,([int]$p.Id)))))
   )
   $deadline=[DateTime]::UtcNow.AddSeconds(5)
   do{$option=$script:w.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$conditions)
    if(!$option){
     $roots=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
     foreach($own in $roots){if($own.Current.ProcessId -in @($p.Id,$combo.Current.ProcessId)){$option=$own.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$conditions);if($option){break}}}
    };if($option){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
   if(!$option){$report.comboLookupFailure=@{name=$name;comboPid=$combo.Current.ProcessId;appPid=$p.Id};throw "Exact option unavailable for $name; no keyboard fallback"}
   $report.selectedOptionType=$option.Current.ControlType.ProgrammaticName
   $report.selectedOptionPatterns=@($option.GetSupportedPatterns()|ForEach-Object {$_.ProgrammaticName})
   $pattern=$null
   if($option.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern,[ref]$pattern)){$pattern.Select()}
   elseif($option.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern,[ref]$pattern)){$pattern.Invoke()}
   else{throw "Exact option has no supported selection pattern for $name"}
  }finally{try{$expand.Collapse()}catch{}}
 }
 Start-Sleep -Milliseconds 300
 if((Combo-Value (Find-Control $name 'ComboBox')) -ne $label){throw "Combo selection not confirmed: $name"}
}
$originalLlmModel=$null;$originalModel=$null;$obsidianToggle=$null;$obsidianWasOn=$false;$player=$null
$store=Join-Path $env:APPDATA 'nl.prezent.transcript-studio/local-transcripts.json'
$recordings=Join-Path $env:LOCALAPPDATA 'nl.prezent.transcript-studio/Recordings'
$beforeFiles=if(Test-Path $recordings){@(Get-ChildItem $recordings -File | Select-Object -ExpandProperty FullName)}else{@()}
$beforeItems=if(Test-Path $store){(Get-Content $store -Raw -Encoding UTF8|ConvertFrom-Json).items}else{@()}
$beforeIds=@($beforeItems|ForEach-Object {$_.id})
$report.scope='Native selected-format import -> installed Parakeet CPU -> selected Ollama Cloud generator, source check and content audit; fixed fictional Dutch fixture only'
$report.humanListeningVerified=$false;$report.newBackupCreated=$false
try{
 $fixture=$ExpectedFixturePath
 if((Get-FileHash $fixture -Algorithm SHA256).Hash -ne $ExpectedFixtureSha256){throw 'Reference audio changed'}
 $model=Join-Path $env:APPDATA 'nl.prezent.transcript-studio/whisper-models/parakeet-tdt-0.6b-v3.q8_0.gguf'
 if((Get-FileHash $model -Algorithm SHA256).Hash -ne 'e3880d0aaaaf2c308ea2c35016b2b895c423eb3fda924c1b463d1c19b7f4d32e'){throw 'Existing Parakeet model missing/changed; no download'}
 $p=Start-Process $exe -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(30)
 do{Start-Sleep -Milliseconds 250;$p.Refresh()}while(!$p.MainWindowHandle -and [DateTime]::UtcNow -lt $deadline)
 $script:mainHandle=$p.MainWindowHandle
 $null=Find-Control 'Home' 'Hyperlink'
 Activate 'Instellingen' 'Hyperlink';Activate 'Verwerking' 'Button'
 $originalModel=Combo-Value (Find-Control 'Transcriptiemodel' 'ComboBox')
 $report.originalModel=$originalModel
 $originalLlmModel=Combo-Value (Find-Control 'Ollama model' 'ComboBox')
 $report.originalLlmModel=$originalLlmModel
 $approvedUrl=$false
 foreach($e in $script:w.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)){
  if($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Edit' -and !$e.Current.IsPassword){
   $v=$null;if($e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$v)){
    if($v.Current.Value -in @('https://ollama.com','https://ollama.com/','https://ollama.com/v1')){$approvedUrl=$true}
   }
  }
 }
 if(!$approvedUrl){throw 'Approved Ollama Cloud endpoint not confirmed; no provider request'}
 Select-Combo 'Ollama model' $ExpectedLlmModel
 $report.verifiedLlmModel=$ExpectedLlmModel
 Select-Combo 'Transcriptiemodel' 'Parakeet TDT v3: lokaal op CPU (~714 MB)'
 $readyDeadline=[DateTime]::UtcNow.AddSeconds(15)
 do{
  $ready=$script:w.FindFirst([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,'Model gedownload en klaar voor gebruik')))
  if($ready){break};Start-Sleep -Milliseconds 200
 }while([DateTime]::UtcNow -lt $readyDeadline)
 if(!$ready){throw 'Model readiness not confirmed; no capture or download'}
 Activate 'Obsidian' 'Button'
 $toggles=@()
 foreach($e in $script:w.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)){
  $toggle=$null;if($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern,[ref]$toggle)){$toggles+=@{element=$e;pattern=$toggle}}
 }
 if($toggles.Count -ne 1){throw 'Automatic export switch not uniquely identified; no capture'}
 $obsidianToggle=$toggles[0].pattern
 $obsidianWasOn=$obsidianToggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On
 if($obsidianWasOn){$obsidianToggle.Toggle();if($obsidianToggle.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::Off){throw 'Automatic export not disabled'}}
 Activate 'Opnemen' 'Hyperlink'
 $null=Find-Control 'Parakeet op deze pc' 'Text'
 Progress 'open import dialog'
 $importControl=Find-Control 'Audiobestand importeren' 'Button'
 $importPattern=$importControl.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
 $invoker=[PowerShell]::Create()
 $null=$invoker.AddScript('param($pattern) $pattern.Invoke()').AddArgument($importPattern)
 $invokeResult=$invoker.BeginInvoke()
 Progress 'wait import dialog'
 $dialog=Wait-Dialog
 $h=[IntPtr]$dialog.Current.NativeWindowHandle
 $edit=[TVNativeDialog]::FilenameEdit($h)
 if($edit -eq [IntPtr]::Zero){throw 'Native import filename control unavailable; no blind typing'}
 $inputPath=$fixture.Replace('/','\')
 $report.selectedFixturePath=$inputPath
 Progress 'set import filename'
 $messageResult=[IntPtr]::Zero
 if([TVNativeDialog]::SetText($edit,0xC,[IntPtr]::Zero,$inputPath,2,3000,[ref]$messageResult) -eq [IntPtr]::Zero){throw 'Native import filename setting failed'}
 $readback=New-Object Text.StringBuilder 4096
 $null=[TVNativeDialog]::GetText($edit,0xD,[IntPtr]4096,$readback,2,3000,[ref]$messageResult)
 if($readback.ToString() -cne $inputPath){throw 'Native import filename readback differs'}
 Progress 'submit import dialog'
 Native-Button $dialog @('Open')
 Start-Sleep -Milliseconds 750
 $still=Dialog-For-App
 if($still -and [TVNativeDialog]::IsWindowVisible([IntPtr]$still.Current.NativeWindowHandle)){
  $fileName=[IO.Path]::GetFileName($inputPath)
  $match=New-Object System.Windows.Automation.AndCondition @((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$fileName)),(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))
  $item=$still.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$match)
  if(!$item){throw 'File dialog remained and exact fixture item is unavailable; no blind second open'}
  $selection=$null
  if(!$item.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern,[ref]$selection)){throw 'Exact fixture item has no supported selection pattern'}
  $selection.Select()
  $report.exactFileSelected=$selection.Current.IsSelected
  if(!$report.exactFileSelected){throw 'Exact fixture selection not confirmed'}
  Native-Button $still @('Open')
 }
 if(!$invokeResult.AsyncWaitHandle.WaitOne(15000)){throw 'Import button invocation did not return after file selection'}
 $null=$invoker.EndInvoke($invokeResult)
 if($invoker.HadErrors){throw 'Asynchronous import button invocation failed'}
 $invoker.Dispose();$invoker=$null
 $closeDeadline=[DateTime]::UtcNow.AddSeconds(10)
 while((Dialog-For-App) -and [DateTime]::UtcNow -lt $closeDeadline){Start-Sleep -Milliseconds 100}
 $remaining=Dialog-For-App
 if($remaining){
  $remainingHandle=[IntPtr]$remaining.Current.NativeWindowHandle
  $report.remainingDialog=@{name=$remaining.Current.Name;visible=[TVNativeDialog]::IsWindowVisible($remainingHandle);offscreen=$remaining.Current.IsOffscreen;enabled=$remaining.Current.IsEnabled;controls=@($remaining.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)|ForEach-Object {@{name=$_.Current.Name;type=$_.Current.ControlType.ProgrammaticName;id=$_.Current.AutomationId}})}
  if([TVNativeDialog]::IsWindowVisible($remainingHandle)){try{Native-Button $remaining @('Cancel')}catch{};throw 'Visible import dialog remained after verified filename submission; dialog evidence preserved'}
 }
 Progress 'waiting for pipeline result'
 $report.importedFixture=$fixture
 $report.processingStarted=[DateTime]::UtcNow.ToString('o')
 $startDeadline=[DateTime]::UtcNow.AddSeconds(60)
 $deadline=[DateTime]::UtcNow.AddMinutes(15);$result=$null
 do{
  try{$items=(Get-Content $store -Raw -Encoding UTF8|ConvertFrom-Json).items}catch{Start-Sleep -Seconds 1;continue}
  $visibleErrors=@()
  foreach($t in $script:w.FindAll([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text)))){
   if($t.Current.Name -match '^(Kan audio|Audiobestand|Audioformaat|Audio-import|Geen audiospoor|Niet-ondersteund|Importeren mislukt|Kan bestand)'){$visibleErrors+=$t.Current.Name}
  }
  if($visibleErrors.Count){$report.visibleImportErrors=$visibleErrors;throw 'Native UI reported audio import error; exact messages preserved'}
  $new=@($items|Where-Object {$_.id -notin $beforeIds})
  if(!$new.Count -and [DateTime]::UtcNow -gt $startDeadline -and !(Get-Process nemo-speech -ErrorAction SilentlyContinue)){throw 'Import produced no record or transcription worker within60 seconds'}
  if($new.Count -gt 1){throw 'More than one new record; no unrelated data changed by test'}
  if($new.Count -eq 1 -and ($new[0].has_notes -or $new[0].notule_review_reason)){$result=$new[0];break}
  Start-Sleep -Seconds 1
 }while([DateTime]::UtcNow -lt $deadline)
 if(!$result){throw 'Pipeline did not produce an accepted note or review result within timeout'}
 $report.recordId=$result.id
 $result|ConvertTo-Json -Depth 15|Set-Content -Encoding UTF8 (Join-Path $env:DALF_ARTIFACT_DIR 'fictional-pipeline-record.json')
 $files=@(Get-ChildItem $recordings -File | Where-Object {$_.FullName -notin $beforeFiles -and $_.Extension -eq '.wav'})
 $report.recordings=@($files|ForEach-Object {@{path=$_.FullName;length=$_.Length;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
 if($files.Count -ne 1){throw 'Expected exactly one normalized imported recording'}
 $afterOriginals=@($items|Where-Object {$_.id -in $beforeIds})
 $report.originalRecordsUnchanged=($beforeItems|ConvertTo-Json -Depth 30 -Compress) -ceq ($afterOriginals|ConvertTo-Json -Depth 30 -Compress)
 if(!$report.originalRecordsUnchanged){throw 'An original record changed'}
 if(!$result.has_notes){throw 'Production content audit rejected the draft; preserved without retry'}
 $report.status='native_pipeline_completed_requires_independent_content_review'
 $report.pipelineStage=$report.stage
}catch{$report.error=$_.Exception.Message;$report.errorLocation=$_.ScriptStackTrace;$report.failureStage=$report.stage}finally{
 $pipelineStage=$report.stage
 if($player){$player.Stop();$player.Dispose()}
 try{
  if($originalModel){Activate 'Instellingen' 'Hyperlink';Activate 'Verwerking' 'Button';Select-Combo 'Transcriptiemodel' $originalModel;$report.originalModelRestored=$true}
  if($originalLlmModel){Select-Combo 'Ollama model' $originalLlmModel;$report.originalLlmModelRestored=$true}
  if($obsidianWasOn){Activate 'Obsidian' 'Button';$ts=@();foreach($e in $script:w.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)){$t=$null;if($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern,[ref]$t)){$ts+=$t}};if($ts.Count -ne 1){throw 'Cannot restore original automatic export switch'};if($ts[0].Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On){$ts[0].Toggle()};$report.obsidianRestored=$ts[0].Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On}
 }catch{$report.settingsRestoreError=$_.Exception.Message}
 $report.cleanupStage=$report.stage;$report.stage=$pipelineStage
 $report.finished=[DateTime]::UtcNow.ToString('o')
 $report|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $env:DALF_ARTIFACT_DIR 'native-short-pipeline-result.json')
 try{$root=[System.Windows.Automation.AutomationElement]::FromHandle($script:mainHandle);$root.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close();$null=$p.WaitForExit(10000)}catch{}
}
if($report.status -ne 'native_pipeline_completed_requires_independent_content_review' -or $report.settingsRestoreError){exit 1}
