using module BRUTE

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# info about the last created evaluation directory
$script:LastEval = $null

# set by Set-BruteEvaluationContext
[BruteEvaluationContext]$script:EVAL_CONTEXT = $null

function Get-Context {
    if (-not $script:EVAL_CONTEXT) {
        throw "Configure the evaluation parameters using 'Set-BruteEvaluationContext' before calling other functions."
    }
    return $script:EVAL_CONTEXT
}


class BruteEvaluationContext {
    [string]$CourseUrl
    [string[]]$ParallelNames

    [scriptblock]$SetContextHookAfterSb
    [scriptblock]$GetEvaluationDirectoryPathSb
    [scriptblock]$StartHookAfterSb
    [scriptblock]$GenerateManualEvaluationSb
    [scriptblock]$PublishHookBeforeSb
    [scriptblock]$PublishHookAfterSb

    [BruteCourseTable]$Table
    [BruteParallel[]]$Parallels

    BruteEvaluationContext([string]$CourseUrl,
        [string[]]$ParallelNames,
        [scriptblock]$SetContextHookAfterSb,
        [scriptblock]$GetEvaluationDirectoryPathSb,
        [scriptblock]$StartHookAfterSb,
        [scriptblock]$GenerateManualEvaluationSb,
        [scriptblock]$PublishHookBeforeSb,
        [scriptblock]$PublishHookAfterSb) {
        $this.CourseUrl = $CourseUrl
        $this.ParallelNames = $ParallelNames
        $this.SetContextHookAfterSb = $SetContextHookAfterSb
        $this.GetEvaluationDirectoryPathSb = $GetEvaluationDirectoryPathSb
        $this.StartHookAfterSb = $StartHookAfterSb
        $this.GenerateManualEvaluationSb = $GenerateManualEvaluationSb
        $this.PublishHookBeforeSb = $PublishHookBeforeSb
        $this.PublishHookAfterSb = $PublishHookAfterSb

        $this.Refresh()
    }

    Refresh() {
        $this.Table = Get-BruteCourseTable $this.CourseUrl
        $this.Parallels = foreach ($pn in $this.ParallelNames) { $this.Table.GetParallel($pn) }
    }

    RenderTable() {
        foreach ($p in $this.Parallels) {
            if (@($this.Parallels).Count -gt 1) {
                Write-Host "`nPARALLEL '$($p.Name)':"
            }
            $p.FormatTable() | Out-Host
        }
    }

    [BruteEvaluation]
    GetEvaluation([string]$AssignmentName,
        [string]$UserName) {
        $Student = foreach ($p in $this.Parallels) {
            try { $p.GetStudent($UserName); break } catch {}
        }
        if (-not $Student) {
            throw "Student '$UserName' not found in parallels " + (($this.Parallels | % { "'" + $_.Name + "'" }) -join ", ") + "."
        }

        $Url = $Student.GetSubmissionURL($AssignmentName)
        if (-not $Url) {
            throw "Student '$UserName' did not submit anything yet."
        }
        return Get-BruteEvaluation $Url
    }

    [string]
    GetEvaluationDirectory([string]$AssignmentName,
        [string]$UserName) {
        return $this.GetEvaluationDirectoryPathSb.Invoke($AssignmentName, $UserName)
    }
}

class _AssignmentName:System.Management.Automation.IValidateSetValuesGenerator {
    [string[]]
    GetValidValues() {
        return (Get-Context).Parallels.GetAssignmentNames()
    }
}

class _StudentName:System.Management.Automation.IValidateSetValuesGenerator {
    [string[]]
    GetValidValues() {
        return (Get-Context).Parallels.GetStudents() | % UserName
    }
}

function Set-BruteEvaluationContext([string]$CourseUrl,
    [string[]]$ParallelNames,
    [scriptblock]$SetContextHookAfterSb,
    [scriptblock]$GetEvaluationDirectoryPathSb,
    [scriptblock]$StartHookAfterSb,
    [scriptblock]$GenerateManualEvaluationSb,
    [scriptblock]$PublishHookBeforeSb,
    [scriptblock]$PublishHookAfterSb) {

    $script:EVAL_CONTEXT = [BruteEvaluationContext]::new($CourseUrl, $ParallelNames, $SetContextHookAfterSb, $GetEvaluationDirectoryPathSb, $StartHookAfterSb, $GenerateManualEvaluationSb, $PublishHookBeforeSb, $PublishHookAfterSb)

    $script:EVAL_CONTEXT.SetContextHookAfterSb.Invoke()

}

function Get-MandatoryConfigOption([hashtable]$Config,
    [string]$Name) {
    if (-not $Config.ContainsKey($Name)) {
        throw "Config file does not contain mandatory option '$Name'."
    }
    # if scriptblock
    if ($Config[$Name].GetType() -eq [ScriptBlock]) {
        return (& $Config[$Name])
    }
    return $Config[$Name]
}

function Import-BruteEvaluationConfig {
    param(
        [string]$Path = "."
    )

    if (-not (Test-Path $Path)) {
        throw "Path '$Path' does not exist."
    }

    if (Test-Path $Path -PathType Leaf) {
        $ConfigPath = $Path
    }
    else {
        $ConfigPath = Get-Item (Join-Path $Path "BruteEvaluationConfig.psd1")
    }

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file does not exist"
    }

    $Config = Import-PowerShellDataFile $ConfigPath

    $CourseUrl = Get-MandatoryConfigOption $Config "CourseUrl"
    $ParallelNames = Get-MandatoryConfigOption $Config "ParallelNames"
    $SetContextHookAfterSb = Get-MandatoryConfigOption $Config "SetContextHookAfterSb"
    $GetEvaluationDirectoryPathSb = Get-MandatoryConfigOption $Config "GetEvaluationDirectoryPathSb"
    $StartHookAfterSb = Get-MandatoryConfigOption $Config "StartHookAfterSb"
    $GenerateManualEvaluationSb = Get-MandatoryConfigOption $Config "GenerateManualEvaluationSb"
    $PublishHookBeforeSb = Get-MandatoryConfigOption $Config "PublishHookBeforeSb"
    $PublishHookAfterSb = Get-MandatoryConfigOption $Config "PublishHookAfterSb"

    Set-BruteEvaluationContext $CourseUrl $ParallelNames $SetContextHookAfterSb $GetEvaluationDirectoryPathSb $StartHookAfterSb $GenerateManualEvaluationSb $PublishHookBeforeSb $PublishHookAfterSb
}


function Get-BruteEvaluationInformation {
    if (-not $script:LastEval) {
        throw "No active evaluation."
    }
    return $script:LastEval
}

function Show-BruteCourseTable {
    [CmdletBinding()]
    param(
        [switch]$NoRefresh
    )

    $Context = Get-Context
    if (-not $NoRefresh) {
        $Context.Refresh()
    }
    $Context.RenderTable()
}

function Show-BruteEvaluationInternal {
    param(
        [BruteEvaluation]$Evaluation
    )

    $p = $Evaluation.Parameters
    Write-Host "AE URL: $($PSStyle.FormatHyperlink($Evaluation.AeOutputUrl, $Evaluation.AeOutputUrl))"
    Write-Host "Evaluation URL: $($PSStyle.FormatHyperlink($Evaluation.SubmissionUrl, $Evaluation.SubmissionUrl))"
    Write-Host ""
    if ($p.ae_score) { Write-Host "AE: $($p.ae_score)" }
    if ($p.penalty) { Write-Host "PENALTY: $($p.penalty)" }
    if ($p.manual_score) { Write-Host "MANUAL: $($p.manual_score)" }
    if ($p.evaluation) {
        Write-Host "EVALUATION:"
        Write-Host $p.evaluation
    }
}

function Show-BruteEvaluation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet([_AssignmentName])][string]$AssignmentName,
        [Parameter(Mandatory)][ValidateSet([_StudentName])][string]$UserName
    )

    $Context = Get-Context
    $Evaluation = $Context.GetEvaluation($AssignmentName, $UserName)
    Show-BruteEvaluationInternal $Evaluation
}

function Start-BruteEvaluation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet([_AssignmentName])][string]$AssignmentName,
        [Parameter(Mandatory)][ValidateSet([_StudentName])][string]$UserName
    )

    $Context = Get-Context
    $Evaluation = $Context.GetEvaluation($AssignmentName, $UserName)

    $Dir = $Context.GetEvaluationDirectory($AssignmentName, $UserName)
    if (Test-Path $Dir) {
        throw "Target directory '$Dir' already exists, is there an unfinished previous evaluation?"
    }

    Get-BruteUpload $Evaluation $Dir
    # this does not work, for some reason; it might be the same reason why you cannot view
    #  AE results of your assignment as a student when you're also logged in as a teacher
    #Get-BruteAeOutput $Evaluation (Join-Path $Target "__AE_RESULT.html")

    # TODO: add AssignmentName to BruteEvaluation
    $script:LastEval = @{
        Directory      = $Dir
        AssignmentName = $AssignmentName
        StudentName    = $UserName
        Evaluation     = $Evaluation
    }

    $p = $Evaluation.Parameters
    Show-BruteEvaluationInternal $Evaluation

    Set-Content "$Dir/.BRUTE-URL.txt" -NoNewline -Value $Evaluation.Url

    $Context.StartHookAfterSb.Invoke($Dir)
}

function Publish-BruteEvaluation {
    [CmdletBinding()]
    param($Evaluation = $null,
        [Nullable[float]]$ManualScore = $null,
        [Nullable[float]]$Penalty = $null,
        $Note = $null,
        $Dir = "."
    )
    $Context = Get-Context

    $Context.PublishHookBeforeSb.Invoke($Dir)
    Publish-BruteEvaluationInternal $Evaluation $ManualScore $Penalty $Note $Dir
    $Context.PublishHookAfterSb.Invoke($Dir)
}

function Publish-BruteEvaluationInternal {
    [CmdletBinding()]
    param($Evaluation = $null,
        [Nullable[float]]$ManualScore = $null,
        [Nullable[float]]$Penalty = $null,
        $Note = $null,
        $Dir = "."
    )

    begin {
        $Url = try {
            Get-Content "$Dir/.BRUTE-URL.txt"
        }
        catch {
            throw "This is not a valid evauation dir. `".BRUTE-URL.txt`" is missing."
        }

        if (-not $Evaluation -and -not $Note -and -not $ManualScore -and -not $Penalty) {
            Write-Host "No evaluation provided. Aborting publishing."
            return # do not submit, no arguments explicitly passed
        }
        else {
            New-BruteEvaluation $Url -Evaluation $Evaluation -Note $Note -ManualScore $ManualScore -Penalty $Penalty
            $Eval = Get-BruteEvaluation $Url
            Show-BruteEvaluationInternal $Eval
        }

    }
}

<#
.SYNOPSIS
Publishes evaluation taking data from files in $Dir instead of from parameters.
This is useful when the data are generated by another tool.
#>
function Publish-BruteEvaluationFromFiles {
    [CmdletBinding()]
    param($EvaluationFile = "eval.txt",
        $ManualScoreFile = "manual-score.txt",
        $PenaltyFile = "penalty.txt",
        $NoteFile = "note.txt",
        $Dir = "."
    )

    $Context = Get-Context
    $Context.PublishHookBeforeSb.Invoke($Dir)

    $Evaluation = try {
        Get-Content "$Dir/$EvaluationFile" -Encoding UTF8 -Raw
    }
    catch {
        $null
    }
    $ManualScore = try {
        [float](Get-Content "$Dir/$ManualScoreFile")
    }
    catch {
        $null
    }
    $Penalty = try {
        [float](Get-Content "$Dir/$PenaltyFile")
    }
    catch {
        $null
    }
    $Note = try {
        Get-Content "$Dir/$NoteFile"
    }
    catch {
        $null
    }

    Publish-BruteEvaluationInternal $Evaluation $ManualScore $Penalty $Note $Dir
    $Context.PublishHookAfterSb.Invoke($Dir)

}

function Stop-BruteEvaluation {
    [CmdletBinding()]
    param($Evaluation = $null,
        [Nullable[float]]$ManualScore = $null,
        [Nullable[float]]$Penalty = $null,
        $Note = $null,
        $Dir = $null
    )

    begin {
        $UsingLastEval = -not $Dir
        if (-not $Dir) {
            if ($script:LastEval) {
                $Dir = $script:LastEval.Directory
            }
            else {
                throw "No evaluation directory set."
            }
        }

        Publish-BruteEvaluation $Evaluation $ManualScore $Penalty $Note $Dir

        rm -Recurse $Dir
        rm "$Dir/.BRUTE-URL.txt"
        $script:LastEval = $null
    }
}

New-Alias brutet Show-BruteCourseTable
New-Alias bruteg Show-BruteEvaluation
New-Alias brutes Start-BruteEvaluation
New-Alias brutee Stop-BruteEvaluation
