Import-Module .\Invoke-Golang.psm1

$Version = "1.14.4"

Invoke-Golang -List Remote
Invoke-Golang -Get $Version
Invoke-Golang -Install $Version
Invoke-Golang -List Local
Invoke-Golang -Remove $Version