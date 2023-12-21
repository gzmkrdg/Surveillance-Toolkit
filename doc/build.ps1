[CmdletBinding()]
param(
    [ValidateSet('all', 'html', 'pdf', 'docx')]
    [string]$Format = 'all',
    [CultureInfo[]]$TargetCultures,
    [switch]$Release
    )

function Test-RebuildRequired {
    [OutputType([bool])]
    param (
        [parameter(Mandatory,Position=0)]
        [string]
        $OutputPath,
        [parameter(Mandatory,Position=1)]
        [string]
        $FirstInputPath,
        [parameter(Position=2)]
        [string[]]
        $AdditionalInputPaths
    )

    if (-not (Test-Path $OutputPath -PathType Leaf)) {
        Write-Debug ("'$OutputPath' does not exist." -replace "/", [IO.Path]::DirectorySeparatorChar)
        return $true
    }

    $outputStamp = (Get-ChildItem $OutputPath).LastWriteTimeUtc
    $inputStamp = (Get-ChildItem $FirstInputPath).LastWriteTimeUtc

    if ($outputStamp -lt $inputStamp) {
        Write-Debug ("'$OutputPath' is older than '$FirstInputPath'." -replace "/", [IO.Path]::DirectorySeparatorChar)
        return $true
    }

    foreach ($inputPath in $AdditionalInputPaths) {
        $inputStamp = (Get-ChildItem $inputPath).LastWriteTimeUtc
        if ($outputStamp -lt $inputStamp) {
            Write-Debug ("'$OutputPath' is older than '$inputPath'." -replace "/", [IO.Path]::DirectorySeparatorChar)
            return $true
        }
        Write-Debug ("'$OutputPath' is newer than or equal to '$inputPath'." -replace "/", [IO.Path]::DirectorySeparatorChar)
    }

    return $false
}

function New-PathogenList {
    [OutputType([void])]
    param (
        [CultureInfo]$TargetCulture,
        [string]$InputDirectory,
        [string]$OutputDirectory
    )
    $listElements = [System.Collections.Generic.Dictionary[string, string]]::new()
    $neoipcConcepts = [System.Collections.Generic.Dictionary[uint, string]]::new()
    Import-Csv -LiteralPath (Join-Path -Path $InputDirectory -ChildPath 'NeoIPC-Owned-Pathogen-Concepts.csv') -Encoding utf8NoBOM | ForEach-Object {
        $neoipcConcepts.Add([uint]::Parse($_.id), ($_.pathogen_type + '_' + ($_.concept_type -creplace '\s', '_')))
    }
    $localizedlist = [System.Collections.ArrayList]::new()
    $c = $TargetCulture
    while ($c.Name.Length -gt 0) {
        $listElementsPath = Join-Path -Path $InputDirectory -ChildPath "ListElements.$($c.Name).csv"
        if ((Test-Path -LiteralPath $listElementsPath -PathType Leaf)) {
            Import-Csv -LiteralPath $listElementsPath -Encoding utf8NoBOM | ForEach-Object {
                if ((-not $listElements.ContainsKey($_.id)) -and $_.needs_translation -ceq 't') {
                    $listElements.add($_.id, $_.translated)
                }
            }
        }
        $pcPath = Join-Path -Path $InputDirectory -ChildPath "NeoIPC-Pathogen-Concepts.$($c.Name).csv"
        $psPath = Join-Path -Path $InputDirectory -ChildPath "NeoIPC-Pathogen-Synonyms.$($c.Name).csv"

        if ((Test-Path -LiteralPath $pcPath -PathType Leaf)) {
            if (-not (Test-Path -LiteralPath $psPath -PathType Leaf)) {
                throw "Invalid state: If '$pcPath' exists, '$psPath' must exist too."
            }
            $pc = Import-Csv -LiteralPath $pcPath -Encoding utf8NoBOM
            $pcHash = [System.Collections.Generic.Dictionary[int, System.Collections.Hashtable]]::new()
            $lineNo = 1
            foreach ($p in $pc) {
                $lineNo++
                # Validate the input file
                if ($p.property -cne 'CONCEPT') {
                    throw "Unknown property name '$($p.property)' in line $lineNo in file '$pcPath'."
                }
                if ($p.default.Trim().Length -eq 0) {
                    throw "Missing default value in line $lineNo in file '$pcPath'."
                }
                if ($p.default.Trim() -cne $p.default) {
                    throw "Default value with superflous whitespace in line $lineNo in file '$pcPath'."
                }
                $needs_translation = $p.needs_translation -ceq 't'
                if (-not ($needs_translation -or $p.needs_translation -ceq 'f')) {
                    throw "Unexpected boolen value '$($p.needs_translation)' in line $lineNo file '$pcPath'."
                }
                if ($needs_translation -and $p.translated.Trim().Length -eq 0) {
                    throw "Missing translation in line $lineNo file '$pcPath'."
                }
                if ($needs_translation -and $p.translated.Trim() -cne $p.translated) {
                    throw "Translation with superflous whitespace in line $lineNo in file '$pcPath'."
                }
                if ((-not $needs_translation) -and $p.translated.Length -ne 0) {
                    throw "Unexpected translation in line $lineNo file '$pcPath'."
                }
                $pcHash.Add($p.id, @{
                    needs_translation = $needs_translation
                    default = $p.default
                    translated = $p.translated
                })
            }

            $ps = Import-Csv -LiteralPath $psPath -Encoding utf8NoBOM
            $psHash = @{}
            $lineNo = 1
            foreach ($p in $ps) {
                $lineNo++
                # Validate the input file
                if ($p.property -cne 'SYNONYM') {
                    throw "Unknown property name '$($p.property)' in line $lineNo in file '$psPath'."
                }
                if ($p.default.Trim().Length -eq 0) {
                    throw "Missing default value in line $lineNo in file '$psPath'."
                }
                if ($p.default.Trim() -cne $p.default) {
                    throw "Default value with superflous whitespace in line $lineNo in file '$psPath'."
                }
                $needs_translation = $p.needs_translation -ceq 't'
                if (-not ($needs_translation -or $p.needs_translation -ceq 'f')) {
                    throw "Unexpected boolen value '$($p.needs_translation)' in line $lineNo file '$psPath'."
                }
                if ($needs_translation -and $p.translated.Trim().Length -eq 0) {
                    throw "Missing translation in line $lineNo file '$psPath'."
                }
                if ($needs_translation -and $p.translated.Trim() -cne $p.translated) {
                    throw "Translation with superflous whitespace in line $lineNo in file '$psPath'."
                }
                if ((-not $needs_translation) -and $p.translated.Length -ne 0) {
                    throw "Unexpected translation in line $lineNo file '$psPath'."
                }
                $psHash.Add($p.id, @{
                    needs_translation = $needs_translation
                    default = $p.default
                    translated = $p.translated
                })
            }
            $localizedlist.Add([System.ValueTuple]::Create($pcHash, $psHash)) > $null
        }
        elseif ((Test-Path -LiteralPath $psPath -PathType Leaf)) {
            throw "Invalid state: If '$psPath' exists, '$pcPath' must exist too."
        }
        $c = $TargetCulture.Parent
    }
    if ($TargetCulture.Name.Length -gt 0 -and $localizedlist.Count -eq 0) {
        Write-Warning "Could not find a pathogen translation file for '$($TargetCulture.Name)'. This will result in an untranslated pathogen list."
    }
    Import-Csv -LiteralPath (Join-Path -Path $InputDirectory -ChildPath 'ListElements.csv') -Encoding utf8NoBOM | ForEach-Object {
        if (-not $listElements.ContainsKey($_.id)) {
            $listElements.add($_.id, $_.value)
        }
    }

    $commonCommensal = ''
    if (-not $listElements.TryGetValue('common_commensal', [ref]$commonCommensal)) {
        throw "Lookup of string 'common_commensal' failed."
    }

    $recognisedPathogen = ''
    if (-not $listElements.TryGetValue('recognised_pathogen', [ref]$recognisedPathogen)) {
        throw "Lookup of string 'recognised_pathogen' failed."
    }

    $MRSA = ''
    if (-not $listElements.TryGetValue('mrsa', [ref]$MRSA)) {
        throw "Lookup of string 'mrsa' failed."
    }

    $VRE = ''
    if (-not $listElements.TryGetValue('vre', [ref]$VRE)) {
        throw "Lookup of string 'vre' failed."
    }

    $3GCR = ''
    if (-not $listElements.TryGetValue('3gcr', [ref]$3GCR)) {
        throw "Lookup of string '3gcr' failed."
    }

    $carbapenems = ''
    if (-not $listElements.TryGetValue('carbapenems', [ref]$carbapenems)) {
        throw "Lookup of string 'carbapenems' failed."
    }

    $colistin = ''
    if (-not $listElements.TryGetValue('colistin', [ref]$colistin)) {
        throw "Lookup of string 'colistin' failed."
    }


    $pcPath = Join-Path -Path $InputDirectory -ChildPath 'NeoIPC-Pathogen-Concepts.csv'
    $pc = Import-Csv -LiteralPath $pcPath -Encoding utf8NoBOM
    $pathogenList = [System.Collections.ArrayList]::new()
    $lineNo = 1
    foreach ($p in $pc) {
        $lineNo++
        # Validate the input file
        if ($p.concept.Trim().Length -eq 0) {
            throw "Missing concept value in line $lineNo in file '$pcPath'."
        }
        if ($p.concept.Trim() -cne $p.concept) {
            throw "Concept value with superflous whitespace in line $lineNo in file '$pcPath'."
        }
        if ($p.concept_type -cnotin 'clade','family','genus','group','serotype','species','species complex','subspecies','unknown','variety') {
            throw "Unknown concept type in line $lineNo in file '$pcPath'."
        }
        if ($p.concept_source -cnotin 'ICTV','LPSN','MycoBank','NeoIPC') {
            throw "Unknown concept source in line $lineNo in file '$pcPath'."
        }

        $type = ''
        switch -casesensitive ($p.concept_source) {
            'LPSN' {
                $typeString = 'bacterial_' + $p.concept_type -creplace '\s', '_'
                if (-not $listElements.TryGetValue($typeString, [ref]$type)) {
                    throw "Lookup of type string '$typeString' failed in line $lineNo in file '$pcPath'."
                }
                $type = "https://lpsn.dsmz.de/$($p.concept_id)[$type,window=_blank]"
            }
            'MycoBank' {
                $typeString = 'fungal_' + $p.concept_type -creplace '\s', '_'
                if (-not $listElements.TryGetValue($typeString, [ref]$type)) {
                    throw "Lookup of type string '$typeString' failed in line $lineNo in file '$pcPath'."
                }
                $type = "https://www.mycobank.org/page/Name%20details%20page/field/Mycobank%20%23/$($p.concept_id)[$type,window=_blank]"
            }
            'ICTV' {
                $typeString = 'viral_' + $p.concept_type -creplace '\s', '_'
                if (-not $listElements.TryGetValue($typeString, [ref]$type)) {
                    throw "Lookup of type string '$typeString' failed in line $lineNo in file '$pcPath'."
                }
                $type = "https://ictv.global/taxonomy/taxondetails?taxnode_id=$($p.concept_id)[$type,window=_blank]"
            }
            'NeoIPC' {
                $typeString = ''
                if ($p.concept_type -ceq 'unknown') {
                    if (-not $listElements.TryGetValue('unknown', [ref]$type)) {
                        throw "Lookup of type string 'unknown' failed in line $lineNo in file '$pcPath'."
                    }
                }
                else {
                    if (-not $neoipcConcepts.TryGetValue([uint]::Parse($p.concept_id), [ref]$typeString)) {
                        throw "Lookup of NeoIPC pathogen with concept_id $($p.concept_id) failed in line $lineNo in file '$pcPath'."
                    }
                    if (-not $listElements.TryGetValue($typeString, [ref]$type)) {
                        throw "Lookup of type string '$typeString' failed in line $lineNo in file '$pcPath'."
                    }
                }
            }
            default { throw "Lookup of type string failed in line $lineNo in file '$pcPath'." }
        }

        $pathogenName = $p.concept
        foreach ($l in $localizedlist) {
            $lpc = @{}
            if ($l.Item1.TryGetValue($p.id, [ref]$lpc)) {
                if ($p.concept -cne $lpc.default) {
                    throw "Default value '$($lpc.default)' in translation file differs from concept '$($p.concept)' for pathogen with id '$($p.id)'."
                }
                if ($lpc.needs_translation) {
                    $pathogenName = $lpc.translated
                }
                break
            }
        }

        if ($p.is_cc -ceq 't') {
            $pathogenicity = $commonCommensal
        } elseif ($p.is_cc -ceq 'f') {
            $pathogenicity = $recognisedPathogen
        }  else {
            throw "Unexpected boolen value '$($p.is_cc)' in line $lineNo file '$pcPath'."
        }

        $resistanceString = [System.Text.StringBuilder]::new()
        if ($p.show_mrsa -ceq 't') {
            $resistanceString.Append($MRSA).Append(', ') > $null
        } elseif (-not($p.show_mrsa -ceq 'f')) {
            throw "Unexpected boolen value '$($p.show_mrsa)' in line $lineNo file '$pcPath'."
        }
        if ($p.show_vre -ceq 't') {
            $resistanceString.Append($VRE).Append(', ') > $null
        } elseif (-not($p.show_vre -ceq 'f')) {
            throw "Unexpected boolen value '$($p.show_vre)' in line $lineNo file '$pcPath'."
        }
        if ($p.show_3gcr -ceq 't') {
            $resistanceString.Append($3GCR).Append(', ') > $null
        } elseif (-not($p.show_3gcr -ceq 'f')) {
            throw "Unexpected boolen value '$($p.show_3gcr)' in line $lineNo file '$pcPath'."
        }
        if ($p.show_carb_r -ceq 't') {
            $resistanceString.Append($carbapenems).Append(', ') > $null
        } elseif (-not($p.show_carb_r -ceq 'f')) {
            throw "Unexpected boolen value '$($p.show_carb_r)' in line $lineNo file '$pcPath'."
        }
        if ($p.show_coli_r -ceq 't') {
            $resistanceString.Append($colistin).Append(', ') > $null
        } elseif (-not($p.show_coli_r -ceq 'f')) {
            throw "Unexpected boolen value '$($p.show_coli_r)' in line $lineNo file '$pcPath'."
        }
        if ($resistanceString.Length -gt 0) {
            $resistanceString.Length -= 2
        }

        $pathogenList.Add(@(
            "[[pathogen-concept-$($p.id)]]$pathogenName"
            $type
            $pathogenicity
            $resistanceString.ToString()
        )) > $null
    }

    #$ps = Import-Csv -LiteralPath (Join-Path -Path $InputDirectory -ChildPath 'NeoIPC-Pathogen-Synonyms.csv') -Encoding utf8NoBOM

    if ($TargetCulture.Name.Length -gt 0) {
        $outfile = Join-Path -Path $OutputDirectory -ChildPath "NeoIPC-Pathogens.$TargetCulture.adoc"
    }
    else {
        $outfile = Join-Path -Path $OutputDirectory -ChildPath "NeoIPC-Pathogens.adoc"
    }
    $pathogenList |
    Sort-Object -Property {$_[0] -creplace '^\[\[pathogen-concept-\d+\]\](.+)$','$1'} -Culture $TargetCulture.Name |
    ForEach-Object { $_ | Join-String -OutputPrefix '|' -Separator ' |' } |
    Out-File -LiteralPath $outfile -Encoding utf8NoBOM

}

if ($null -eq $targetCultures)
{
    $targetCultures = @(
        (new-object CultureInfo("")),
        (new-object CultureInfo("de")),
        (new-object CultureInfo("es"))
        (new-object CultureInfo("tr"))
         )
}
if ($Release)
{
    $revRemark = 'revremark!'
}
else {
    $revRemark = 'revremark=Preview'
}

$metadataDir = (Resolve-Path -Path "$PSScriptRoot/../metadata").Path
$antibioticsDir = "$metadataDir/common/antibiotics"
$pathogensDir = "$metadataDir/common/pathogens"
$buildDir = "$PSScriptRoot/build"
$outDir = "$PSScriptRoot/out"
$protocolDir = "$PSScriptRoot/protocol"
$imgDir = "$protocolDir/img"
$buildImgDir = "$buildDir/img"
$resDir = "$protocolDir/resx"
$transDir = "$protocolDir/xslt"

if (-not (Test-Path -LiteralPath $buildDir -PathType Container)) {
    Write-Debug -Message "Build directory does not exist."
    $p = (New-Item -Path $PSScriptRoot -Name build -ItemType Directory).FullName
    Write-Verbose -Message "Created build directory at '$p'."
}

if (-not (Test-Path -LiteralPath $buildImgDir -PathType Container)) {
    Write-Debug -Message "Build image directory does not exist."
    $p = (New-Item -Path $buildDir -Name img -ItemType Directory).FullName
    Write-Verbose -Message "Created build image directory at '$p'."
}

if (-not (Test-Path -LiteralPath $outDir -PathType Container)) {
    Write-Debug -Message "Output directory does not exist."
    $p = (New-Item -Path $PSScriptRoot -Name out -ItemType Directory).FullName
    Write-Verbose -Message "Created output directory at '$p'."
}

Copy-Item $imgDir/* $buildImgDir/ -Force
Copy-Item $imgDir $buildImgDir/ -Force -Recurse
Copy-Item $imgDir $outDir -Force -Recurse

[AppContext]::SetSwitch("Switch.System.Xml.AllowDefaultResolver", $true);
$resolver = New-Object System.Xml.XmlUrlResolver

$titlePage = New-Object System.Xml.Xsl.XslCompiledTransform
$titlePage.Load((Get-ChildItem $transDir/NeoIPC-Core-Title-Page.xslt).FullName, [System.Xml.Xsl.XsltSettings]::TrustedXslt, $resolver)

$previewWatermark = New-Object System.Xml.Xsl.XslCompiledTransform
$previewWatermark.Load((Get-ChildItem $transDir/Preview-Watermark.xslt).FullName, [System.Xml.Xsl.XsltSettings]::TrustedXslt, $resolver)

$decisionFlow = New-Object System.Xml.Xsl.XslCompiledTransform
$decisionFlow.Load((Get-ChildItem $transDir/NeoIPC-Core-Decision-Flow.xslt).FullName, [System.Xml.Xsl.XsltSettings]::TrustedXslt, $resolver)

$masterDataSheet = New-Object System.Xml.Xsl.XslCompiledTransform
$masterDataSheet.Load((Get-ChildItem $transDir/NeoIPC-Core-Master-Data-Collection-Sheet.xslt).FullName, [System.Xml.Xsl.XsltSettings]::TrustedXslt, $resolver)

$masterDataSheetImage = New-Object System.Xml.Xsl.XslCompiledTransform
$masterDataSheetImage.Load((Get-ChildItem $transDir/NeoIPC-Core-Master-Data-Collection-Sheet-Image.xslt).FullName, [System.Xml.Xsl.XsltSettings]::TrustedXslt, $resolver)

if (Test-RebuildRequired $buildDir/NeoIPC-Core-Protocol.header.adoc $protocolDir/NeoIPC-Core-Protocol.header.adoc) {
    Write-Debug "Copying Asciidoc header file to build dir"
    Copy-Item $protocolDir/NeoIPC-Core-Protocol.header.adoc $buildDir/NeoIPC-Core-Protocol.header.adoc -Force
}

foreach ($targetCulture in $targetCultures)
{
    if ("iv" -eq $targetCulture.TwoLetterISOLanguageName)
    {
        $revDate = "revdate=$([datetime]::UtcNow.ToString('yyyy-MM-dd'))"
        $lang = ""
        $langSuffix = ""
        Write-Information "Generating NeoIPC documentation (english)"

        if (Test-RebuildRequired $buildDir/NeoIPC-Antibiotics.adoc $antibioticsDir/NeoIPC-Antibiotics.csv) {
            Write-Verbose "Generating appendix table for antibiotics"

            Import-Csv -LiteralPath $antibioticsDir/NeoIPC-Antibiotics.csv -Encoding utf8 |
                Sort-Object name |
                ForEach-Object { "|$($_.name) |$($_.atc_code)" } |
                Out-File -LiteralPath $buildDir/NeoIPC-Antibiotics.adoc -Encoding utf8NoBOM -Append
        }
    }
    else
    {
        $revDate = "revdate=$([datetime]::UtcNow.ToString('d', $targetCulture))"
        $lang = $targetCulture.TwoLetterISOLanguageName
        $langSuffix = ".$lang"
        Write-Information "Generating NeoIPC documentation for language '$($targetCulture.DisplayName)'"

        if (Test-RebuildRequired $buildDir/NeoIPC-Antibiotics$langSuffix.adoc $antibioticsDir/NeoIPC-Antibiotics.csv $antibioticsDir/NeoIPC-Antibiotics$langSuffix.csv) {
            Write-Verbose "Generating appendix table for antibiotics"

            $hash = @{}
            Import-Csv -LiteralPath $antibioticsDir/NeoIPC-Antibiotics$langSuffix.csv -Encoding utf8 |
                ForEach-Object {
                    if ($_.property -cne 'NAME') {
                        throw "Unexpected property value '$($_.property)' in file '$antibioticsDir/NeoIPC-Antibiotics$langSuffix.csv'"
                    }
                    $loc = @{}
                    $loc['default'] = $_.default

                    if ($_.needs_translation -ceq 'f') {
                        $loc['translated'] = $null
                    } elseif ($_.needs_translation -ceq 't') {
                        $loc['translated'] = $_.translated
                    } else {
                        throw "Unexpected needs_translation value '$($_.needs_translation)' in file '$antibioticsDir/NeoIPC-Antibiotics$langSuffix.csv'"
                    }
                    $hash[$_.code] = $loc
                }

            Import-Csv -LiteralPath $antibioticsDir/NeoIPC-Antibiotics.csv -Encoding utf8 |
                Sort-Object name |
                ForEach-Object {
                    $loc = $hash[$_.atc_code]
                    if ($loc['default'] -cne $_.name) {
                        throw "Values for name ($($_.name)) and default ($($loc['default']) for ATC code '$($_.atc_code)' don't match between '$antibioticsDir/NeoIPC-Antibiotics.csv' and '$antibioticsDir/NeoIPC-Antibiotics$langSuffix.csv'"
                    }
                    if ($loc['translated']) {
                        $name = $loc['translated']
                    }
                    else {
                        $name = $_.name
                    }

                    "|$name |$($_.atc_code)"
                } |
                Out-File -LiteralPath $buildDir/NeoIPC-Antibiotics$langSuffix.adoc -Encoding utf8NoBOM -Append
        }
    }
    if (Test-RebuildRequired $buildDir/NeoIPC-Pathogens$langSuffix.adoc $pathogensDir/NeoIPC-Pathogen-Concepts.csv $pathogensDir/NeoIPC-Pathogen-Concepts$langSuffix.csv) {
        New-PathogenList -TargetCulture $targetCulture -InputDirectory $pathogensDir -OutputDirectory $buildDir
    }
    if (Test-RebuildRequired $buildImgDir/NeoIPC-Core-Title-Page$langSuffix.svg $resDir/NeoIPC-Core-Title-Page$langSuffix.resx $transDir/NeoIPC-Core-Title-Page.xslt) {
        Write-Verbose "Generating title page background SVG"
        $titlePage.Transform("$resDir/NeoIPC-Core-Title-Page$langSuffix.resx", "$buildImgDir/NeoIPC-Core-Title-Page$langSuffix.svg")
    }
    if (($revRemark -ne 'revremark!') -and (Test-RebuildRequired $buildImgDir/Preview-Watermark$langSuffix.svg $resDir/Preview-Watermark$langSuffix.resx $transDir/Preview-Watermark.xslt)) {
        Write-Verbose "Generating preview watermark SVG"
        $previewWatermark.Transform("$resDir/Preview-Watermark$langSuffix.resx", "$buildImgDir/Preview-Watermark$langSuffix.svg")
    }
    if (Test-RebuildRequired $buildImgDir/NeoIPC-Core-Decision-Flow$langSuffix.svg $resDir/NeoIPC-Core-Decision-Flow$langSuffix.resx $transDir/NeoIPC-Core-Decision-Flow.xslt) {
        Write-Verbose "Generating decision flow SVG"
        $decisionFlow.Transform("$resDir/NeoIPC-Core-Decision-Flow$langSuffix.resx", "$buildImgDir/NeoIPC-Core-Decision-Flow$langSuffix.svg")
    }
    if (Test-RebuildRequired $buildImgDir/NeoIPC-Core-Master-Data-Collection-Sheet$langSuffix.svg $resDir/NeoIPC-Core-Master-Data-Collection-Sheet$langSuffix.resx $transDir/NeoIPC-Core-Master-Data-Collection-Sheet.xslt) {
        Write-Verbose "Generating master data collection sheet SVG"
        $masterDataSheet.Transform("$resDir/NeoIPC-Core-Master-Data-Collection-Sheet$langSuffix.resx", "$buildImgDir/NeoIPC-Core-Master-Data-Collection-Sheet$langSuffix.svg")
    }
    if (Test-RebuildRequired $buildImgDir/NeoIPC-Core-Master-Data-Collection-Sheet-Image$langSuffix.svg $resDir/NeoIPC-Core-Master-Data-Collection-Sheet$langSuffix.resx $transDir/NeoIPC-Core-Master-Data-Collection-Sheet-Image.xslt) {
        Write-Verbose "Generating master data collection sheet image SVG"
        $masterDataSheetImage.Transform("$resDir/NeoIPC-Core-Master-Data-Collection-Sheet$langSuffix.resx", "$buildImgDir/NeoIPC-Core-Master-Data-Collection-Sheet-Image$langSuffix.svg")
    }
    if (Test-RebuildRequired $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc $protocolDir/NeoIPC-Core-Protocol$langSuffix.adoc) {
        Write-Debug "Copying Asciidoc files to build dir"
        Copy-Item $protocolDir/*$langSuffix.adoc $buildDir/ -Force
    }
    if (($Format -eq 'all' -or $Format -eq 'html') -and (Test-RebuildRequired $outDir/index$langSuffix.html $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc @(
        "$buildDir/NeoIPC-Core-Protocol.header.adoc",
        "$buildImgDir/NeoIPC-Core-Decision-Flow$langSuffix.svg",
        "$buildImgDir/NeoIPC-Core-Master-Data-Collection-Sheet-Image$langSuffix.svg"
        ))) {
        Write-Information "Generating HTML"
        asciidoctor -a $revRemark -a $revDate --backend html5 --warnings --trace --failure-level WARN --destination-dir $outDir --out-file index$langSuffix.html $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc
        if (-not $?) { exit 1 }
        Write-Verbose "Linting HTML"
        $allOutput = & linthtml --config (((Resolve-Path -Relative "$PSScriptRoot/.linthtmlrc.yaml") -replace "\\","/") -replace "\./","") (((Resolve-Path -Relative "$outDir/index$langSuffix.html") -replace "\\","/") -replace "\./","") 2>&1
        $success = $?
        $stderr = $allOutput | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }
        $stdout = $allOutput | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
        # For some reason linthtml writes standard output to STDERR and error messages to STDOUT
        foreach ($msg in $stderr) {
            if ($msg.Exception.Message.Trim().Length -gt 0) {
                Write-Verbose $msg.Exception.Message
            }
        }
        if (-not $success) {
            foreach ($msg in $stdout) {
                if ($msg.Trim().Length -gt 0) {
                    Write-Error $msg
                }
            }
            exit 1
        }
    }
    if (($Format -eq 'all' -or $Format -eq 'pdf') -and (Test-RebuildRequired $outDir/NeoIPC-Core-Protocol$langSuffix.pdf $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc @(
        "$buildDir/NeoIPC-Core-Protocol.header.adoc",
        "$PSScriptRoot/NeoIPC.theme.yml",
        "$buildImgDir/NeoIPC-Core-Title-Page$langSuffix.svg",
        "$buildImgDir/NeoIPC-Core-Decision-Flow$langSuffix.svg",
        "$buildImgDir/NeoIPC-Core-Master-Data-Collection-Sheet-Image$langSuffix.svg"
        ))) {
        Write-Information "Generating PDF"
        if ($IsWindows) {
            Write-Warning "Asciidoctor Mathematical is not supported on Windows. The STEM expressions will not be converted."
            asciidoctor-pdf -a $revRemark -a $revDate --warnings --trace --failure-level WARN --destination-dir $outDir --out-file NeoIPC-Core-Protocol$langSuffix.pdf $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc
            if (-not $?) { exit 1 }
        } else {
            asciidoctor-pdf -a $revRemark -a $revDate -a mathematical-format=svg -r asciidoctor-mathematical --warnings --trace --failure-level WARN --destination-dir $outDir --out-file NeoIPC-Core-Protocol$langSuffix.pdf $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc
            if (-not $?) { exit 1 }
        }
    }
    if (($Format -eq 'all' -or $Format -eq 'docx') -and (Test-RebuildRequired $outDir/NeoIPC-Core-Protocol$langSuffix.docx $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc @(
        "$buildDir/NeoIPC-Core-Protocol.header.adoc",
        "$buildDir/NeoIPC-Core-Protocol$langSuffix.xml",
        "$buildImgDir/NeoIPC-Core-Decision-Flow$langSuffix.svg",
        "$buildImgDir/NeoIPC-Core-Master-Data-Collection-Sheet-Image$langSuffix.svg"
        ))) {
        Write-Information "Generating Open XML (docx)"
        if (Test-RebuildRequired $buildDir/NeoIPC-Core-Protocol$langSuffix.xml $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc) {
            Write-Verbose "Generating DocBook xml"
            if ($IsWindows) {
                Write-Warning "Asciidoctor Mathematical is not supported on Windows. The STEM expressions will not be converted."
                asciidoctor -a $revRemark -a $revDate --backend docbook --warnings --trace --failure-level WARN --destination-dir $buildDir --out-file NeoIPC-Core-Protocol$langSuffix.xml $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc
                if (-not $?) { exit 1 }
            } else {
                asciidoctor -a $revRemark -a $revDate -a mathematical-format=svg -r asciidoctor-mathematical --backend docbook --warnings --trace --failure-level WARN --destination-dir $buildDir --out-file NeoIPC-Core-Protocol$langSuffix.xml $buildDir/NeoIPC-Core-Protocol$langSuffix.adoc
                if (-not $?) { exit 1 }
            }
        }
        if (Test-RebuildRequired $outDir/img/NeoIPC-Core-Decision-Flow$langSuffix.docx $buildDir/NeoIPC-Core-Decision-Flow$langSuffix.xml @(
            "$buildImgDir/NeoIPC-Core-Decision-Flow$langSuffix.svg",
            "$buildImgDir/NeoIPC-Core-Master-Data-Collection-Sheet-Image$langSuffix.svg"
            )) {
            Write-Verbose "Generating DOCX"
            $locationBackup = Get-Location
            Set-Location $buildDir
            try {
                pandoc --from=docbook --to=docx --toc --output=$outDir/NeoIPC-Core-Protocol$langSuffix.docx NeoIPC-Core-Protocol$langSuffix.xml
                if (-not $?) { exit 1 }
            }
            finally {
                Set-Location $locationBackup
            }
        }
    }
}
