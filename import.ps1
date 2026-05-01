#################################################
# HelloID-Conn-Prov-Target-IrisIntranet-Import
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
        foreach ($property in $actionContext.ImportFields) {
            switch ($property) {
                'Id'                { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.id }
                'EmailAddress'      { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.emails.value }
                'IsEmailPrimary'    { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue "$($AccountObject.emails.primary)" }
                'EmailAddressType'  { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.emails.type }
                'Username'          { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.userName }
                'ExternalId'        { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.externalId }
                'GivenName'         { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.name.givenName }
                'NameFormatted'     { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.name.formatted }
                'FamilyName'        { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.name.familyName }
                'FamilyNamePrefix'  { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.name.familyNamePrefix }
                'IsEnabled'         { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.active }
                default             { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.$($property.Name) }
            }
        }
        Write-Output $helloidAccountObject
    }
}
#endregion

try {
    Write-Information 'Starting IrisIntranet account entitlement import'

    $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.ApiToken)")

    $take = 20
    $startIndex = 0
    do {
        $splatImportAccountParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/iris/v1/$($actionContext.Configuration.ApiID)/scim/Users?startIndex=$($startIndex)&count=$($take)"
            Method  = 'GET'
            Headers = $headers
        }

        $response = Invoke-RestMethod @splatImportAccountParams

        $result = $response.Resources
        $totalResults = $response.totalResults

        if ($null -ne $result) {
            foreach ($importedAccount in $result) {
                $data = ConvertTo-HelloIDAccountObject -AccountObject $importedAccount

                # Set Enabled based on importedAccount status
                $isEnabled = $false
                if ($importedAccount.active -eq $true) {
                    $isEnabled = $true
                }

                # Make sure the displayName has a value
                $displayName = "$($importedAccount.name.formatted)"
                if ([string]::IsNullOrEmpty($displayName)) {
                    $displayName = $importedAccount.Id
                }

                # Make sure the userName has a value
                $UserName =  $importedAccount.UserName
                if ([string]::IsNullOrWhiteSpace($UserName)) {
                    $UserName = $importedAccount.Id
                }

                Write-Output @{
                    AccountReference = $importedAccount.Id
                    displayName      = $displayName
                    UserName         = $UserName
                    Enabled          = $isEnabled
                    Data             = $data
                }
                $startIndex++
            }
        }
    } while (($result.count -gt 0) -and ($startIndex -lt $totalResults))
    Write-Information 'IrisIntranet account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IrisIntranetError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import IrisIntranet account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import IrisIntranet account entitlements. Error: $($ex.Exception.Message)"
    }
}
