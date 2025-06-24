param (
    [Parameter(Mandatory)]
    [string[]]$AdminEmails,

    [Parameter(Mandatory)]
    [string]$SmtpServer,

    [Parameter(Mandatory)]
    [string]$EmailFrom,

    [string]$TemplatesPath = "",

    [int]$SmtpPort = 587,

    [string]$Username = "",

    [string]$Password = "",

    [switch]$SmtpSSL = $true,

    [switch]$EnableLog,

    [int]$InactivityDays = 45,

    [int]$NotificationDays = 15,

    [switch]$IncludeExpiringAccounts,

    [int]$ExpirationWarningDays = 30,

    [switch]$DebugMode,

    [switch]$DryRun
)

# Script version
$scriptVersion = "2.3.0"
Add-Type -AssemblyName System.Web

# Changelog
# v2.3.0 - Added support for accounts with expiration dates via -IncludeExpiringAccounts parameter

<#
.SYNOPSIS
    Manage inactive Active Directory accounts with optional expiration date handling.

.DESCRIPTION
    This script identifies inactive Active Directory accounts and:
    - Sends notifications to users before disabling accounts.
    - Automatically disables accounts after specified days of inactivity.
    - Optionally manages accounts with expiration dates when -IncludeExpiringAccounts is used.
    - Generates comprehensive reports for administrators.
    - Protects accounts marked with //ACCOUNT_PROTECTED// in description.

.PARAMETER AdminEmails
    Email addresses of administrators to receive the summary report.

.PARAMETER SmtpServer
    SMTP server address for sending emails.

.PARAMETER EmailFrom
    The email address to use as the sender.

.PARAMETER TemplatesPath
    Directory containing HTML templates for email bodies.

.PARAMETER SmtpPort
    SMTP server port. Default is 587.

.PARAMETER Username
    Username for SMTP authentication. Leave empty for anonymous.

.PARAMETER Password
    Password for SMTP authentication. Leave empty for anonymous.

.PARAMETER SmtpSSL
    Enable or disable SSL for SMTP. Default is true.

.PARAMETER EnableLog
    Enable logging of actions to a log file.

.PARAMETER InactivityDays
    Number of days of inactivity before accounts are deactivated. Default is 45.

.PARAMETER NotificationDays
    Number of days before deactivation to send notification. Default is 15.

.PARAMETER IncludeExpiringAccounts
    Include accounts with expiration dates in processing and reporting.

.PARAMETER ExpirationWarningDays
    Days before account expiration to show warning in reports. Default is 30.

.PARAMETER DebugMode
    Enable debug mode. Outputs logs to the console.

.PARAMETER DryRun
    Simulate actions without making changes to Active Directory.

.EXAMPLE
    .\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" `
        -EmailFrom "no-reply@example.com" -EnableLog

.EXAMPLE
    .\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" `
        -EmailFrom "no-reply@example.com" -IncludeExpiringAccounts -EnableLog

.NOTES
    Script version: 2.3.0
    Author: Philippe Candido (philippe.candido@emerging-it.fr)
    
    IMPORTANT: 
    - Accounts with //ACCOUNT_PROTECTED// in description are excluded from deactivation.
    - Use -IncludeExpiringAccounts to process accounts with expiration dates.
#>

#region Global Variables and Initialization

# Calculate thresholds
$Today = Get-Date
$InactivityThreshold = $Today.AddDays(-$InactivityDays)
$DeactivationThreshold = $Today.AddDays(-$InactivityDays)
$NotificationStartDate = $Today.AddDays(-$InactivityDays + $NotificationDays)
$ExpirationWarningThreshold = $Today.AddDays($ExpirationWarningDays)

# Get script name and current date for reporting
$ScriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path
$CurrentDate = Get-Date -Format "dd-MM-yyyy HH:mm:ss"

# Constants for account expiration
$NEVER_EXPIRES_VALUES = @(0, 9223372036854775807)

#endregion

#region Logging Functions

function Write-Log {
    param (
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = (Get-Date).ToString("yyyyMMdd-HH:mm:ss")
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if ($DebugMode -or $Level -eq "ERROR" -or $Level -eq "WARNING") {
        Write-Host $logMessage -ForegroundColor $(
            switch ($Level) {
                "ERROR" { "Red" }
                "WARNING" { "Yellow" }
                "DEBUG" { "Cyan" }
                default { "White" }
            }
        )
    }
    
    if ($EnableLog) {
        Add-Content -Path "$PSScriptRoot\InactiveAccountsManager.log" -Value $logMessage
    }
}

#endregion

#region Account Expiration Functions

function Get-AccountExpirationInfo {
    param (
        [Parameter(Mandatory)]
        $AccountExpiresValue
    )
    
    if ($AccountExpiresValue -in $NEVER_EXPIRES_VALUES) {
        return @{
            HasExpiration = $false
            Status = "NeverExpires"
            ExpirationDate = $null
            DaysUntilExpiration = $null
        }
    }
    
    try {
        $expirationDate = [DateTime]::FromFileTime($AccountExpiresValue)
        $daysUntilExpiration = [math]::Ceiling(($expirationDate - $Today).TotalDays)
        
        $status = if ($expirationDate -gt $Today) {
            "FutureExpiration"
        } elseif ($expirationDate.Date -eq $Today.Date) {
            "ExpiringToday"
        } else {
            "AlreadyExpired"
        }
        
        return @{
            HasExpiration = $true
            Status = $status
            ExpirationDate = $expirationDate
            DaysUntilExpiration = $daysUntilExpiration
        }
    }
    catch {
        Write-Log "Error parsing account expiration date: $AccountExpiresValue - $_" -Level "ERROR"
        return @{
            HasExpiration = $false
            Status = "InvalidDate"
            ExpirationDate = $null
            DaysUntilExpiration = $null
        }
    }
}

function Get-ExpirationDisplayText {
    param ($ExpirationInfo)
    
    if (-not $ExpirationInfo.HasExpiration) {
        return "N'expire jamais"
    }
    
    switch ($ExpirationInfo.Status) {
        "FutureExpiration" {
            $daysText = if ($ExpirationInfo.DaysUntilExpiration -eq 1) { "1 jour" } else { "$($ExpirationInfo.DaysUntilExpiration) jours" }
            return "Expire dans $daysText ($($ExpirationInfo.ExpirationDate.ToString('dd/MM/yyyy')))"
        }
        "ExpiringToday" {
            return "Expire aujourd'hui ($($ExpirationInfo.ExpirationDate.ToString('dd/MM/yyyy')))"
        }
        "AlreadyExpired" {
            $daysPast = [math]::Abs($ExpirationInfo.DaysUntilExpiration)
            $daysText = if ($daysPast -eq 1) { "1 jour" } else { "$daysPast jours" }
            return "Expiré depuis $daysText ($($ExpirationInfo.ExpirationDate.ToString('dd/MM/yyyy')))"
        }
        default {
            return "Statut d'expiration inconnu"
        }
    }
}

#endregion

#region Template and Email Functions

function Render-Template {
    param (
        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [hashtable]$Variables
    )

    if (-not (Test-Path $TemplatePath)) {
        throw "Template file not found: $TemplatePath"
    }

    try {
        $TemplateContent = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
        
        foreach ($Key in $Variables.Keys) {
            $pattern = "{{\s*$Key\s*}}"
            $TemplateContent = $TemplateContent -replace $pattern, $Variables[$Key]
        }
        
        return $TemplateContent
    }
    catch {
        Write-Log "Error rendering template $TemplatePath : $_" -Level "ERROR"
        throw
    }
}

function Send-SecureMail {
    param (
        [Parameter(Mandatory)]
        [string[]]$To,

        [Parameter(Mandatory)]
        [string]$From,

        [Parameter(Mandatory)]
        [string]$Subject,

        [Parameter(Mandatory)]
        [string]$Body,

        [Parameter(Mandatory)]
        [string]$SmtpServer,

        [string]$Logo,

        [int]$SmtpPort = 587,

        [string]$Username = "",

        [string]$Password = "",

        [switch]$SmtpSSL = $true,

        [switch]$DryRun,

        [switch]$DebugMode
    )

    if ($DryRun) {
        Write-Host "[DRY-RUN] Email to $($To -join ', '): Subject='$Subject'"
        Write-Log "Dry-run mode: Email to $($To -join ', ') simulated." -Level "INFO"
        return
    }

    try {
        $SMTP = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        $SMTP.EnableSsl = $SmtpSSL

        if ($script:SmtpAuth) {
            if ($script:credential) {
                $SMTP.Credentials = $script:credential.GetNetworkCredential()
                Write-Log "Using credentials from XML file" -Level "DEBUG"
            } elseif ($Username -and $Password) {
                $SMTP.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
                Write-Log "Using provided credentials" -Level "DEBUG"
            } else {
                Write-Log "SMTP authentication enabled but no credentials provided" -Level "WARNING"
            }
        }
        
        $MailMessage = New-Object System.Net.Mail.MailMessage
        $mailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8
        $mailMessage.BodyEncoding = [System.Text.Encoding]::UTF8
        $MailMessage.From = $From
        
        foreach ($Recipient in $To) {
            if ($Recipient -match "^[^@]+@[^@]+\.[^@]+$") {
                $MailMessage.To.Add($Recipient)
            } else {
                Write-Log "Invalid email address skipped: $Recipient" -Level "WARNING"
            }
        }
        
        if ($MailMessage.To.Count -eq 0) {
            throw "No valid email addresses found"
        }
        
        $MailMessage.Subject = $Subject
        $MailMessage.Body = $Body
        $MailMessage.IsBodyHtml = $true

        if ($script:embeddedImages -and $LogoPath -and (Test-Path $LogoPath)) {
            $Attachment = New-Object Net.Mail.Attachment($LogoPath)
            $Attachment.ContentId = "logo-image"
            $mailMessage.Attachments.Add($Attachment)
        }

        $SMTP.Send($MailMessage)
        Write-Log "Email sent successfully to: $($To -join ', ')" -Level "INFO"

    } catch {
        Write-Log "Failed to send email to $($To -join ', '). Error: $_" -Level "ERROR"
        throw
    } finally {
        if ($MailMessage) { $MailMessage.Dispose() }
        if ($SMTP) { $SMTP.Dispose() }
    }
}

#endregion

#region Configuration and Validation

Write-Log "Starting InactiveAccountsManager v$scriptVersion" -Level "INFO"
if ($IncludeExpiringAccounts) {
    Write-Log "Extended mode: Including accounts with expiration dates" -Level "INFO"
}

# Load configuration file
$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath "config.ps1"
if (-not (Test-Path -Path $ConfigFile)) {
    Write-Log "Configuration file not found: $ConfigFile" -Level "ERROR"
    exit 1
}

try {
    . $ConfigFile
    $phoneSupportHref = $phoneSupport.Replace(" ", "")
    Write-Log "Configuration file loaded successfully" -Level "INFO"
    
    $script:SmtpAuth = $SmtpAuth
    $script:embeddedImages = $embeddedImages
    
} catch {
    Write-Log "Configuration cannot be loaded. Error: $_" -Level "ERROR"
    exit 1
}

# Validate required configuration variables
$requiredVars = @('emailSupport', 'phoneSupport', 'urlSupport')
foreach ($var in $requiredVars) {
    if (-not (Get-Variable -Name $var -ErrorAction SilentlyContinue).Value) {
        Write-Log "Missing required configuration variable: $var" -Level "ERROR"
        exit 1
    }
}

# Load SMTP credentials if available
$credentialFilePath = Join-Path -Path $PSScriptRoot -ChildPath "smtp_credential.xml"
if (Test-Path -Path $credentialFilePath) {
    try {
        $script:credential = Import-Clixml -Path $credentialFilePath
        Write-Log "SMTP credentials loaded from $credentialFilePath" -Level "INFO"
    } catch {
        Write-Log "Failed to load SMTP credentials: $_" -Level "ERROR"
        $script:credential = $null
    }
} else {
    Write-Log "No smtp_credential.xml found. Using provided parameters" -Level "INFO"
    $script:credential = $null
}

# Validate and set templates path
if (-not $TemplatesPath) {
    $TemplatesPath = Join-Path -Path $PSScriptRoot -ChildPath "Templates"
}

$templatePaths = @(
    "$TemplatesPath\UserDesactivationNotification.html",
    "$TemplatesPath\UserDesactivatedNotification.html",
    "$TemplatesPath\InactiveAccountsReport.html",
    "$TemplatesPath\logo.png"
)

foreach ($templatePath in $templatePaths) {
    if (-not (Test-Path -Path $templatePath)) {
        Write-Log "Required file not found: $templatePath" -Level "ERROR"
        exit 1
    }
}

$LogoPath = Join-Path -Path $TemplatesPath -ChildPath "logo.png"

#endregion

#region Debug Information

if ($DebugMode) {
    Write-Log "=== DEBUG MODE ACTIVATED ===" -Level "DEBUG"
    Write-Log "Script Parameters:" -Level "DEBUG"
    Write-Log "  - AdminEmails: $($AdminEmails -join ', ')" -Level "DEBUG"
    Write-Log "  - InactivityDays: $InactivityDays" -Level "DEBUG"
    Write-Log "  - NotificationDays: $NotificationDays" -Level "DEBUG"
    Write-Log "  - IncludeExpiringAccounts: $IncludeExpiringAccounts" -Level "DEBUG"
    Write-Log "  - ExpirationWarningDays: $ExpirationWarningDays" -Level "DEBUG"
    Write-Log "  - DryRun: $DryRun" -Level "DEBUG"
    Write-Log "" -Level "DEBUG"
    Write-Log "Calculated Thresholds:" -Level "DEBUG"
    Write-Log "  - Today: $($Today.ToString('yyyy-MM-dd HH:mm:ss'))" -Level "DEBUG"
    Write-Log "  - InactivityThreshold: $($InactivityThreshold.ToString('yyyy-MM-dd HH:mm:ss'))" -Level "DEBUG"
    Write-Log "  - ExpirationWarningThreshold: $($ExpirationWarningThreshold.ToString('yyyy-MM-dd HH:mm:ss'))" -Level "DEBUG"
    Write-Log "==============================" -Level "DEBUG"
}

#endregion

#region Active Directory Operations

# Validate AD Module
try {
    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        throw "Active Directory module not available"
    }
    
    if (-not (Get-Module -Name ActiveDirectory)) {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    
    Write-Log "Active Directory module loaded successfully" -Level "INFO"
} catch {
    Write-Log "Failed to load Active Directory module: $_" -Level "ERROR"
    exit 1
}

# Build AD filter based on IncludeExpiringAccounts parameter
Write-Log "Querying Active Directory for accounts..." -Level "INFO"

try {
    $NotificationThresholdFileTime = $NotificationStartDate.ToFileTime()
    
    if ($IncludeExpiringAccounts) {
        # Include all enabled accounts regardless of expiration
        $adFilter = {
            Enabled -eq $true -and 
            LastLogonTimestamp -lt $NotificationThresholdFileTime
        }
        Write-Log "Using extended query (including accounts with expiration dates)" -Level "DEBUG"
    } else {
        # Exclude accounts with expiration dates (original behavior)
        $adFilter = {
            Enabled -eq $true -and 
            LastLogonTimestamp -lt $NotificationThresholdFileTime -and
            (AccountExpires -eq 0 -or AccountExpires -eq 9223372036854775807)
        }
        Write-Log "Using standard query (excluding accounts with expiration dates)" -Level "DEBUG"
    }
    
    $AllAccounts = Get-ADUser -Filter $adFilter `
        -Properties DisplayName, SamAccountName, EmailAddress, LastLogonTimestamp, Description, AccountExpires -ErrorAction Stop |
        Select-Object DisplayName, SamAccountName, EmailAddress, Description, AccountExpires,
            @{Name="LastLogon";Expression={
                if ($_.LastLogonTimestamp) {
                    [datetime]::FromFileTime($_.LastLogonTimestamp)
                } else {
                    [datetime]::FromFileTime(0)
                }
            }}

    Write-Log "Found $($AllAccounts.Count) accounts matching criteria" -Level "INFO"
    
} catch {
    Write-Log "Failed to query Active Directory: $_" -Level "ERROR"
    exit 1
}

#endregion

#region Account Categorization

# Categorize accounts
$InactiveAccounts = @()
$ExpiringAccounts = @()
$ExpiredActiveAccounts = @()

foreach ($account in $AllAccounts) {
    $expirationInfo = Get-AccountExpirationInfo -AccountExpiresValue $account.AccountExpires
    
    if ($IncludeExpiringAccounts -and $expirationInfo.HasExpiration) {
        switch ($expirationInfo.Status) {
            "FutureExpiration" {
                $ExpiringAccounts += $account | Add-Member -NotePropertyName "ExpirationInfo" -NotePropertyValue $expirationInfo -PassThru
            }
            { $_ -in @("AlreadyExpired", "ExpiringToday") } {
                $ExpiredActiveAccounts += $account | Add-Member -NotePropertyName "ExpirationInfo" -NotePropertyValue $expirationInfo -PassThru
            }
        }
    } else {
        # Standard inactive account (no expiration or not including expiring accounts)
        $InactiveAccounts += $account | Add-Member -NotePropertyName "ExpirationInfo" -NotePropertyValue $expirationInfo -PassThru
    }
}

Write-Log "Account categorization:" -Level "INFO"
Write-Log "  - Inactive accounts (standard processing): $($InactiveAccounts.Count)" -Level "INFO"
if ($IncludeExpiringAccounts) {
    Write-Log "  - Accounts with future expiration: $($ExpiringAccounts.Count)" -Level "INFO"
    Write-Log "  - Expired accounts still active: $($ExpiredActiveAccounts.Count)" -Level "INFO"
}

#endregion

#region Standard Inactive Account Processing

$InactiveAccountsTable = @()
$processedCount = 0
$notifiedCount = 0
$deactivatedCount = 0
$protectedCount = 0

if ($InactiveAccounts.Count -gt 0) {
    Write-Log "Processing inactive accounts..." -Level "INFO"

    foreach ($Account in $InactiveAccounts) {
        $processedCount++
        
        $DaysInactive = [math]::Floor(($Today - $Account.LastLogon).TotalDays)
        $DaysUntilDeactivation = $InactivityDays - $DaysInactive
        $ShouldNotify = ($DaysInactive -ge ($InactivityDays - $NotificationDays))
        $ShouldDeactivate = ($DaysInactive -ge $InactivityDays)
        
        Write-Log "Processing account: $($Account.SamAccountName) (Inactive: $DaysInactive days, Until deactivation: $DaysUntilDeactivation days)" -Level "DEBUG"
        
        $accountRecord = [PSCustomObject]@{
            SamAccountName    = $Account.SamAccountName
            DisplayName       = $Account.DisplayName
            EmailAddress      = $Account.EmailAddress
            LastLogon         = $Account.LastLogon
            DaysInactive      = $DaysInactive
            DaysRemaining     = $DaysUntilDeactivation
            ExpirationStatus  = Get-ExpirationDisplayText -ExpirationInfo $Account.ExpirationInfo
            Action            = "none"
            AccountType       = "Inactive"
        }
        
        # Check if account is protected
        if ($Account.Description -like "*//ACCOUNT_PROTECTED//*") {
            Write-Log "Account $($Account.SamAccountName) is protected - skipping" -Level "INFO"
            $accountRecord.Action = "protected"
            $protectedCount++
            $InactiveAccountsTable += $accountRecord
            continue
        }
        
        $actionTaken = $false
        
        # Send notification if needed and account has email
        if ($ShouldNotify -and $Account.EmailAddress) {
            try {
                $templateVars = @{
                    DisplayName      = $Account.DisplayName
                    LastLogon        = $Account.LastLogon.ToString("dd MMMM yyyy à HH:mm:ss")
                    InactivityDays   = $InactivityDays
                    ScriptName       = $ScriptName
                    DaysRemaining    = [math]::Max(0, $DaysUntilDeactivation)
                    DaysInactive     = $DaysInactive
                    phoneSupport     = $phoneSupport
                    phoneSupportHref = $phoneSupportHref
                    urlSupport       = $urlSupport
                    emailSupport     = $emailSupport
                }
                
                if ($ShouldDeactivate) {
                    $subject = "URGENT: Votre compte a été désactivé"
                    $templatePath = "$TemplatesPath\UserDesactivatedNotification.html"
                } else {
                    $subject = "ATTENTION: Votre compte sera désactivé dans $($DaysUntilDeactivation) jour$(if($DaysUntilDeactivation -gt 1){'s'})"
                    $templatePath = "$TemplatesPath\UserDesactivationNotification.html"
                }
                
                $UserBody = Render-Template -TemplatePath $templatePath -Variables $templateVars
                
                Send-SecureMail -To $Account.EmailAddress -From $EmailFrom -Subject $subject -Body $UserBody `
                    -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password `
                    -SmtpSSL:$SmtpSSL -DryRun:$DryRun -Logo $LogoPath
                
                $accountRecord.Action = "notified"
                $notifiedCount++
                $actionTaken = $true
                
            } catch {
                Write-Log "Failed to send notification to $($Account.EmailAddress): $_" -Level "ERROR"
            }
        } elseif ($ShouldNotify -and -not $Account.EmailAddress) {
            Write-Log "Account $($Account.SamAccountName) needs notification but has no email address" -Level "WARNING"
        }
        
        # Deactivate account if needed
        if ($ShouldDeactivate) {
            try {
                $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
                $UpdatedDescription = if ($Account.Description -notlike "*| Disabled at*") {
                    "$($Account.Description) | Disabled at $timestamp".Trim()
                } else {
                    $Account.Description
                }
                
                if ($DryRun) {
                    Write-Log "[DRY-RUN] Would deactivate account: $($Account.SamAccountName)" -Level "INFO"
                } else {
                    $currentAccount = Get-ADUser -Identity $Account.SamAccountName -Properties Enabled -ErrorAction Stop
                    
                    if ($currentAccount.Enabled) {
                        Set-ADUser -Identity $Account.SamAccountName -Enabled $false -Description $UpdatedDescription -ErrorAction Stop
                        Write-Log "Deactivated account: $($Account.SamAccountName)" -Level "INFO"
                    } else {
                        Write-Log "Account $($Account.SamAccountName) is already disabled" -Level "WARNING"
                    }
                }
                
                $accountRecord.Action = if ($actionTaken) { "notified_and_deactivated" } else { "deactivated" }
                $deactivatedCount++
                
            } catch {
                Write-Log "Failed to deactivate account $($Account.SamAccountName): $_" -Level "ERROR"
                $accountRecord.Action = "error"
            }
        }
        
        $InactiveAccountsTable += $accountRecord
    }
}

#endregion

#region Expiring Accounts Processing (when IncludeExpiringAccounts is enabled)

$ExpiringAccountsTable = @()
$ExpiredAccountsTable = @()

if ($IncludeExpiringAccounts) {
    
    # Process accounts with future expiration
    foreach ($Account in $ExpiringAccounts) {
        $expirationInfo = $Account.ExpirationInfo
        $DaysInactive = [math]::Floor(($Today - $Account.LastLogon).TotalDays)
        
        $accountRecord = [PSCustomObject]@{
            SamAccountName    = $Account.SamAccountName
            DisplayName       = $Account.DisplayName
            EmailAddress      = $Account.EmailAddress
            LastLogon         = $Account.LastLogon
            DaysInactive      = $DaysInactive
            ExpirationDate    = $expirationInfo.ExpirationDate
            DaysUntilExpiration = $expirationInfo.DaysUntilExpiration
            ExpirationStatus  = Get-ExpirationDisplayText -ExpirationInfo $expirationInfo
            Action            = "monitored"
            AccountType       = "Expiring"
        }
        
        $ExpiringAccountsTable += $accountRecord
    }
    
    # Process expired accounts that are still active
    foreach ($Account in $ExpiredActiveAccounts) {
        $expirationInfo = $Account.ExpirationInfo
        $DaysInactive = [math]::Floor(($Today - $Account.LastLogon).TotalDays)
        
        $accountRecord = [PSCustomObject]@{
            SamAccountName      = $Account.SamAccountName
            DisplayName         = $Account.DisplayName
            EmailAddress        = $Account.EmailAddress
            LastLogon           = $Account.LastLogon
            DaysInactive        = $DaysInactive
            ExpirationDate      = $expirationInfo.ExpirationDate
            DaysSinceExpiration = [math]::Abs($expirationInfo.DaysUntilExpiration)
            ExpirationStatus    = Get-ExpirationDisplayText -ExpirationInfo $expirationInfo
            Action              = "requires_attention"
            AccountType         = "ExpiredActive"
        }
        
        # Check if account is protected
        if ($Account.Description -like "*//ACCOUNT_PROTECTED//*") {
            $accountRecord.Action = "protected_expired"
        }
        
        $ExpiredAccountsTable += $accountRecord
    }
    
    Write-Log "Expiring accounts processing:" -Level "INFO"
    Write-Log "  - Accounts with future expiration monitored: $($ExpiringAccountsTable.Count)" -Level "INFO"
    Write-Log "  - Expired accounts requiring attention: $($ExpiredAccountsTable.Count)" -Level "INFO"
}

#endregion

#region Generate Comprehensive Admin Report

Write-Log "Generating comprehensive administrator report..." -Level "INFO"

# Generate HTML for inactive accounts
$InactiveAccountsTableHtml = ""
if ($InactiveAccountsTable.Count -eq 0) {
    $InactiveAccountsTableHtml = "<tr><td colspan='7' style='text-align:center; padding:20px;'>Aucun compte inactif traité.</td></tr>"
} else {
    foreach ($Row in $InactiveAccountsTable) {
        $actionColor = switch ($Row.Action) {
            "deactivated" { "color: #d9534f; font-weight: bold;" }
            "notified_and_deactivated" { "color: #d9534f; font-weight: bold;" }
            "notified" { "color: #f0ad4e;" }
            "protected" { "color: #5bc0de;" }
            "error" { "color: #d9534f; background-color: #f2dede;" }
            default { "" }
        }
        
        $emailCell = if ($Row.EmailAddress) {
            "<a href='mailto:$([System.Web.HttpUtility]::HtmlEncode($Row.EmailAddress))'>$([System.Web.HttpUtility]::HtmlEncode($Row.EmailAddress))</a>"
        } else {
            "<em>Pas d'adresse email</em>"
        }
        
        $InactiveAccountsTableHtml += "<tr>" +
            "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.SamAccountName))</td>" +
            "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.DisplayName))</td>" +
            "<td style='padding: 8px; border: 1px solid #ddd;'>$emailCell</td>" +
            "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.LastLogon.ToString('dd/MM/yyyy HH:mm')))</td>" +
            "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.DaysInactive))</td>" +
            "<td style='padding: 8px; border: 1px solid #ddd; font-size: 12px;'>$([System.Web.HttpUtility]::HtmlEncode($Row.ExpirationStatus))</td>" +
            "<td style='padding: 8px; border: 1px solid #ddd; $actionColor'>$([System.Web.HttpUtility]::HtmlEncode($Row.Action))</td>" +
            "</tr>"
    }
}

# Generate additional sections for expiring accounts if enabled
$AdditionalSections = ""

if ($IncludeExpiringAccounts) {
    
    # Section for accounts with future expiration
    if ($ExpiringAccountsTable.Count -gt 0) {
        $ExpiringAccountsHtml = ""
        foreach ($Row in $ExpiringAccountsTable) {
            $warningStyle = if ($Row.DaysUntilExpiration -le 7) {
                "background-color: #f2dede; color: #a94442;"
            } elseif ($Row.DaysUntilExpiration -le 30) {
                "background-color: #fcf8e3; color: #8a6d3b;"
            } else {
                ""
            }
            
            $emailCell = if ($Row.EmailAddress) {
                "<a href='mailto:$([System.Web.HttpUtility]::HtmlEncode($Row.EmailAddress))'>$([System.Web.HttpUtility]::HtmlEncode($Row.EmailAddress))</a>"
            } else {
                "<em>Pas d'adresse email</em>"
            }
            
            $ExpiringAccountsHtml += "<tr style='$warningStyle'>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.SamAccountName))</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.DisplayName))</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$emailCell</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.ExpirationDate.ToString('dd/MM/yyyy HH:mm')))</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.DaysUntilExpiration))</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.DaysInactive))</td>" +
                "</tr>"
        }
        
        $AdditionalSections += @"
        <div style="margin-top: 30px;">
            <h2 style="color: #0056b3; font-size: 18px; margin-bottom: 15px;">📅 Comptes avec expiration programmée ($($ExpiringAccountsTable.Count))</h2>
            <table style="width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 14px; text-align: left; border: 1px solid #ddd;">
                <thead>
                    <tr style="background-color: #f2f2f2; border-bottom: 2px solid #ddd;">
                        <th style="padding: 10px; border: 1px solid #ddd;">Compte</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Nom</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Email</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Date d'expiration</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Jours restants</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Jours inactifs</th>
                    </tr>
                </thead>
                <tbody>
                    $ExpiringAccountsHtml
                </tbody>
            </table>
        </div>
"@
    }
    
    # Section for expired accounts still active
    if ($ExpiredAccountsTable.Count -gt 0) {
        $ExpiredAccountsHtml = ""
        foreach ($Row in $ExpiredAccountsTable) {
            $emailCell = if ($Row.EmailAddress) {
                "<a href='mailto:$([System.Web.HttpUtility]::HtmlEncode($Row.EmailAddress))'>$([System.Web.HttpUtility]::HtmlEncode($Row.EmailAddress))</a>"
            } else {
                "<em>Pas d'adresse email</em>"
            }
            
            $actionColor = if ($Row.Action -eq "protected_expired") {
                "color: #5bc0de;"
            } else {
                "color: #d9534f; font-weight: bold;"
            }
            
            $ExpiredAccountsHtml += "<tr style='background-color: #f2dede;'>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.SamAccountName))</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.DisplayName))</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$emailCell</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.ExpirationDate.ToString('dd/MM/yyyy HH:mm')))</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.DaysSinceExpiration))</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.DaysInactive))</td>" +
                "<td style='padding: 8px; border: 1px solid #ddd; $actionColor'>$([System.Web.HttpUtility]::HtmlEncode($Row.Action))</td>" +
                "</tr>"
        }
        
        $AdditionalSections += @"
        <div style="margin-top: 30px;">
            <h2 style="color: #d9534f; font-size: 18px; margin-bottom: 15px;">⚠️ Comptes expirés mais encore actifs ($($ExpiredAccountsTable.Count))</h2>
            <p style="color: #a94442; background-color: #f2dede; padding: 10px; border-radius: 4px; margin-bottom: 15px;">
                <strong>Attention :</strong> Ces comptes ont dépassé leur date d'expiration mais sont toujours activés dans AD. Une vérification manuelle est recommandée.
            </p>
            <table style="width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 14px; text-align: left; border: 1px solid #ddd;">
                <thead>
                    <tr style="background-color: #f2f2f2; border-bottom: 2px solid #ddd;">
                        <th style="padding: 10px; border: 1px solid #ddd;">Compte</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Nom</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Email</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Date d'expiration</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Jours de dépassement</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Jours inactifs</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Statut</th>
                    </tr>
                </thead>
                <tbody>
                    $ExpiredAccountsHtml
                </tbody>
            </table>
        </div>
"@
    }
}

# Create enhanced template with additional sections
$enhancedReportTemplate = @"
<html>
    <head>
        <meta charset="UTF-8">
    </head>
<body style="font-family: Arial, sans-serif; background-color: #f4f4f9; margin: 0; padding: 0;">

    <!-- Conteneur principal -->
    <div style="max-width: 1000px; margin: 20px auto; background-color: #ffffff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
        
        <!-- En-tête -->
        <div style="background-color: #0056b3; color: #ffffff; padding: 20px; border-top-left-radius: 8px; border-top-right-radius: 8px; text-align: center;">
            <img src="cid:logo-image" alt="Logo de l'entreprise" style="height: 50px; margin-bottom: 10px;">
            <h1 style="margin: 0; font-size: 22px;">Rapport complet de gestion des comptes</h1>
            <p style="margin: 5px 0; font-size: 14px;">Comptes inactifs depuis plus de {{InactivityDays}} jours</p>
            <p style="margin: 5px 0; font-size: 14px;">Généré le {{CurrentDate}}</p>
        </div>

        <!-- Message principal -->
        <div style="padding: 20px;">
            <h2 style="color: #0056b3; font-size: 18px; margin-bottom: 15px;">📋 Comptes inactifs - Traitement standard</h2>
            <p style="font-size: 16px; color: #333333;">
                Comptes utilisateurs Active Directory identifiés comme inactifs depuis plus de 
                <span style="font-weight: bold;">{{InactivityDays}} jours</span>.
            </p>

            <!-- Tableau des comptes inactifs -->
            <table style="width: 100%; border-collapse: collapse; margin-top: 20px; font-size: 14px; text-align: left; border: 1px solid #ddd;">
                <thead>
                    <tr style="background-color: #f2f2f2; border-bottom: 2px solid #ddd;">
                        <th style="padding: 10px; border: 1px solid #ddd;">Compte</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Nom</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Email</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Dernière connexion</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Jours inactifs</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Expiration</th>
                        <th style="padding: 10px; border: 1px solid #ddd;">Action</th>
                    </tr>
                </thead>
                <tbody>
                    {{InactiveAccountsTableHtml}}
                </tbody>
            </table>
            
            {{AdditionalSections}}
        </div>

        <!-- Pied de page -->
        <div style="background-color: #f4f4f9; padding: 20px; text-align: center; border-bottom-left-radius: 8px; border-bottom-right-radius: 8px; font-size: 12px; color: #555;">
            <p style="margin: 0;">Ce message a été généré automatiquement par le script <b>{{ScriptName}}</b>. Merci de ne pas répondre à cet email.</p>
            <p style="margin-top: 10px;">Cordialement,<br><i>Le Service Informatique</i></p>
        </div>

    </div>

</body>
</html>
"@

# Generate the final report
$AdminBody = $enhancedReportTemplate
$AdminBody = $AdminBody -replace "{{\s*InactivityDays\s*}}", $InactivityDays
$AdminBody = $AdminBody -replace "{{\s*InactiveAccountsTableHtml\s*}}", $InactiveAccountsTableHtml
$AdminBody = $AdminBody -replace "{{\s*AdditionalSections\s*}}", $AdditionalSections
$AdminBody = $AdminBody -replace "{{\s*ScriptName\s*}}", $ScriptName
$AdminBody = $AdminBody -replace "{{\s*CurrentDate\s*}}", $CurrentDate

# Generate subject line
$adminSubject = "Rapport de gestion des comptes - $processedCount comptes traités"
if ($deactivatedCount -gt 0) {
    $adminSubject += " ($deactivatedCount désactivés)"
}
if ($IncludeExpiringAccounts -and ($ExpiringAccountsTable.Count -gt 0 -or $ExpiredAccountsTable.Count -gt 0)) {
    $adminSubject += " [Mode étendu]"
}

Send-SecureMail -To $AdminEmails -From $EmailFrom -Subject $adminSubject -Body $AdminBody `
    -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password `
    -SmtpSSL:$SmtpSSL -DryRun:$DryRun -Logo $LogoPath

#endregion

#region Script Completion

Write-Log "=== RÉSUMÉ D'EXÉCUTION ===" -Level "INFO"
Write-Log "Total comptes inactifs traités: $processedCount" -Level "INFO"
Write-Log "Comptes notifiés: $notifiedCount" -Level "INFO"
Write-Log "Comptes désactivés: $deactivatedCount" -Level "INFO"
Write-Log "Comptes protégés ignorés: $protectedCount" -Level "INFO"

if ($IncludeExpiringAccounts) {
    Write-Log "=== MODE ÉTENDU - COMPTES AVEC EXPIRATION ===" -Level "INFO"
    Write-Log "Comptes avec expiration future: $($ExpiringAccountsTable.Count)" -Level "INFO"
    Write-Log "Comptes expirés encore actifs: $($ExpiredAccountsTable.Count)" -Level "INFO"
    
    if ($ExpiredAccountsTable.Count -gt 0) {
        Write-Log "⚠️  ATTENTION: Des comptes expirés sont encore actifs et nécessitent une vérification manuelle" -Level "WARNING"
    }
}

Write-Log "Script terminé avec succès" -Level "INFO"

if ($DebugMode) {
    Write-Log "Résumé debug des tables:" -Level "DEBUG"
    if ($InactiveAccountsTable.Count -gt 0) {
        $InactiveAccountsTable | Format-Table -AutoSize | Out-String | Write-Log -Level "DEBUG"
    }
    if ($IncludeExpiringAccounts -and $ExpiringAccountsTable.Count -gt 0) {
        $ExpiringAccountsTable | Format-Table -AutoSize | Out-String | Write-Log -Level "DEBUG"
    }
    if ($IncludeExpiringAccounts -and $ExpiredAccountsTable.Count -gt 0) {
        $ExpiredAccountsTable | Format-Table -AutoSize | Out-String | Write-Log -Level "DEBUG"
    }
}

#endregion