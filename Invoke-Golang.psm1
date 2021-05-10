<#
.SYNOPSIS

Download And Switch Golang Versions

Author: mingcheng (https://github.com/mingcheng/Invoke-Golang)
License: GPL

.DESCRIPTION

This PowerShell script to find and install golang package from golang original website.

.EXAMPLE

After `Import-Module .\Invoke-Golang.psm1`, you can use Invoke-Golang cmdlet within below commands:

List remote avaiable versions or local installed package

> Invoke-Golang -List Remote

or

> Invoke-Golang -List Remote

Download(do not install) golang package specified version

> Invoke-Golang -Get 1.13.8

Download and install specified version of golang package

> Invoke-Golang -Install 1.14.4

Remove specified golang package

> Invoke-Golang -Remove 1.12.17
#>

# Set Golang Envirment
function Invoke-GolangEnvirment {
  $GolangDirectory = "${HOME}/.g"

  if (-not (Test-Path -Path $GolangDirectory -PathType Container)) {
    New-Item -Path $GolangDirectory -ItemType Directory -ErrorAction SilentlyContinue
  }

  $User = [EnvironmentVariableTarget]::User
  $Path = [Environment]::GetEnvironmentVariable('Path', $User)
  if (!(";$Path;".ToLower() -like "*;${GolangDirectory}/go/bin;*".ToLower())) {
    [Environment]::SetEnvironmentVariable('Path', "${GolangDirectory}/go/bin;$Path", $User)
    $Env:Path += ";${GolangDirectory}/go/bin"
    $Env:Path += ";${HOME}/go/bin"
  }

  [Environment]::SetEnvironmentVariable("GOROOT", "${GolangDirectory}/go", $User)
}

function Test-GolangInstall([Parameter(Mandatory = $true)] [ValidatePattern('\d+\.\d+\.*\d*')] [string] $Version) {
  $Path = "${HOME}/.g/versions/${Version}"
  return (Test-Path -Path $Path -PathType Container)
}

function Get-GolangCurrent {
  try {
    $Item = Get-Item "${HOME}/.g/go" -ErrorAction SilentlyContinue
    $Target = [System.IO.Path]::GetFileName($Item.Target)

    $Check = (go version  | Select-String -Pattern $Target)
    if ($Check.Pattern -eq $Target) {
      return $Target
    }
    else {
      throw "Not found"
    }
  }
  catch {
    throw $_
  }
}

function Get-GolangRemotePackage {
  $Uri = "https://golang.org/dl/"
  $TimeoutSec = 10

  $User = [EnvironmentVariableTarget]::User
  $EnvironmentUri = [System.Environment]::GetEnvironmentVariable("GOALNG_PACKAGE_URI", $User)
  if ($EnvironmentUri.Length -gt 0) {
    $Uri = $EnvironmentUri
    Write-Debug "Reset golang package uri from envirment variable ${Uri}"
  }

  Write-Debug "Get golang package list form uri ${Uri} in timeout ${TimeoutSec}"
  try {
    $Response = Invoke-WebRequest -Uri $Uri -TimeoutSec $TimeoutSec -UseDefaultCredentials
    if ($Response.StatusCode -eq 200) {
      $result = @()
      $response.Links | Where-Object {
        $_.href -like "/dl/go*windows-amd64.zip" -and $_.class -eq "download"
      } | ForEach-Object {
        if ( $_.href -match "\/go(\d+\.*\d+\.*\d*).windows-") {
          $obj = New-Object System.Object
          Add-Member -InputObject $obj -MemberType NoteProperty -Name Version -Value $matches[1]
          Add-Member -InputObject $obj -MemberType NoteProperty -Name Uri -Value $_.href
          $result += $obj
        }
      }

      if ($result.Count -gt 0) {
        $result | ForEach-Object {
          if (Test-GolangInstall($_.Version)) {
            Write-Host -ForegroundColor Red "*"$_.Version
          }
          else {
            # example, https://dl.google.com/go/go1.3.3.windows-amd64.zip
            Write-Host $_.Version
          }
        }
      }
      else {
        Write-Error "Can NOT found any install package from ${Uri}"
      }
    }
    else {
      Write-Error "Request remote package infomation error, please check your network connection."
    }
  }
  catch {
    Write-Error "Caught an error durning request for golang package, please check your envirment"
  }
}

function Get-GolangLocalPackage {
  $Target = Get-GolangCurrent

  try {
    Get-ChildItem -Path "${HOME}/.g/versions" -Directory -Depth 0 -ErrorAction SilentlyContinue | ForEach-Object {
      if ($Target -eq $_.Name) {
        Write-Host -ForegroundColor Red "*${Target}"
      }
      else {
        Write-Host $_.Name
      }
    }
  }
  catch {
    Write-Error "List local packages failed, maybe not installed\?"
  }
}

function Get-GolangPackage {
  Param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\d+\.\d+\.*\d*')]
    [string]
    $Version
  )

  if (Test-GolangInstall($Version)) {
    Write-Debug "${Version} is already downloaded"
    return
  }

  $Uri = "https://dl.google.com/go/go${Version}.windows-amd64.zip"
  # $Uri = "https://gomirrors.org/dl/go/go${Version}.windows-amd64.zip"

  $Outfile = $HOME + "/.g/downloads/" + "go${Version}.windows-amd64.zip"
  $DestinationPath = $HOME + "/.g/versions"

  $OutfileDirectory = [System.IO.Path]::GetDirectoryName($Outfile)

  New-Item -Path $OutfileDirectory -Type Directory -Force -ErrorAction SilentlyContinue | Out-Null
  New-Item -Path $DestinationPath -Type Directory -Force -ErrorAction SilentlyContinue | Out-Null

  if (-not (Test-Path -Path $Outfile -PathType Leaf)) {
    try {
      Write-Debug "Get package from ${Uri}"
      # $ProgressPreference = 'SilentlyContinue'
      Invoke-WebRequest -Uri $Uri -OutFile $Outfile -UseDefaultCredentials
    }
    catch {
      Remove-GolangPackage -Version $Version
      Write-Error "Download packge is failed, please check the network."
      return
    }
  }

  try {
    if (-not (Test-Path -PathType Container -Path $DestinationPath)) {
      Write-Debug "${DestinationPath} not exists, try to create"
      New-Item -Path $DestinationPath -ItemType Directory -Force
    }

    # Exanpd downloaded golang package to destination path
    Expand-Archive -LiteralPath $Outfile -DestinationPath $DestinationPath -Force

    # Move to right destination and doing some cleanup
    if (Test-Path -Path "${DestinationPath}/go" -PathType Container) {
      Move-Item -Path "${DestinationPath}/go" -Destination "${DestinationPath}/${Version}" -Force
    }

    Write-Debug "Get ${Version} is finished, everything looks fine."
  }
  catch {
    Remove-GolangPackage -Version $Version
    throw "Expand golang packge with error, abort."
  }
}

function Install-GolangPackage {
  Param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\d+\.\d+\.*\d*')]
    [string]
    $Version
  )

  Invoke-GolangEnvirment | Out-Null

  if (-not (Test-GolangInstall($Version))) {
    Get-Package -Version $Version
  }

  Write-Debug "Create symbolic links"
  New-Item -ItemType SymbolicLink -Path "${HOME}/.g/go" -Value "${HOME}/.g/versions/${Version}" -Force | Out-Null

  # Check
  $Check = (go version  | Select-String -Pattern $Version)
  if ($Check.Pattern -eq $Version) {
    "Install ${Version} is finished"
  }
  else {
    Write-Error "Failed"
  }
}

function Remove-GolangPackage {
  Param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\d+\.\d+\.*\d*')]
    [string]
    $Version
  )

  $Outfile = "${HOME}/.g/downloads/go${Version}.windows-amd64.zip"

  try {
    if (Test-Path -Path $Outfile -PathType Leaf) {
      Write-Debug "Removing package ${Outfile}"
      Remove-Item -Path $Outfile -Confirm:$false -Force
    }

    if (Test-GolangInstall($Version)) {
      Remove-Item -Path "${HOME}/.g/versions/${Version}" -Recurse -Force -Confirm:$false
    }

    "${Version} has removed"
  }
  catch {
    Write-Error "Remove ${Version} caught something error, check your filesystem."
  }
}


<#
.SYNOPSIS

Download And Switch Golang Versions

Author: mingcheng (https://github.com/mingcheng/Invoke-Golang)
License: GPL

.DESCRIPTION

This PowerShell script to find and install golang package from golang original website.

.PARAMETER List

`Remote` list avaiable packages from offical golang website
`Local` list local install packages

.PARAMETER Get

Get and do not install golang package

.PARAMETER Install

Get and install golang package

.PARAMETER Remove

Remove installed golang package
#>
Function Invoke-Golang {
  [CmdletBinding()]

  param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Local", "Remote")]
    [string]
    $List,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('\d+\.\d+\.*\d*')]
    [string]
    $Install,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('\d+\.\d+\.*\d*')]
    [string]
    $Remove,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('\d+\.\d+\.*\d*')]
    [string]
    $Get
  )

  switch ($List) {
    "Remote" {
      Get-GolangRemotePackage
      return
    }

    "Local" {
      Get-GolangLocalPackage
      return
    }
  }

  if ($Get -ne "") {
    Get-GolangPackage -Version $Get
  }

  if ($Install -ne "") {
    Install-GolangPackage  -Version $Install
  }

  if ($Remove -ne "") {
    Remove-GolangPackage -Version $Remove
  }
}

Export-ModuleMember -Function Invoke-Golang
