@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',      # scripts are interactive CLI/CI tools; Write-Host output is intended
        'PSUseSingularNouns',         # Get-DataverseRecords etc. mirror Dataverse terminology
        'PSReviewUnusedParameter'     # false positives for parameters used in nested functions
    )
}
