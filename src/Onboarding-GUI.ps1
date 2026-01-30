<#
.SYNOPSIS
  Onboarding GUI (Sanitised Template / Portfolio Edition)

.DESCRIPTION
  GitHub-safe onboarding GUI template that demonstrates:
  - Config-driven onboarding inputs (company, office, department)
  - Auto-generated email/UPN logic
  - Dynamic group + license selection based on config
  - DemoMode to run without AD/M365 connectivity

SECURITY / PORTFOLIO NOTE
  - Do NOT commit config/config.json (real values)
  - Commit ONLY config/config.example.json
  - This script is designed so real environment values live only in config.json

QUICK START
  1) Copy config/config.example.json -> config/config.json
  2) Run:
       pwsh -ExecutionPolicy Bypass -File .\src\Onboarding-GUI.ps1
     or:
       pwsh -ExecutionPolicy Bypass -File .\src\Onboarding-GUI.ps1 -DemoMode

AUTHOR
  Teresa Fares (sanitised / portfolio edition)
#>

[CmdletBinding()]
param(
    [switch]$DemoMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ----------------------------
# Paths + Config Loading
# ----------------------------
$RepoRoot   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ConfigPath = Join-Path $RepoRoot "config\config.json"

if (-not (Test-Path $ConfigPath)) {
    throw "Missing config/config.json. Copy 'config/config.example.json' to 'config/config.json' and edit locally."
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# If caller didn't pass DemoMode, read default from config
if (-not $PSBoundParameters.ContainsKey("DemoMode")) {
    $DemoMode = [bool]$config.App.DemoModeDefault
}

# ----------------------------
# Helpers
# ----------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")] [string]$Level = "INFO"
    )
    $prefix = "[$Level] "
    Write-Host ($prefix + $Message)
    if ($script:guiStatusText) { $script:guiStatusText.Text = ($prefix + $Message) }
}

function Update-Gui {
    if ($script:window -and $script:window.Dispatcher) {
        $script:window.Dispatcher.Invoke([Windows.Threading.DispatcherPriority]::Background, [action] {})
    }
}

function StatusUpdate {
    param([string]$Text, [int]$Progress = 0)
    if ($script:guiStatusText) { $script:guiStatusText.Text = $Text }
    if ($script:guiProgressBar) { $script:guiProgressBar.Value = $Progress }
    Update-Gui
}

function Confirm-YesNo {
    param([string]$Text, [string]$Title = "Confirm")
    [void][reflection.assembly]::LoadWithPartialName("PresentationFramework")
    $result = [System.Windows.MessageBox]::Show($Text, $Title, "YesNo", "Question")
    return ($result -eq "Yes")
}

function Get-SamAccountNameFromName {
    param([string]$FirstName, [string]$LastName)
    return (($FirstName + "." + $LastName) -replace "\s", "").ToLower().Trim()
}

function Safe-GetConfigMapValue {
    param($Map, [string]$Key)
    if ($null -eq $Map) { return $null }
    return $Map.PSObject.Properties[$Key].Value
}

# ----------------------------
# Modules (Real Mode Only)
# ----------------------------
function Ensure-Modules {
    if ($DemoMode) {
        Write-Log "DemoMode enabled: skipping AD/M365 module checks." "WARN"
        return
    }

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "ActiveDirectory module not found. Install RSAT or run on a management host."
    }
    Import-Module ActiveDirectory -ErrorAction Stop

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
        throw "Microsoft Graph SDK not found. Install Microsoft.Graph modules."
    }

    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        throw "ExchangeOnlineManagement module not found."
    }
}

function Connect-Services {
    <#
      Connect to Graph + EXO (Real Mode).
      In DemoMode: simulate success so the UI works for anyone.
    #>
    if ($DemoMode) {
        StatusUpdate "DemoMode: simulated sign-in success." 10
        $script:signedIn = $true
        return
    }

    $username = $script:guiO365Username.Text
    $secure   = $script:guiO365Password.SecurePassword

    if ([string]::IsNullOrWhiteSpace($username) -or $null -eq $secure) {
        throw "Enter O365 username/password."
    }

    $cred = New-Object System.Management.Automation.PSCredential ($username, $secure)

    StatusUpdate "Connecting to Microsoft Graph..." 10
    Connect-MgGraph -Scopes $config.M365.GraphScopes -TenantId $config.M365.TenantId -NoWelcome

    StatusUpdate "Connecting to Exchange Online..." 30
    Connect-ExchangeOnline -Credential $cred

    StatusUpdate "Connected." 40
    $script:signedIn = $true
}

# ----------------------------
# Config-derived lists
# ----------------------------
$OfficeNames     = @($config.Offices.PSObject.Properties.Name)
$CompanyNames    = @($config.Companies.PSObject.Properties.Name)
$DepartmentNames = @($config.Departments)

# ----------------------------
# UI logic
# ----------------------------
function Update-EmailAndUpn {
    $first = $script:guiFirstName.Text
    $last  = $script:guiLastName.Text

    if ([string]::IsNullOrWhiteSpace($first) -or [string]::IsNullOrWhiteSpace($last)) {
        $script:guiEmail.Text = ""
        $script:guiUPNBox.Text = ""
        return
    }

    $sam = Get-SamAccountNameFromName -FirstName $first -LastName $last
    $company = $script:guiCompanyCombo.SelectedItem
    if ([string]::IsNullOrWhiteSpace($company)) { $company = $CompanyNames[0] }

    $domain = Safe-GetConfigMapValue -Map $config.Companies -Key $company
    if ([string]::IsNullOrWhiteSpace($domain)) { $domain = "example.com" }

    $script:guiEmail.Text  = "$sam@$domain"
    $script:guiUPNBox.Text = "$sam@"

    if ($script:guiUPNCheck.IsChecked -ne $true) {
        $script:guiUPNCombo.SelectedItem = $domain
    }
}

function Build-DefaultGroups {
    $groups = @()

    $groups += @($config.Groups.Global)

    $company = $script:guiCompanyCombo.SelectedItem
    $office  = $script:guiOfficeCombo.SelectedItem
    $dept    = $script:guiDepCombo.SelectedItem

    if ($company) {
        $companyGroups = Safe-GetConfigMapValue -Map $config.Groups.Company -Key $company
        if ($companyGroups) { $groups += @($companyGroups) }
    }
    if ($office) {
        $officeGroups = Safe-GetConfigMapValue -Map $config.Groups.Office -Key $office
        if ($officeGroups) { $groups += @($officeGroups) }
    }
    if ($dept) {
        $deptGroups = Safe-GetConfigMapValue -Map $config.Groups.Department -Key $dept
        if ($deptGroups) { $groups += @($deptGroups) }
    }

    $ignore = @($config.Groups.Ignore)
    $groups = $groups | Where-Object { $_ -and ($_ -notin $ignore) } | Select-Object -Unique
    return $groups
}

function Refresh-GroupsListUI {
    $script:guiGroupList.Items.Clear()
    foreach ($g in (Build-DefaultGroups)) { [void]$script:guiGroupList.Items.Add($g) }
}

function Refresh-LicenseListUI {
    $script:guiLicenseList.Items.Clear()

    $company   = $script:guiCompanyCombo.SelectedItem
    $cloudOnly = ($script:guiCloudOnlyCheck.IsChecked -eq $true)

    if ($cloudOnly) {
        foreach ($l in $config.Licenses.CloudOnlyDefaults) { [void]$script:guiLicenseList.Items.Add($l) }
        return
    }

    if ($company -and ($config.Licenses.CompanyDefaults.PSObject.Properties.Name -contains $company)) {
        foreach ($l in $config.Licenses.CompanyDefaults.$company) { [void]$script:guiLicenseList.Items.Add($l) }
        return
    }

    foreach ($l in $config.Licenses.Defaults) { [void]$script:guiLicenseList.Items.Add($l) }
}

function Validate-Fields {
    $missing = @()
    if ([string]::IsNullOrWhiteSpace($script:guiFirstName.Text)) { $missing += "First Name" }
    if ([string]::IsNullOrWhiteSpace($script:guiLastName.Text))  { $missing += "Last Name" }
    if ([string]::IsNullOrWhiteSpace($script:guiEmail.Text))     { $missing += "Email" }
    if ($script:guiOfficeCombo.SelectedIndex -eq -1)             { $missing += "Office" }
    if ($script:guiCompanyCombo.SelectedIndex -eq -1)            { $missing += "Company" }
    if ($script:guiDepCombo.SelectedIndex -eq -1)                { $missing += "Department" }

    if ($missing.Count -gt 0) {
        [void][System.Windows.MessageBox]::Show("Missing: $($missing -join ', ')", "Validation", "OK", "Warning")
        return $false
    }
    return $true
}

function Clear-All {
    $script:guiFirstName.Text = ""
    $script:guiLastName.Text = ""
    $script:guiJobTitle.Text = ""
    $script:guiMobileBox.Text = ""

    $script:guiCompanyCombo.SelectedIndex = -1
    $script:guiDepCombo.SelectedIndex = -1
    $script:guiOfficeCombo.SelectedIndex = -1

    $script:guiGroupList.Items.Clear()
    $script:guiLicenseList.Items.Clear()

    $script:guiCloudOnlyCheck.IsChecked = $false
    $script:guiUPNCheck.IsChecked = $false
    $script:guiUPNCombo.SelectedIndex = -1

    Update-EmailAndUpn
    StatusUpdate "Cleared." 0
}

function Provision-User {
    if (-not (Validate-Fields)) { return }

    if (-not $script:signedIn -and -not $DemoMode) {
        [void][System.Windows.MessageBox]::Show("Please sign in first.", "Not signed in", "OK", "Warning")
        return
    }

    $first   = $script:guiFirstName.Text.Trim()
    $last    = $script:guiLastName.Text.Trim()
    $sam     = Get-SamAccountNameFromName -FirstName $first -LastName $last
    $email   = $script:guiEmail.Text.Trim()
    $upn     = ($script:guiUPNBox.Text + $script:guiUPNCombo.SelectedItem).ToLower()
    $office  = $script:guiOfficeCombo.SelectedItem
    $dept    = $script:guiDepCombo.SelectedItem
    $company = $script:guiCompanyCombo.SelectedItem
    $job     = $script:guiJobTitle.Text.Trim()
    $mobile  = $script:guiMobileBox.Text.Trim()

    $groups   = @($script:guiGroupList.Items)
    $licenses = @($script:guiLicenseList.Items)

    $summary = @"
SAM:      $sam
UPN:      $upn
Email:    $email
Name:     $first $last
Company:  $company
Office:   $office
Dept:     $dept
Title:    $job
Mobile:   $mobile

Groups:
 - $($groups -join "`n - ")

Licenses:
 - $($licenses -join "`n - ")

Mode: DemoMode=$DemoMode
"@

    if (-not (Confirm-YesNo -Text $summary -Title "Confirm Provisioning")) {
        Write-Log "Provisioning cancelled." "WARN"
        StatusUpdate "Cancelled." 0
        return
    }

    Ensure-Modules

    if ($DemoMode) {
        StatusUpdate "Demo: simulate AD user creation..." 30
        Start-Sleep -Milliseconds 400

        StatusUpdate "Demo: simulate group assignment..." 60
        Start-Sleep -Milliseconds 400

        StatusUpdate "Demo: simulate license assignment..." 85
        Start-Sleep -Milliseconds 400

        StatusUpdate "Demo complete. No changes made." 100
        Write-Log "DemoMode complete: no AD/M365 actions executed." "SUCCESS"
        return
    }

    # REAL MODE (scaffold):
    # Put your environment-specific implementation here, reading values from config.json.
    # Keep secrets out of the repo.

    $ouPath = $config.AD.DefaultOU

    StatusUpdate "Checking if user exists..." 10
    $existing = Get-ADUser -Filter "samAccountName -eq '$sam'" -ErrorAction SilentlyContinue
    if ($existing) { throw "User '$sam' already exists." }

    StatusUpdate "Creating user in AD..." 35

    # Portfolio-safe approach: generate random temp password + force change at logon
    Add-Type -AssemblyName System.Web
    $plainPw  = [System.Web.Security.Membership]::GeneratePassword(14,3)
    $securePw = ConvertTo-SecureString -AsPlainText $plainPw -Force

    New-ADUser `
        -SamAccountName $sam `
        -UserPrincipalName $upn `
        -GivenName $first `
        -Surname $last `
        -Name "$first $last" `
        -DisplayName "$first $last" `
        -EmailAddress $email `
        -Title $job `
        -Office $office `
        -Department $dept `
        -Company $company `
        -MobilePhone $mobile `
        -Path $ouPath `
        -AccountPassword $securePw `
        -Enabled $true `
        -ChangePasswordAtLogon $true

    StatusUpdate "Adding groups..." 60
    foreach ($g in $groups) {
        Add-ADGroupMember -Identity $g -Members $sam
    }

    # M365 licensing would go here (Graph SKU mapping etc.)
    StatusUpdate "Licensing placeholder..." 85

    StatusUpdate "Provisioning complete." 100
    Write-Log "User provisioned successfully." "SUCCESS"

    [void][System.Windows.MessageBox]::Show(
        "Temporary password (shown once): $plainPw`nUser must change at first sign-in.",
        "Temp Password",
        "OK",
        "Information"
    )
}

# ----------------------------
# WPF UI (embedded XAML)
# ----------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Onboarding GUI (Sanitised Template)" Height="610" Width="860"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Login -->
    <Border Grid.Row="0" BorderBrush="Black" BorderThickness="1" CornerRadius="4" Padding="10" Margin="0,0,0,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0" Margin="0,0,10,0">
          <TextBlock Text="O365 Username"/>
          <TextBox Name="O365Username" Height="26"/>
        </StackPanel>

        <StackPanel Grid.Column="1" Margin="0,0,10,0">
          <TextBlock Text="O365 Password"/>
          <PasswordBox Name="O365Password" Height="26"/>
        </StackPanel>

        <Button Grid.Column="2" Name="O365Login" Content="Sign in" Height="26" Width="120" VerticalAlignment="Bottom"/>
      </Grid>
    </Border>

    <!-- Main -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="420"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Left form -->
      <Border Grid.Column="0" BorderBrush="Black" BorderThickness="1" CornerRadius="4" Padding="10" Margin="0,0,10,0">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <Grid Grid.Row="0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="90"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="First Name" VerticalAlignment="Center"/>
            <TextBox Grid.Column="1" Name="FirstName" Height="26"/>
          </Grid>

          <Grid Grid.Row="1" Margin="0,6,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="90"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Last Name" VerticalAlignment="Center"/>
            <TextBox Grid.Column="1" Name="LastName" Height="26"/>
          </Grid>

          <Grid Grid.Row="2" Margin="0,6,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="90"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Job Title" VerticalAlignment="Center"/>
            <TextBox Grid.Column="1" Name="JobTitle" Height="26"/>
          </Grid>

          <Grid Grid.Row="3" Margin="0,6,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="90"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Mobile" VerticalAlignment="Center"/>
            <TextBox Grid.Column="1" Name="MobileBox" Height="26"/>
          </Grid>

          <Grid Grid.Row="4" Margin="0,10,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="90"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Office" VerticalAlignment="Center"/>
            <ComboBox Grid.Column="1" Name="OfficeCombo" Height="26"/>
          </Grid>

          <Grid Grid.Row="5" Margin="0,6,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="90"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Company" VerticalAlignment="Center"/>
            <ComboBox Grid.Column="1" Name="CompanyCombo" Height="26"/>
          </Grid>

          <Grid Grid.Row="6" Margin="0,6,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="90"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Department" VerticalAlignment="Center"/>
            <ComboBox Grid.Column="1" Name="DepCombo" Height="26"/>
          </Grid>

          <Grid Grid.Row="7" Margin="0,10,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="90"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="Email" VerticalAlignment="Center"/>
            <TextBox Grid.Column="1" Name="Email" Height="26" IsReadOnly="True"/>
          </Grid>

          <Grid Grid.Row="8" Margin="0,6,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="90"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="UPN" VerticalAlignment="Center"/>
            <TextBox Grid.Column="1" Name="UPNBox" Height="26" IsReadOnly="True"/>
            <ComboBox Grid.Column="2" Name="UPNCombo" Height="26" Width="160" Margin="6,0,0,0"/>
          </Grid>

          <StackPanel Grid.Row="9" Orientation="Horizontal" Margin="0,14,0,0">
            <CheckBox Name="CloudOnlyCheck" Content="Cloud Only" Margin="0,0,10,0"/>
            <CheckBox Name="UPNCheck" Content="Allow UPN change"/>
            <Button Name="ClearAll" Content="Clear" Width="90" Margin="20,0,0,0"/>
          </StackPanel>
        </Grid>
      </Border>

      <!-- Right: lists + actions -->
      <Border Grid.Column="1" BorderBrush="Black" BorderThickness="1" CornerRadius="4" Padding="10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <TextBlock Grid.Row="0" Text="Licenses" FontWeight="Bold"/>
          <ListBox Grid.Row="1" Name="LicenseList" Margin="0,6,0,10"/>

          <TextBlock Grid.Row="2" Text="Groups" FontWeight="Bold"/>
          <ListBox Grid.Row="3" Name="GroupList" Margin="0,6,0,10"/>

          <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="OnboardUser" Content="Provision User" Width="140" Height="30"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Status -->
    <Grid Grid.Row="2" Margin="0,10,0,0">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <ProgressBar Name="ProgressBar" Grid.Row="0" Height="18"/>
      <TextBlock Name="StatusText" Grid.Row="1" Text="Awaiting user input..." HorizontalAlignment="Center" Margin="0,6,0,0"/>
    </Grid>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:window = [Windows.Markup.XamlReader]::Load($reader)

# Bind controls to script vars
$xaml.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name ("gui" + $_.Name) -Value $script:window.FindName($_.Name) -Scope Script
}

# Populate dropdowns
foreach ($o in $OfficeNames) { [void]$script:guiOfficeCombo.Items.Add($o) }
foreach ($c in $CompanyNames) { [void]$script:guiCompanyCombo.Items.Add($c) }
foreach ($d in $DepartmentNames) { [void]$script:guiDepCombo.Items.Add($d) }

# Populate UPN domains from Companies
foreach ($c in $CompanyNames) {
    $domain = Safe-GetConfigMapValue -Map $config.Companies -Key $c
    if ($domain -and ($script:guiUPNCombo.Items -notcontains $domain)) {
        [void]$script:guiUPNCombo.Items.Add($domain)
    }
}

# Default state
$script:signedIn = $false
$script:guiUPNCombo.IsEnabled = $false

# Events
$script:guiO365Login.Add_Click({
    try {
        Connect-Services
        [void][System.Windows.MessageBox]::Show("Signed in (or demo).", "Success", "OK", "Information")
        StatusUpdate "Signed in - ready." 0
    } catch {
        Write-Log $_.Exception.Message "ERROR"
        StatusUpdate "Sign-in failed." 0
        [void][System.Windows.MessageBox]::Show($_.Exception.Message, "Sign-in failed", "OK", "Error")
    }
})

$script:guiFirstName.Add_TextChanged({ Update-EmailAndUpn })
$script:guiLastName.Add_TextChanged({ Update-EmailAndUpn })

$script:guiCompanyCombo.Add_SelectionChanged({
    Update-EmailAndUpn
    Refresh-GroupsListUI
    Refresh-LicenseListUI
})

$script:guiOfficeCombo.Add_SelectionChanged({ Refresh-GroupsListUI })
$script:guiDepCombo.Add_SelectionChanged({ Refresh-GroupsListUI })

$script:guiCloudOnlyCheck.Add_Checked({
    Refresh-LicenseListUI
    Refresh-GroupsListUI
})
$script:guiCloudOnlyCheck.Add_Unchecked({
    Refresh-LicenseListUI
    Refresh-GroupsListUI
})

$script:guiUPNCheck.Add_Checked({ $script:guiUPNCombo.IsEnabled = $true })
$script:guiUPNCheck.Add_Unchecked({
    $script:guiUPNCombo.IsEnabled = $false
    try {
        $company = $script:guiCompanyCombo.SelectedItem
        if ($company) {
            $script:guiUPNCombo.SelectedItem = Safe-GetConfigMapValue -Map $config.Companies -Key $company
        }
    } catch {}
})

$script:guiClearAll.Add_Click({
    Clear-All
    Refresh-LicenseListUI
    Refresh-GroupsListUI
})

$script:guiOnboardUser.Add_Click({
    try {
        Provision-User
    } catch {
        Write-Log $_.Exception.Message "ERROR"
        [void][System.Windows.MessageBox]::Show($_.Exception.Message, "Provisioning failed", "OK", "Error")
        StatusUpdate "Provisioning failed." 0
    }
})

# Initial draw
Refresh-LicenseListUI
Refresh-GroupsListUI
Update-EmailAndUpn

Write-Log "Launching UI. DemoMode=$DemoMode" "INFO"
[void]$script:window.ShowDialog()
