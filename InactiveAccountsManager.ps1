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

    [switch]$DebugMode,

    [switch]$DryRun
)

# Script version
$scriptVersion = "2.1.1"
Add-Type -AssemblyName System.Web

# Changelog
# v2.1.1 - Add default templates path and configuration file check and load

<#
.SYNOPSIS
    Manage inactive Active Directory accounts.

.DESCRIPTION
    This script identifies inactive Active Directory accounts and:
    - Sends daily notifications to users and admins 15 days before disabling the accounts.
    - Automatically disables accounts after 45 days of inactivity.
    - Updates the "description" field of disabled accounts to include the date of deactivation.
    - Constructs a table (InactiveAccountsTable) to track user details and actions.

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
    Number of days of inactivity before accounts are considered for deactivation.

.PARAMETER NotificationDays
    Number of days before to deactivate to notify.

.PARAMETER DebugMode
    Enable debug mode. Outputs logs to the console instead of a log file.

.PARAMETER DryRun
    Simulate actions without making changes to Active Directory.

.EXAMPLE
    .\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" `
        -EmailFrom "no-reply@example.com" -TemplatesPath "C:\templates" -EnableLog

.NOTES
    Script version: 2.1.0
    Author: Philippe Candido (philippe.candido@emerging-it.fr)
#>

# Global settings
$InactivityThreshold = (Get-Date).AddDays(-$InactivityDays)
$NotificationThreshold = (Get-Date).AddDays(-$InactivityDays + $NotificationDays)

# Get the current date
$CurrentDate = Get-Date -Format "dd-MM-yyyy HH:mm:ss"

# Logging function
function Write-Log {
    param ([string]$Message)
    $timestamp = (Get-Date).ToString("yyyyMMdd-HH:mm:ss")
    if ($DebugMode) {
        Write-Host "[$timestamp] $Message"
    } elseif ($EnableLog) {
        Add-Content -Path "$PSScriptRoot\InactiveAccountsManager.log" -Value "[$timestamp] $Message"
    }
}

# Template rendering function
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

    $TemplateContent = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
    foreach ($Key in $Variables.Keys) {
        $TemplateContent = $TemplateContent -replace "{{\s*$Key\s*}}", $Variables[$Key]
    }
    return $TemplateContent
}

# Secure email sending function
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
        Write-Log "Dry-run mode: Email to $($To -join ', ') simulated."
        return
    }

    try {
        $SMTP = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        $SMTP.EnableSsl = $SmtpSSL

        # Use credentials xml file if available, else use provided credentials
        if ($smtpAuth) {
            if ($credential) {
                $SMTP.Credentials = $credential.GetNetworkCredential()
            } elseif ($Username -and $Password) {
                $SMTP.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
            } else {
                throw "Aucune information d'identification SMTP n'a été fournie."
            }
        }
        
        $MailMessage = New-Object System.Net.Mail.MailMessage
        $mailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8
        $mailMessage.BodyEncoding = [System.Text.Encoding]::UTF8
        $MailMessage.From = $From
        foreach ($Recipient in $To) {
            $MailMessage.To.Add($Recipient)
        }
        
        $MailMessage.Subject = $Subject
        $MailMessage.Body = $Body
        $MailMessage.IsBodyHtml = $true

        # Create a logo attachment
        if ($embeddedImages) {
            $Attachment = New-Object Net.Mail.Attachment($LogoPath)
            $Attachment.ContentId = "logo-image"
            $mailMessage.Attachments.Add($Attachment)
        } 

        if ($DebugMode) {
            Write-Host "[DEBUG] Preparing to send email: Subject='$Subject', To='$($To -join ', ')' "
        }

        $SMTP.Send($MailMessage)
        Write-Log "Email sent to: $($To -join ', ')"

    } catch {
        Write-Log "Failed to send email. Error: $_"
        if ($DebugMode) {
            Write-Host "[DEBUG] Error encountered during email sending: $_"
        }
        throw $_
    }
}

# Fetch inactive accounts
Write-Log "Identifying inactive accounts..."
if ($DebugMode) {
    Write-Host "[DEBUG] Inactivity Threshold: "$InactivityThreshold.ToString("yyyy/MM/dd-HH:mm:ss")
    Write-Host "[DEBUG] Notification Threshold: "$NotificationThreshold.ToString("yyyy/MM/dd-HH:mm:ss")
}

## Main script logic
# Get configuration file
$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath "config.ps1"
if (-not (Test-Path -Path $ConfigFile)) {
    Write-Error "Configuration file not found. Script aborted."
    exit 1
}

try {
    . $ConfigFile
    $phoneSupportHref = $phoneSupport.Replace(" ", "")
    Write-Host "Configuration file loaded successfully."
} catch {
    Write-Error "Configuration cannot be loaded. Error : $_"
    exit 1
}

if (-not $emailSupport -or -not $phoneSupport -or -not $urlSupport) {
    Write-Error "Mandatories variables emailSupport, phoneSupport, urlSupport are missing in $ConfigFile. Please check file."
    exit 1
}

# Chck if file smtp_credential.xml exists
$credentialFilePath = Join-Path -Path $PSScriptRoot -ChildPath "smtp_credential.xml"
if (Test-Path -Path $credentialFilePath) {
    Write-Log "Chargement des informations d'identification SMTP depuis $credentialFilePath"
    $credential = Import-Clixml -Path $credentialFilePath
} else {
    Write-Log "Aucun fichier smtp_credential.xml trouvé. Utilisation des informations d'identification fournies via les paramètres."
    $credential = $null
}

# HTML templates
if (-not $TemplatesPath) {
    $TemplatesPath = Join-Path -Path $PSScriptRoot -ChildPath "Templates"
}

# HTML templates
$templatePaths = @(
    "$TemplatesPath\UserDesactivationNotification.html",
    "$TemplatesPath\UserDesactivatedNotification.html",
    "$TemplatesPath\logo.png"
)

# Check if templates exist
foreach ($templatePath in $templatePaths) {
    if (-not (Test-Path -Path $templatePath)) {
        Write-Error "File $templatePath not found. Script aborted."
        exit 1
    }
    $LogoPath = Join-Path -Path $TemplatesPath -ChildPath "logo.png"
}

# DebugMode: Display script parameters
if ($DebugMode) {
    Write-Host "[DEBUG] Debug mode activated. Displaying script parameters:"
    Write-Host "[DEBUG]   - AdminEmails      : $($AdminEmails -join ', ')"
    Write-Host "[DEBUG]   - SmtpServer       : $SmtpServer"
    Write-Host "[DEBUG]   - SmtpPort         : $SmtpPort"
    Write-Host "[DEBUG]   - EmailFrom        : $EmailFrom"
    Write-Host "[DEBUG]   - TemplatesPath    : $TemplatesPath"
    Write-Host "[DEBUG]   - Username         : $Username"
    Write-Host "[DEBUG]   - SmtpSSL          : $SmtpSSL"
    Write-Host "[DEBUG]   - EnableLog        : $EnableLog"
    Write-Host "[DEBUG]   - InactivityDays   : $InactivityDays"
    Write-Host "[DEBUG]   - NotificationDays : $NotificationDays"
    Write-Host "[DEBUG]   - DebugMode        : $DebugMode"
    Write-Host "[DEBUG]   - DryRun           : $DryRun"
    Write-Host "[DEBUG] "
    Write-Host "[DEBUG] Calculated thresholds:"
    Write-Host "[DEBUG]   - InactivityThreshold   : "$InactivityThreshold.toString("MM/dd/yyyy-HH:mm:ss")
    Write-Host "[DEBUG]   - NotificationThreshold : "$NotificationThreshold.toString("MM/dd/yyyy-HH:mm:ss")
    Write-Host "[DEBUG] "
}

# Get inactive accounts
$InactiveAccounts = Get-ADUser -Filter {Enabled -eq $true -and LastLogonTimestamp -lt $NotificationThreshold} `
    -Properties DisplayName, SamAccountName, EmailAddress, LastLogonTimestamp, Description | 
    Select-Object DisplayName, SamAccountName, EmailAddress, `
        @{Name="LastLogon";Expression={[datetime]::FromFileTime($_.LastLogonTimestamp)}}, Description   

if ($InactiveAccounts.Count -eq 0) {
    Write-Log "No inactive accounts found."
    # Notify admins
    $AdminBody = Render-Template -TemplatePath "$TemplatesPath\InactiveAccountsReport.html" -Variables @{
        InactivityDays            = $InactivityDays
        InactiveAccountsTableHtml = "<tr><td colspan='5'>No inactive accounts found.</td></tr>"
        ScriptName                = $ScriptName
        Action                    = "deactivated"
        CurrentDate               = $CurrentDate
    }
    Send-SecureMail -To $AdminEmails -From $EmailFrom `
        -Subject "Inactive Accounts Report" -Body $AdminBody `
        -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password ` 
        -SmtpSSL:$SmtpSSL -DryRun:$DryRun -logo $LogoPath

    return
}

if ($DebugMode) {
    Write-Host "[DEBUG] InactiveAccounts details:"
    $InactiveAccounts | Format-Table -AutoSize
}

# Initialize the table of inactive accounts
$InactiveAccountsTable = @()

# Get script name
$ScriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path

# Get the current date
$CurrentDate = Get-Date

# Disable accounts
foreach ($Account in $InactiveAccounts) {
    if ($DebugMode) { Write-Host "[DEBUG]" }
    if ($DebugMode) { Write-Host "[DEBUG] # Account $($Account.SamAccountName)" }
    # Calculate inactive days and deactivation date
    $DaysRemaining = [math]::Ceiling(($Account.LastLogon - $InactivityThreshold).TotalDays)
    $DaysInactive =  [math]::Floor(($CurrentDate - $Account.LastLogon).TotalDays)

    if ($DebugMode) { Write-Host "[DEBUG]   - DaysRemaining : $DaysRemaining" }
    if ($DebugMode) { Write-Host "[DEBUG]   - DaysInactive $DaysInactive" }

    $InactiveAccountsTable += [PSCustomObject]@{
        SamAccountName    = $Account.SamAccountName
        EmailAddress      = $Account.EmailAddress
        LastLogon         = $Account.LastLogon
        Action            = $null
        DaysInactive      = $DaysInactive
        DaysRemaining      = $DaysRemaining
    }

    # Check if the account is protected
    if ($DebugMode) { Write-Host "[DEBUG]  ## Check if the account $($Account.SamAccountName) is protected" }
    if ($Account.Description -like "*//ACCOUNT_PROTECTED//*") {
        Write-Log "Account $($Account.SamAccountName) is protected and will not be disabled."

        # Update Action in the table
        $Row = $InactiveAccountsTable | Where-Object { $_.SamAccountName -eq $Account.SamAccountName }
        if ($Row) {
            $Row.Action = "protected"
            $Row.DaysInactive = $DaysInactive
        }
        if ($DebugMode) { Write-Host "[DEBUG]" }
        continue
    } else {
        if ($DebugMode) { Write-Host "[DEBUG]   - Account is not protected" }
    }

    # Check if the DaysRemaining is less or equal to NotificationDays
    if ($DebugMode) { Write-Host "[DEBUG]  ## Check if the DaysRemaining is less or equal to NotificationDays" }
    if ($DaysRemaining -le $NotificationDays) {
        # Notify the user
        if ($Account.EmailAddress) {
            if ($DebugMode) { Write-Host "[DEBUG]  - The account $($Account.SamAccountName) has an email address" }
            # Check if the DaysRemaining is less or equal to 0
            if ($DaysRemaining -le 0) {
                $subject = "Attention votre compte a été déassactivé"
                $UserBody = Render-Template -TemplatePath "$TemplatesPath\UserDesactivatedNotification.html" -Variables @{
                    DisplayName       = $Account.DisplayName
                    LastLogon         = $Account.LastLogon.ToString("dd MMMM yyyy HH:mm:ss")
                    InactivityDays    = $InactivityDays
                    ScriptName        = $ScriptName
                    DaysRemaining     = $DaysRemaining
                    DaysInactive      = $DaysInactive
                    phoneSupport      = $phoneSupport
                    phoneSupportHref  = $phoneSupportHref
                    urlSupport        = $urlSupport
                    emailSupport      = $emailSupport
                }
            } else {
                $subject = "Avertissement avant désactivation de votre compte"
                $UserBody = Render-Template -TemplatePath "$TemplatesPath\UserDesactivationNotification.html" -Variables @{
                    DisplayName       = $Account.DisplayName
                    LastLogon         = $Account.LastLogon.ToString("dd MMMM yyyy HH:mm:ss")
                    InactivityDays    = $InactivityDays
                    ScriptName        = $ScriptName
                    DaysRemaining     = $DaysRemaining
                    DaysInactive      = $DaysInactive
                    phoneSupport      = $phoneSupport
                    phoneSupportHref  = $phoneSupportHref
                    urlSupport        = $urlSupport
                    emailSupport      = $emailSupport
                }
            }
    
            if ($DryRun) {
                Write-Host "[DRY-RUN] Account $($Account.SamAccountName) will be notified with variables :"
                Write-Host "[DRY-RUN]   - DisplayName    :" $Account.DisplayName
                Write-Host "[DRY-RUN]   - LastLogon      :" $Account.LastLogon.ToString("dd MMMM yyyy HH:mm:ss")
                Write-Host "[DRY-RUN]   - InactivityDays :" $InactivityDays
                Write-Host "[DRY-RUN]   - DaysRemaining  :" $DaysRemaining
                Write-Host "[DRY-RUN]   - DaysInactive   :" $DaysInactive
            } else {
                Send-SecureMail -To $Account.EmailAddress -From $EmailFrom `
                -Subject $subject -Body $UserBody `
                -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password `
                -SmtpSSL:$SmtpSSL -DryRun:$DryRun -logo $LogoPath
            }
           
            # Update DaysInactive and in Action the table InactiveAccountsTable
            $Row = $InactiveAccountsTable | Where-Object { $_.SamAccountName -eq $Account.SamAccountName }
            if ($Row) {
                $Row.DaysInactive = $DaysInactive
                $Row.Action = "notified"
                if ($DebugMode) { Write-Host "[DEBUG]   - Action   : notified" }
            }
        } else {
            Write-Log "No email address found for account $($Account.DisplayName)"
        }
    }
    
    # Check if the DaysRemaining is less or equal to 0
    if ($DebugMode) { Write-Host "[DEBUG]  ## Check DaysRemaining value for account $($Account.DisplayName)" }
    if ($DaysRemaining -le 0) {
        if ($DebugMode) { Write-Host "[DEBUG]   - DaysRemaining ($($DaysRemaining)) <= 0" }

        # Update description and disable account
        if ($DebugMode) { Write-Host "[DEBUG]  ## Check the description for account $($Account.DisplayName)" }

        $UpdatedDescription = if ($Account.Description -notlike "*| Disabled at*") {
            "$($Account.Description) | Disabled at $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")"
        } else {
            $Account.Description
        }

        if ($DryRun) {
            Write-Host "[DRY-RUN] Account $($Account.SamAccountName) will be disabled."
        } else {
            if ($DebugMode) { Write-Host "[DEBUG]   - Account $($Account.SamAccountName) is inactive since $($Account.LastLogon), and will be disabled."
                Write-Host "[DEBUG]   - Update the description of the account to: $UpdatedDescription"
            }
            Set-ADUser -Identity $Account.SamAccountName -Enabled $false -Description $UpdatedDescription
            if ($DebugMode) { 
                Write-Host "[DEBUG]   - Account $($Account.SamAccountName) is inactive since $($Account.LastLogon), and will be disabled."
                Write-Host "[DEBUG]   - Update the description of the account to: $UpdatedDescription"
            }
            Write-Log "Disabled account: $($Account.SamAccountName)"
        }

        # Update Action in the table
        $Row = $InactiveAccountsTable | Where-Object { $_.SamAccountName -eq $Account.SamAccountName }
        if ($Row) {
            $Row.Action = "deactivated"
            $Row.DaysInactive = [math]::Floor(($CurrentDate - $Account.LastLogon).TotalDays)
            if ($DebugMode) { Write-Host "[DEBUG]   - Update the Action value with : "$Row.Action }
        }

    }
}

# Generate the HTML table for admin report
$InactiveAccountsTableHtml = ""
Write-Log "Generate the HTML table for admin report."
if ($InactiveAccountsTable.cout -eq 0) {
    $InactiveAccountsTableHtml = "<tr><td colspan='5'>No inactive accounts found.</td></tr>"
    Write-Log "No inactive accounts found. (InactiveAccountsTable is empty)"
} else {
    foreach ($Row in $InactiveAccountsTable) {
        # if ($Row.Action -eq "protected") {
        #     continue
        # }
        Write-Log "Account $([System.Web.HttpUtility]::HtmlEncode($Row.sAMAccountName)) is inactive since `
        $([System.Web.HttpUtility]::HtmlEncode($Row.LastLogon.ToString('dd/MM/yyyy HH:mm:ss'))), `
        and will be $([System.Web.HttpUtility]::HtmlEncode($Row.Action))."
        $InactiveAccountsTableHtml += "<tr>" +
            "<td style='padding: 10px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.sAMAccountName))</td>" +
            "<td style='padding: 10px; border: 1px solid #ddd;'><a href='mailto:$([System.Web.HttpUtility]::HtmlEncode($Row.EmailAddress))'>$([System.Web.HttpUtility]::HtmlEncode($Row.EmailAddress))</a></td>" +
            "<td style='padding: 10px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.LastLogon.ToString('dd/MM/yyyy HH:mm:ss')))</td>" +
            "<td style='padding: 10px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.DaysInactive))</td>" +
            "<td style='padding: 10px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($Row.Action))</td>" +
            "</tr>"
    }
}


# Notify admins
$AdminBody = Render-Template -TemplatePath "$TemplatesPath\InactiveAccountsReport.html" -Variables @{
    InactivityDays            = $InactivityDays
    InactiveAccountsTableHtml = $InactiveAccountsTableHtml
    ScriptName                = $ScriptName
    Action                    = "deactivated"
    CurrentDate               = $CurrentDate
}

Send-SecureMail -To $AdminEmails -From $EmailFrom `
    -Subject "Inactive Accounts Report" -Body $AdminBody `
    -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password `
    -SmtpSSL:$SmtpSSL -DryRun:$DryRun -logo $LogoPath

    $debugInactiveAccountsTable = $InactiveAccountsTable | Format-Table -AutoSize | Out-String
    Write-Log "InactiveAccountsTable : "
    Write-Log $debugInactiveAccountsTable

Write-Log "Script completed successfully."
