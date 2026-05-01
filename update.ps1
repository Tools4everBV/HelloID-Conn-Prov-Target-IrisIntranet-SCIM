#################################################
# HelloID-Conn-Prov-Target-IrisIntranet-Update
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

function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $AccountObject
    )
    process {

        # Making sure only fieldMapping fields are imported
        $helloidAccountObject = [PSCustomObject]@{}
        foreach ($property in $actionContext.Data.PSObject.Properties) {
            switch ($property.Name) {
                'EmailAddress'      { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.emails.value }
                'IsEmailPrimary'    { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue "$($AccountObject.emails.primary)" }
                'EmailAddressType'  { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.emails.type }
                'Username'          { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.userName }
                'ExternalId'        { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.externalId }
                'GivenName'         { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.givenName }
                'NameFormatted'     { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.formatted }
                'FamilyName'        { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.familyName }
                'FamilyNamePrefix'  { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.familyNamePrefix }
                'IsEnabled'         { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.active }
                default             { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.$($property.Name) }
            }
        }
        Write-Output $helloidAccountObject
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
    $targetAccount = Invoke-RestMethod @splatGetUser


    if ($null -ne $targetAccount) {
        # Always compare the account against the current account in target system
        $correlatedAccount = ConvertTo-HelloIDCompareAccountObject($targetAccount)

        $outputContext.PreviousData = $correlatedAccount

        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $lifecycleProcess = 'UpdateAccount'
        }
        else {
            $lifecycleProcess = 'NoChanges'
        }
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"

            [System.Collections.Generic.List[object]]$operations = @()
            foreach ($property in $propertiesChanged) {
                switch ($property.Name) {
                    'ExternalId' {
                        $operations.Add(
                            [PSCustomObject]@{
                                op    = 'Replace'
                                path  = 'externalId'
                                value = $property.Value
                            }
                        )
                    }
                    'Username' {
                        $operations.Add(
                            [PSCustomObject]@{
                                op    = 'Replace'
                                path  = 'userName'
                                value = $property.Value
                            }
                        )
                    }
                    'GivenName' {
                        $operations.Add(
                            [PSCustomObject]@{
                                op    = 'Replace'
                                path  = 'name.givenName'
                                value = $property.Value
                            }
                        )
                    }
                    'FamilyName' {
                        $operations.Add(
                            [PSCustomObject]@{
                                op    = 'Replace'
                                path  = 'name.familyName'
                                value = $property.Value
                            }
                        )
                    }
                    'EmailAddress' {
                        $operations.Add(
                            [PSCustomObject]@{
                                op    = 'Replace'
                                path  = 'emails.value'
                                value = $property.Value
                            }
                        )
                    }
                }
            }

            $body = [ordered]@{
                schemas    = @(
                    "urn:ietf:params:scim:api:messages:2.0:PatchOp"
                )
                Operations = $operations
            } | ConvertTo-Json

            $splatUpdateParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/iris/v1/$($actionContext.Configuration.ApiID)/scim/Users"
                Headers = $headers
                Body    = $body
                Method  = 'Patch'
            }

            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating IrisIntranet account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatUpdateParams
            }
            else {
                Write-Information "[DryRun] Update IrisIntranet account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to IrisIntranet account with accountReference: [$($actionContext.References.Account)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating IrisIntranet account with AccountReference: [$($actionContext.References.Account)]. Reason: No changes."
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
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IrisIntranetError -ErrorObject $ex
        $auditLogMessage = "Could not update IrisIntranet account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not update IrisIntranet account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}