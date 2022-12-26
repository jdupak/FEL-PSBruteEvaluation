@{
	RootModule = 'BRUTE_Evaluation.psm1'
	ModuleVersion = '0.1'
	GUID = '7d1db95e-bf17-449c-9770-716d72555afe'
	Author = 'Matej Kafka'

	FunctionsToExport = @('Set-BruteEvaluationContext', 'Show-BruteCourseTable', 'Show-BruteEvaluation', 'Start-BruteEvaluation', 'Stop-BruteEvaluation', 'Get-BruteEvaluationInformation')
	CmdletsToExport = @()
	VariablesToExport = @()
	AliasesToExport = @('brutet', 'bruteg', 'brutes', 'brutee')
}

