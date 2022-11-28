using module BRUTE

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


#############################################################################
# set these values manually:
$script:COURSE_URL = "https://cw.felk.cvut.cz/brute/teacher/course/<...>/<...>"
$script:PARALLEL_NAMES = @("parallel-name")
# this function should open your preferred file manager / IDE
function OpenDirectory($Dir) {explorer $Dir}
#############################################################################


$script:TABLE = while ($true) {
    try {
        Get-BruteCourseTable $script:COURSE_URL
        break
    } catch [InvalidBruteSSOTokenException] {
        Write-Host ($PSStyle.Foreground.BrightRed + $_ + $PSStyle.Reset)
        Set-BruteSSOToken (Read-Host "Enter a new SSO token" -MaskInput)
    }
}
$script:PARALLELS = $script:PARALLEL_NAMES | % {$script:TABLE.GetParallel($_)}


# render the AE tables
foreach ($p in $script:PARALLELS) {
    if (@($script:PARALLELS).Count -gt 1) {
        Write-Host "PARALLEL '$($p.Name)':"
    }
    $p.FormatTable() | Out-Host
}


# path to the last created evaluation directory
$script:LastEvalDir = $null


class _AssignmentName : System.Management.Automation.IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return $script:PARALLELS.GetAssignmentNames()
    }
}

class _StudentName : System.Management.Automation.IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return $script:PARALLELS.GetStudents() | % UserName
    }
}


function New-TemporaryPath($Extension = "", $Prefix = "") {
    $Tmp = if ($IsWindows) {$env:TEMP} else {"/tmp"}
    return Join-Path $Tmp "$Prefix$(New-Guid)$Extension"
}


function Get-BruteEvaluationDir {
    return $script:LastEvalDir
}

function Start-BruteEvaluation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet([_AssignmentName])][string]$AssignmentName,
        [Parameter(Mandatory)][ValidateSet([_StudentName])][string]$UserName
    )
    
    $Student = foreach ($p in $script:PARALLELS) {
        try {$p.GetStudent($UserName); break} catch {}
    }
    if (-not $Student) {
        throw "Student '$UserName' not found in parallels " + (($script:PARALLELS | % {"'" + $_.Name + "'"}) -join ", ")  + "."
    }

    $Url = $Student.GetSubmissionURL($AssignmentName)
    if (-not $Url) {
        throw "Student '$UserName' did not submit anything yet."
    }
    $Evaluation = Get-BruteEvaluation $Url

    $Target = New-TemporaryPath -Prefix "BRUTE-$AssignmentName-$UserName-"
    Get-BruteUpload $Evaluation $Target
    # this does not work, for some reason; it might be the same reason why you cannot view
    #  AE results of your assignment as a student when you're also logged in as a teacher
    #Get-BruteAeOutput $Evaluation (Join-Path $Target "__AE_RESULT.html")
    $script:LastEvalDir = $Target

    $p = $Evaluation.Parameters
    Write-Host "USERNAME: $UserName"
    if ($p.ae_score) {Write-Host "AE: $($p.ae_score)"}
    if ($p.penalty) {Write-Host "PENALTY: $($p.penalty)"}
    if ($p.manual_score) {Write-Host "MANUAL: $($p.manual_score)"}
    Write-Host "AE URL: $($PSStyle.FormatHyperlink($Evaluation.AeOutputUrl, $Evaluation.AeOutputUrl))"

    Set-Content "${Target}-URL.txt" -NoNewline -Value $Evaluation.Url

    pause
    OpenDirectory $Target
}

function Stop-BruteEvaluation {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Evaluation = $null,
        [Nullable[float]]$ManualScore = $null,
        [Nullable[float]]$Penalty = $null,
        [AllowNull()][string]$Note = $null,
        [string]$Dir = $script:LastEvalDir
    )

    begin {
        if (-not $Dir) {
            throw "No evaluation directory set."
        }

        $Url = cat "$Dir-URL.txt"
        rm "$Dir-URL.txt"
        rm -Recurse $Dir
        $script:LastEvalDir = $null

        if (-not $Evaluation -and -not $Note -and -not $ManualScore -and -not $Penalty) {
            Write-Host "Assignment directory deleted, no evaluation submitted."
            return # do not submit, no arguments explicitly passed
        } else {
            New-BruteEvaluation $Url -Evaluation $Evaluation -Note $Note -ManualScore $ManualScore -Penalty $Penalty
        }
    }
}

New-Alias brutes Start-BruteEvaluation
New-Alias brutee Stop-BruteEvaluation
