Function Get-WAUConfig 
{
    #region Default Names and Values
        [string]$ARP_ProductName = 'Winget-AutoUpdate';
        [string]$ARP_Vendor = 'Romanitho';
        [string]$ARP_Subkey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
        [string]$GPO_Subkey = 'SOFTWARE\Policies\Romanitho';
        [string]$setting_prefix = 'WAU_';
    #endregion

    # defining WAUConfig object (it will hold settings from both ARP and GPO subkeys (GPO entries will override ARP entries if defined))
    [psobject]$WAUConfig = [psobject]::new();

    # Setting the HKLM as the starting registry Hive
    [Microsoft.Win32.RegistryHive]$RegHive = [Microsoft.Win32.RegistryHive]::LocalMachine;

    #region opening the registry Hive in x64 view (or default on x86 systems)
        if([System.IntPtr]::Size -eq 8)
        {
            [Microsoft.Win32.RegistryView]$RegView = [Microsoft.Win32.RegistryView]::Registry64;
        } 
        else
        {
            [Microsoft.Win32.RegistryView]$RegView = [Microsoft.Win32.RegistryView]::Default;
        }
        [Microsoft.Win32.RegistryKey]$RegBaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($RegHive, $RegView);
    #endregion

    #region navigating to ARP subkey in opened registry hive
        # I am wrapping it into try-catch here ,because $ARP_Subkey always exists, but AntiViruses are stupid when dealing with PowerShell scripts and sometimes freak out
        try
        {
            [Microsoft.Win32.RegistryKey]$RegARPx64Key = $RegBaseKey.OpenSubKey($ARP_Subkey, $false);
            $reg_Path = "$RegBaseKey\$ARP_Subkey";

            if($null -ne $RegARPx64Key)
            {
                #region navigating to WAU ARP subkey
                    try
                    {
                        [Microsoft.Win32.RegistryKey]$RegARPx64Key_WAU = $RegARPx64Key.OpenSubKey($ARP_ProductName, $false);
                        $reg_Path = "$RegARPx64Key\$ARP_ProductName";

                        if($null -ne $RegARPx64Key_WAU)
                        {
                            # if we managed to open it, then the $RegARPx64Key_WAU IS NOT NULL
                            # we want to exclude ValueNames which are defaults for ARP entries and collect only WAU_* entries;
                            [string[]]$WAU_props = $RegARPx64Key_WAU.GetValueNames() | ? {$_.ToUpperInvariant().StartsWith($setting_prefix)}

                            # double check if we had found anything
                            if($WAU_props.Count -gt 0)
                            {
                                # now we are adding all filtered pairs of name+Value to our custom object
                                $WAU_props | % {
                                    $n = $_;
                                    $v = $RegARPx64Key_WAU.GetValue($_, [string]::Empty, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                    Write-CMTraceLog -Message "adding`t$n : $v" -Type Information;
                                    $WAUConfig | Add-Member -MemberType NoteProperty -Name $n -Value $v;
                                }
                            }
                            else
                            {
                                $m = "Get-WAUConfig returned an error: $reg_Path does not contain any WAU settings";
                                Write-CMTraceLog -Message $m -Type Warning;
                                throw [exception]::new($m);
                            }
                            $RegARPx64Key_WAU.Close();
                        }
                        else
                        {
                            $m = "Get-WAUConfig returned an error while Opening $reg_Path subkey for reading";
                            Write-CMTraceLog -Message $m -Type Error;
                            throw [exception]::new($m);
                        }
                    }
                    catch
                    {
                        $m = "Get-WAUConfig returned an error while Operating in $reg_Path";
                        Write-CMTraceLog -Message $m -Type Error;
                        throw [exception]::new($m);
                    }
                #endregion
                $RegARPx64Key.Close();
            }
            else
            {
                $m = "Get-WAUConfig returned an error while Opening $reg_Path subkey for reading";
                Write-CMTraceLog -Message $m -Type Error;
                throw [exception]::new($m);
            }
        }
        catch
        {
            $m = "Get-WAUConfig returned an error while Operating in $reg_Path subkey for reading";
            Write-CMTraceLog -Message $m -Type Error;
            throw [exception]::new($m);
        }
    #endregion

    #region reading GPO settings
        try
        {
            [Microsoft.Win32.RegistryKey]$RegGPOx64Key = $RegBaseKey.OpenSubKey($GPO_Subkey, $false);
            $reg_Path = "$RegBaseKey\$GPO_Subkey";
            if($null -ne $RegGPOx64Key)
            {
                #region navigating to WAU GPO subkey
                    try
                    {
                        [Microsoft.Win32.RegistryKey]$RegGPOx64Key_WAU = $RegGPOx64Key.OpenSubKey($ARP_ProductName, $false);
                        $reg_Path = "$RegGPOx64Key\$ARP_ProductName";

                        if($null -ne $RegGPOx64Key_WAU)
                        {
                            # if we managed to open it, then the $RegARPx64Key_WAU IS NOT NULL
                            # we want to exclude ValueNames which are defaults for ARP entries and collect only WAU_* entries;
                            [string[]]$WAU_props = $RegGPOx64Key_WAU.GetValueNames() | ? {$_.ToUpperInvariant().StartsWith($setting_prefix)}

                            # double check if we had found anything
                            if($WAU_props.Count -gt 0)
                            {
                                $n = "WAU_ActivateGPOManagement";
                                if($WAU_props.Contains($n))
                                {
                                    $m = "$n setting found in $reg_Path";
                                    Write-CMTraceLog -Message $m -Type Warning;
                                    $v = $RegGPOx64Key_WAU.GetValue($n, [string]::Empty, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);
                                    $m = "$n = $v";
                                    Write-CMTraceLog -Message $m -Type Warning;
                                    if($v -eq 1)
                                    {
                                        $m = "activating GPO override for ARP settings";
                                        Write-CMTraceLog -Message $m -Type Information;
                                        # now we are adding all filtered pairs of name+Value to our custom object
                                        $WAU_props | % {
                                            $n = $_;
                                            $v = $RegGPOx64Key_WAU.GetValue($n, [string]::Empty, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                            if(($WAUConfig.PSObject.Members).Name -icontains $n) 
                                            {
                                                # HA! $_ is a duplicate, we rewrite its ARP value with the one from GPO SubKey
                                                $m = "setting`t$n : $v";
                                                Write-CMTraceLog -Message $m -Type Information;
                                                $WAUConfig.$n = $v;
                                            }
                                            else
                                            {
                                                # HA! $_ is new setting not defied previously";
                                                $m = "adding`t$n : $v";
                                                Write-CMTraceLog -Message $m -Type Information;
                                                $WAUConfig | Add-Member -MemberType NoteProperty -Name $n -Value $v;
                                            }
                                        }
                                    }
                                    else
                                    {
                                        $m = "using only the ARP settings";
                                        Write-CMTraceLog -Message $m -Type Warning;
                                    }
                                }
                            }
                            else
                            {
                                $m = "Get-WAUConfig returned an error: $reg_Path does not contain any WAU settings";
                                Write-CMTraceLog -Message $m -Type Warning;
                                throw [exception]::new($m);
                            }
                            $RegGPOx64Key_WAU.Close();
                        }
                        else
                        {
                            $m = "Get-WAUConfig returned an error while Opening $reg_Path subkey for reading";
                            Write-CMTraceLog -Message $m -Type Error;
                            throw [exception]::new($m);
                        }
                    }
                    catch
                    {
                        $m = "Get-WAUConfig returned an error while Operating in $reg_Path";
                        Write-CMTraceLog -Message $m -Type Error;
                        throw [exception]::new($m);
                    }
                #endregion
                $RegGPOx64Key.Close();
            }
            else
            {
                $m = "Get-WAUConfig returned an error while Opening $reg_Path subkey for reading";
                Write-CMTraceLog -Message $m -Type Error;
                throw [exception]::new($m);
            }
        }
        catch
        {
            $m = "Get-WAUConfig returned an error while Operating in $reg_Path subkey for reading";
            Write-CMTraceLog -Message $m -Type Error;
            throw [exception]::new($m);
        }
    #endregion

    #closing the Registry hive after all potential reading is done
    $RegBaseKey.Close();

    #Return config
    return $WAUConfig
}
