#################################################
# HelloID-Conn-Prov-Target-IrisIntranet-Create
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

function Invoke-ScimRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Microsoft.PowerShell.Commands.WebRequestMethod]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json',

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [string]
        $TotalResults
    )

    try {
        $splatParams = @{
            Uri         = "$($actionContext.configuration.BaseUrl)/$Uri"
            Headers     = $Headers
            Method      = $Method
            ContentType = $ContentType
        }

        if ($Body) {
            $splatParams['Body'] = $Body
        }

        if ($TotalResults) {
            # Fixed value since each page contains 20 items max
            $count = 20

            [System.Collections.Generic.List[object]]$dataList = @()
            do {
                $startIndex = $dataList.Count
                $splatParams['Uri'] = "$($actionContext.configuration.BaseUrl)/$($Uri)?startIndex=$startIndex&count=$count"
                $result = Invoke-RestMethod @splatParams
                foreach ($resource in $result.Resources) {
                    $dataList.Add($resource)
                }

            } until ($dataList.Count -eq $TotalResults)
            Write-Output $dataList
        }
        else {
            Invoke-RestMethod @splatParams
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.ApiToken)")

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        Write-Information 'Getting total number of users'
        $splatGetTotal = @{
            Uri     = 'Users'
            Method  = 'Get'
            Headers = $headers
        }
        $response = Invoke-ScimRestMethod @splatGetTotal
        $totalResults = $response.totalResults


        Write-Information "Retrieving '$totalResults' users"
        $splatGetUsers = @{
            Uri          = 'Users'
            Method       = 'GET'
            Headers      = $headers
            TotalResults = $totalResults
        }
        $responseAllUsers = Invoke-ScimRestMethod @splatGetUsers

        Write-Information "Verifying if a IrisIntranet account exists where $correlationField is: [$correlationValue]"
        $lookup = $responseAllUsers | Group-Object -Property $correlationField -AsHashTable

        if (-not $lookup.ContainsKey($correlationValue)) {
            $correlatedAccount = $null
        }
        else {
            $correlatedAccount = $lookup[$correlationValue]

            if ($correlatedAccount.Count -gt 1) {
                throw "Multiple accounts found for $correlationField = $correlationValue"
            }
        }
    }

    if ($null -ne $correlatedAccount) {
        $lifecycleProcess = 'CorrelateAccount'
    } else {
        $lifecycleProcess = 'CreateAccount'
    }

    # Process
    switch ($lifecycleProcess) {
        'CreateAccount' {
            [System.Collections.Generic.List[object]]$emailList = @()
            $emailList.Add(
                [PSCustomObject]@{
                    primary = $actionContext.Data.IsEmailPrimary
                    type    = $actionContext.Data.EmailAddressType
                    display = $actionContext.Data.EmailAddress
                    value   = $actionContext.Data.EmailAddress
                }
            )

            $body = [ordered]@{
                schemas    = @(
                    "urn:ietf:params:scim:schemas:core:2.0:User",
                    "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"
                )
                externalId = $actionContext.Data.ExternalID
                userName   = $actionContext.Data.UserName
                active     = $false
                emails     = $emailList
                meta       = @{
                    resourceType = "User"
                }
                name       = [ordered]@{
                    formatted        = $actionContext.Data.NameFormatted
                    familyName       = $actionContext.Data.FamilyName
                    familyNamePrefix = $actionContext.Data.FamilyNamePrefix
                    givenName        = $actionContext.Data.GivenName
                }
            } | ConvertTo-Json

            $splatCreateParams = @{
                Uri     = "$($actionContext.configuration.BaseUrl)/api/iris/v1/$($actionContext.configuration.ApiID)/scim/Users"
                Headers = $headers
                Body    = $body
                Method  = 'Post'
            }

            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating IrisIntranet account'

                $createdAccount = Invoke-RestMethod @splatCreateParams

                $outputContext.Data = ConvertTo-HelloIDOutputAccountObject($createdAccount)
                $outputContext.AccountReference = $createdAccount.id
            }
            else {
                Write-Information '[DryRun] Create and correlate IrisIntranet account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating IrisIntranet account'

            $outputContext.Data = $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.Id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $lifecycleProcess
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IrisIntranetError -ErrorObject $ex
        $auditLogMessage = "Could not create or correlate IrisIntranet account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create or correlate IrisIntranet account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}