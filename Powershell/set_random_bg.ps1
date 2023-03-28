$SettingPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$ImagePath = "PATH\TO\IMAGES"
$PowershellSettings = Get-Content $SettingPath -Raw | ConvertFrom-Json

function Get-Random-Image {
    $RandomImage = (Get-ChildItem $ImagePath | Get-Random -Count 1).FullName
    $Image = New-Object System.Drawing.Bitmap $RandomImage

    return @($RandomImage, $Image)
}

function Get-Image-For-Background {
    $Picked = Get-Random-Image
    $File = $Picked[0]
    $Image = $Picked[1]
    
    while ($Image.Height -gt $Image.Width) {
        $NewFile = Get-Random-Image
        $File = $NewFile[0]
        $Image = $NewFile[1]
    }

    return $File
}

foreach ($item in $PowershellSettings.profiles.defaults) {
    # Skip WSL Settings
    if ($item.name -ne $WSLname) {
        continue
    }

    if ($item.PSObject.Properties.Item('backgroundImage')) {
        $RandomImage = Get-Image-For-Background

        $item.backgroundImage = $RandomImage

        break
    }
}


$PowershellSettings | ConvertTo-Json -Depth 32 | Set-Content $SettingPath
