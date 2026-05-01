#################################################
# HelloID-Conn-Prov-Target-IrisIntranet-Enable
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-IrisIntranetError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = $errorDetailsObject # Temporarily assignment
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            Write-Warning $_.Exception.Message
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.ApiToken)")

    Write-Information 'Verifying if a IrisIntranet account exists'
    $splatGetUser = @{
        Uri         = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)"
        Method      = 'GET'
        Headers     = $headers
        ContentType = 'application/json'
    }
    $correlatedAccount = Invoke-RestMethod @splatGetUser

    if ($null -ne $correlatedAccount) {
        $lifecycleProcess = 'EnableAccount'
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'EnableAccount' {
            [System.Collections.Generic.List[object]]$operations = @()

            $operations.Add(
                [PSCustomObject]@{
                    op    = "Replace"
                    path  = "active"
                    value = $true
                }
            )

            $body = [ordered]@{
                schemas    = @(
                    "urn:ietf:params:scim:api:messages:2.0:PatchOp"
                )
                Operations = $operations
            } | ConvertTo-Json

            $splatEnableParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/iris/v1/$($actionContext.Configuration.ApiID)/scim/Users"
                Headers = $headers
                Body    = $body
                Method  = 'Patch'
            }
            
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Enabling IrisIntranet account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatEnableParams
            }
            else {
                Write-Information "[DryRun] Enable IrisIntranet account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Enable account was successful'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "IrisIntranet account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "IrisIntranet account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }

} 
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IrisIntranetError -ErrorObject $ex
        $auditLogMessage = "Could not enable IrisIntranet account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not enable IrisIntranet account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}