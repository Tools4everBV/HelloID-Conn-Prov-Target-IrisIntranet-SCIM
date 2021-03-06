#####################################################
# HelloID-Conn-Prov-Target-Iris-Intranet-Create
#
# Version: 1.0.0.3
#####################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

$account = [PSCustomObject]@{
    ExternalId          = $p.ExternalId
    UserName            = $p.UserName
    GivenName           = $p.Name.GivenName
    FamilyName          = $p.Name.FamilyName
    FamilyNameFormatted = $p.DisplayName
    FamilyNamePrefix    = ''
    IsUserActive        = $true
    EmailAddress        = $p.Contact.Business.Email
    EmailAddressType    = 'Work'
    IsEmailPrimary      = $true
}

#region functions
function Invoke-ScimRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
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
        $Headers
    )

    try {
        Write-Verbose "Invoking command '$($MyInvocation.MyCommand)'"
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        $splatParams = @{
            Uri         = "$($config.BaseUrl)/$Uri"
            Headers     = $Headers
            Method      = $Method
            ContentType = $ContentType
        }

        if ($Body){
            Write-Verbose 'Adding body to request'
            $splatParams['Body'] = $Body
        }

        Invoke-RestMethod @splatParams
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Invoke-ScimPagedRestMethod {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param (
        [int]
        $TotalResults,

        [String]
        $EndPoint,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )

    # Fixed value since each page contains 20 items max
    $count = 20

    try {
        Write-Verbose "Invoking command '$($MyInvocation.MyCommand)'"

        [System.Collections.Generic.List[object]]$dataList = @()
        if ($TotalResults -gt $count){
            Write-Verbose 'Using pagination to retrieve results'
            do {
                $startIndex = $dataList.Count
                $splatPagedWebRequest = @{
                    Uri     = "$($EndPoint)?startIndex=$startIndex&count=$count"
                    Method  = 'GET'
                    Headers = $Headers
                }
                $result = Invoke-ScimRestMethod @splatPagedWebRequest
                foreach ($resource in $result.Resources){
                    $dataList.Add($resource)
                }
            } until ($dataList.Count -eq $totalResults)
        }
        Write-Output $dataList
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $HttpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $HttpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $stream = $ErrorObject.Exception.Response.GetResponseStream()
            $stream.Position = 0
            $streamReader = New-Object System.IO.StreamReader $Stream
            $errorResponse = $StreamReader.ReadToEnd()
            $HttpErrorObj.ErrorMessage = $errorResponse
        }
        Write-Output $HttpErrorObj
    }
}
#endregion

try {
    # Begin
    Write-Verbose 'Adding token to authorization headers'
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $($config.ApiKey)")

    Write-Verbose 'Getting total number of users'
    $response = Invoke-ScimRestMethod -Uri 'Users' -Method 'GET' -headers $headers
    $totalResults = $response.totalResults

    Write-Verbose "Retrieving '$totalResults' users"
    if ($totalResults -gt 20){
        $responseAllUsers = Invoke-ScimPagedRestMethod -TotalResults $totalResults -EndPoint 'Users' -Headers $headers
    } else {
        $responseAllUsers = Invoke-ScimRestMethod -Uri 'Users' -Method 'GET' -headers $headers
    }

    Write-Verbose "Verifying if account for '$($p.DisplayName)' must be created or correlated"
    $lookup = $responseAllUsers.Resources | Group-Object -Property 'ExternalId' -AsHashTable
    $userObject = $lookup[$account.ExternalId]
    if ($userObject){
        Write-Verbose "Account for '$($account.DisplayName)' found with id '$($userObject.id)', switching to 'correlate'"
        $action = 'Correlate'
    } else {
        Write-Verbose "No account for '$($account.DisplayName)' has been found, switching to 'create'"
        $action = 'Create'
    }

    # Process
    if (-not ($dryRun -eq $true)){
        switch ($action) {
            'Create' {
                Write-Verbose "Creating account for '$($p.DisplayName)'"

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
                $response = Invoke-ScimRestMethod -Uri 'Users' -Method 'POST' -body $body -headers $headers
                $accountReference = $response.id
                break
            }

            'Correlate'{
                Write-Verbose "Correlating account for '$($p.DisplayName)'"
                $accountReference = $userObject.id
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "$action account for: $($p.DisplayName) was successful. AccountReference is: $accountReference"
            IsError = $False
        })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -Error $ex
        $errorMessage = "Could not create scim account for: $($p.DisplayName). Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not create scim account for: $($p.DisplayName). Error: $($ex.Exception.Message)"
    }
    Write-Error $errorMessage
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
# End
} Finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
