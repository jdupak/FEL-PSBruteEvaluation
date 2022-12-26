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
    [scriptblock]$EvalDirPathSb
    [scriptblock]$OpenEvalDirSb

    [BruteCourseTable]$Table
    [BruteParallel[]]$Parallels

    BruteEvaluationContext([string]$CourseUrl, [string[]]$ParallelNames,
            [scriptblock]$GetEvaluationDirectoryPathSb, [scriptblock]$OpenEvaluationDirectorySb) {
        $this.CourseUrl = $CourseUrl
        $this.ParallelNames = $ParallelNames
        $this.EvalDirPathSb = $GetEvaluationDirectoryPathSb
        $this.OpenEvalDirSb = $OpenEvaluationDirectorySb

        $this.Refresh()
    }

    Refresh() {
        $this.Table = Get-BruteCourseTable $this.CourseUrl
        $this.Parallels = foreach ($pn in $this.ParallelNames) {$this.Table.GetParallel($pn)}
    }

    RenderTable() {
        foreach ($p in $this.Parallels) {
            if (@($this.Parallels).Count -gt 1) {
                Write-Host "`nPARALLEL '$($p.Name)':"
            }
            $p.FormatTable() | Out-Host
        }
    }

    [BruteEvaluation] GetEvaluation([string]$AssignmentName, [string]$UserName) {
        $Student = foreach ($p in $this.Parallels) {
            try {$p.GetStudent($UserName); break} catch {}
        }
        if (-not $Student) {
            throw "Student '$UserName' not found in parallels " + (($this.Parallels | % {"'" + $_.Name + "'"}) -join ", ")  + "."
        }

        $Url = $Student.GetSubmissionURL($AssignmentName)
        if (-not $Url) {
            throw "Student '$UserName' did not submit anything yet."
        }
        return Get-BruteEvaluation $Url
    }

    [string] GetEvaluationDirectory([string]$AssignmentName, [string]$UserName) {
        return & $this.EvalDirPathSb $AssignmentName $UserName
    }

    OpenEvaluationDirectory([string]$Path) {
        & $this.OpenEvalDirSb $Path
    }
}

class _AssignmentName : System.Management.Automation.IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return (Get-Context).Parallels.GetAssignmentNames()
    }
}

class _StudentName : System.Management.Automation.IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return (Get-Context).Parallels.GetStudents() | % UserName
    }
}


function Set-BruteEvaluationContext($CourseUrl, $ParallelNames, $GetEvaluationDirectoryPathSb, $OpenEvaluationDirectorySb) {
    $script:EVAL_CONTEXT = [BruteEvaluationContext]::new($CourseUrl, $ParallelNames, $GetEvaluationDirectoryPathSb, $OpenEvaluationDirectorySb)
}

function Get-BruteEvaluationInformation {
    if (-not $script:LastEval) {
        throw "No active evaluation."
    }
    return $script:LastEval
}

function Show-BruteCourseTable {
    [CmdletBinding()]
    param([switch]$NoRefresh)

    $Context = Get-Context
    if (-not $NoRefresh) {
        $Context.Refresh()
    }
    $Context.RenderTable()
}

function Show-BruteEvaluation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet([_AssignmentName])][string]$AssignmentName,
        [Parameter(Mandatory)][ValidateSet([_StudentName])][string]$UserName
    )
    
    $Context = Get-Context
    $Evaluation = $Context.GetEvaluation($AssignmentName, $UserName)
    $p = $Evaluation.Parameters
    Write-Host "AE URL: $($PSStyle.FormatHyperlink($Evaluation.AeOutputUrl, $Evaluation.AeOutputUrl))"
    Write-Host "Evaluation URL: $($PSStyle.FormatHyperlink($Evaluation.SubmissionUrl, $Evaluation.SubmissionUrl))"
    Write-Host ""
    Write-Host "USERNAME: $UserName"
    if ($p.ae_score) {Write-Host "AE: $($p.ae_score)"}
    if ($p.penalty) {Write-Host "PENALTY: $($p.penalty)"}
    if ($p.manual_score) {Write-Host "MANUAL: $($p.manual_score)"}
    if ($p.evaluation) {
        Write-Host "EVALUATION:"
        Write-Host $p.evaluation
    }
}

function Start-BruteEvaluation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet([_AssignmentName])][string]$AssignmentName,
        [Parameter(Mandatory)][ValidateSet([_StudentName])][string]$UserName
    )
    
    $Context = Get-Context
    $Evaluation = $Context.GetEvaluation($AssignmentName, $UserName)
    
    $Target = $Context.GetEvaluationDirectory($AssignmentName, $UserName)
    if (Test-Path $Target) {
        throw "Target directory '$Target' already exists, is there an unfinished previous evaluation?"
    }

    Get-BruteUpload $Evaluation $Target
    # this does not work, for some reason; it might be the same reason why you cannot view
    #  AE results of your assignment as a student when you're also logged in as a teacher
    #Get-BruteAeOutput $Evaluation (Join-Path $Target "__AE_RESULT.html")
    
    # TODO: add AssignmentName to BruteEvaluation
    $script:LastEval = @{
        Directory = $Target
        AssignmentName = $AssignmentName
        StudentName = $UserName
        Evaluation = $Evaluation
    }

    $p = $Evaluation.Parameters
    Write-Host "AE URL: $($PSStyle.FormatHyperlink($Evaluation.AeOutputUrl, $Evaluation.AeOutputUrl))"
    Write-Host "Evaluation URL: $($PSStyle.FormatHyperlink($Evaluation.SubmissionUrl, $Evaluation.SubmissionUrl))"
    Write-Host ""
    Write-Host "USERNAME: $UserName"
    if ($p.ae_score) {Write-Host "AE: $($p.ae_score)"}
    if ($p.penalty) {Write-Host "PENALTY: $($p.penalty)"}
    if ($p.manual_score) {Write-Host "MANUAL: $($p.manual_score)"}

    Set-Content "${Target}-URL.txt" -NoNewline -Value $Evaluation.Url

    $Context.OpenEvaluationDirectory($Target)
}

function Stop-BruteEvaluation {
    [CmdletBinding()]
    param(
        $Evaluation = $null,
        [Nullable[float]]$ManualScore = $null,
        [Nullable[float]]$Penalty = $null,
        $Note = $null,
        $Dir = $null
    )

    begin {
        $UsingLastEval = -not $Dir
        if (-not $Dir) {
            if ($script:LastEval) {$Dir = $script:LastEval.Directory}
            else {throw "No evaluation directory set."}
        }

        $Url = cat "$Dir-URL.txt"
        if (-not $Evaluation -and -not $Note -and -not $ManualScore -and -not $Penalty) {
            Write-Host "No evaluation submitted, deleting assignment directory..."
        } else {
            $Arg1 = if ($UsingLastEval) {$script:LastEval.Evaluation} else {$Url}
            New-BruteEvaluation $Arg1 -Evaluation $Evaluation -Note $Note -ManualScore $ManualScore -Penalty $Penalty
        }

        rm -Recurse $Dir
        rm "$Dir-URL.txt"
        $script:LastEval = $null
    }
}

New-Alias brutet Show-BruteCourseTable
New-Alias bruteg Show-BruteEvaluation
New-Alias brutes Start-BruteEvaluation
New-Alias brutee Stop-BruteEvaluation
