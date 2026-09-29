Import-Module (Join-Path $PSScriptRoot '../Invoke-Golang.psm1') -Force

Describe 'Invoke-Golang module' {
  It 'exports only the public command' {
    @((Get-Module Invoke-Golang).ExportedCommands.Keys) | Should -Be @('Invoke-Golang')
  }

  It 'rejects invalid versions before changing anything' {
    { Invoke-Golang -Install '1.14.4-invalid' } | Should -Throw
  }
}

InModuleScope Invoke-Golang {
  Describe 'Get-GolangLocalPackage' {
    It 'works without an active Go link or go executable' {
      Mock Get-Item { $null }
      Mock Get-ChildItem { @() }

      Get-GolangLocalPackage | Should -BeNullOrEmpty
      Should -Invoke Get-ChildItem -Times 1
    }
  }

  Describe 'Install-GolangPackage' {
    BeforeEach {
      Mock Invoke-GolangEnvirment {}
      Mock New-Item {}
      Mock Get-GolangCurrent { '1.14.4' }
    }

    It 'does not change the environment or link if a download fails' {
      Mock Test-GolangInstall { $false }
      Mock Get-GolangPackage {}

      { Install-GolangPackage -Version '1.14.4' } | Should -Throw '*not installed*'
      Should -Invoke Get-GolangPackage -Times 1
      Should -Invoke Invoke-GolangEnvirment -Times 0
      Should -Invoke New-Item -Times 0
    }

    It 'downloads a missing version before activating it' {
      $script:installed = $false
      Mock Test-GolangInstall { $script:installed }
      Mock Get-GolangPackage { $script:installed = $true }

      Install-GolangPackage -Version '1.14.4' | Should -Be 'Install 1.14.4 is finished'
      Should -Invoke Get-GolangPackage -Times 1
      Should -Invoke Invoke-GolangEnvirment -Times 1
      Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq 'SymbolicLink' }
    }

    It 'switches to an already installed version without downloading' {
      Mock Test-GolangInstall { $true }
      Mock Get-GolangPackage {}

      Install-GolangPackage -Version '1.14.4' | Should -Be 'Install 1.14.4 is finished'
      Should -Invoke Get-GolangPackage -Times 0
      Should -Invoke New-Item -Times 1 -ParameterFilter { $ItemType -eq 'SymbolicLink' }
    }
  }
}
