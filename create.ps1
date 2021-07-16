#####################################################
# HelloID-Conn-Prov-Target-IrisIntranet-Create
#
# Version: 1.0.0.0
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$personObj = $person | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

$account = [PSCustomObject]@{
    ExternalId          = $personObj.ExternalId
    UserName            = $personObj.UserName
    GivenName           = $personObj.Name.GivenName
    FamilyName          = $personObj.Name.FamilyName
    FamilyNameFormatted = $personObj.DisplayName
    FamilyNamePrefix    = ''
    IsUserActive        = $true
    EmailAddress        = $personObj.Contact.Business.Email
    EmailAddressType    = 'Work'
    IsEmailPrimary      = $true
}

#region Helper Functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $HttpErrorObj = @{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $HttpErrorObj['ErrorMessage'] = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $stream = $ErrorObject.Exception.Response.GetResponseStream()
            $stream.Position = 0
            $streamReader = New-Object System.IO.StreamReader $Stream
            $errorResponse = $StreamReader.ReadToEnd()
            $HttpErrorObj['ErrorMessage'] = $errorResponse
        }
        Write-Output "'$($HttpErrorObj.ErrorMessage)', TargetObject: '$($HttpErrorObj.RequestUri), InvocationCommand: '$($HttpErrorObj.MyCommand)"
    }
}
#endregion

if (-not($dryRun -eq $true)) {
    try {
        [System.Collections.Generic.List[object]]$emailList = @()
        $emailList.Add(
            [PSCustomObject]@{
                primary = $account.IsEmailPrimary
                type    = $account.EmailAddressType
                display = $account.EmailAddress
                value   = $account.EmailAddress
            }
        )

        $body = [ordered]@{
            schemas    = @(
                "urn:ietf:params:scim:schemas:core:2.0:User",
                "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"
            )
            externalId = $account.ExternalID
            userName   = $account.UserName
            active     = $account.IsUserActive
            emails     = $emailList
            meta       = @{
                resourceType = "User"
            }
            name = [ordered]@{
                formatted        = $account.NameFormatted
                familyName       = $account.FamilyName
                familyNamePrefix = $account.FamilyNamePrefix
                givenName        = $account.GivenName
            }
        } | ConvertTo-Json

        Write-Verbose 'Adding Authorization headers'
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $($config.ApiToken)")
        $splatParams = @{
            Uri      = "$($config.BaseUrl)/api/iris/v1/$($config.ApiID)/scim/Users"
            Headers  = $headers
            Body     = $body
            Method   = 'Post'
        }

        $results = Invoke-RestMethod @splatParams
        if ($results.id){
            $logMessage = "Account for '$($personObj.DisplayName)' successfully created with id: '$($results.id)'"
            Write-Verbose $logMessage
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = $logMessage
                IsError = $False
            })
        }
    } catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            $auditMessage = "Account for '$($personObj.DisplayName)' not created. Error: $errorMessage"
        } else {
            $auditMessage = "Account for '$($personObj.DisplayName)' not created. Error: $($ex.Exception.Message)"
        }
        $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
        Write-Error $auditMessage
    }
}

$result = [PSCustomObject]@{
    Success          = $success
    Account          = $account
    AccountReference = $($results.id)
    AuditLogs        = $auditLogs
}

Write-Output $result | ConvertTo-Json -Depth 10
