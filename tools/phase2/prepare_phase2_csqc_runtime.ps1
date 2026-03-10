param(
	[string]$TemplateRuntimeBase = "E:\_RE\runtime\phase3-interop\qwbase",
	[string]$OutputRuntimeBase = "E:\_RE\runtime\phase2-csqc-runtime-alt",
	[string]$CsprogsPath = "",
	[switch]$BuildFromKtxQc,
	[string]$KtxQcSrc = "E:\Repositories\ktx\qcsrc",
	[string]$FteqccExe = "E:\_RE\runtime\phase3-interop\fteqcc-build\fteqcc.exe",
	[string]$BuildWorkRoot = "E:\_RE\runtime\csqc_build_tmp",
	[switch]$NoInputFrameStub
)

$ErrorActionPreference = "Stop"

function Assert-Path {
	param(
		[string]$PathToCheck,
		[string]$Label
	)

	if (-not (Test-Path $PathToCheck)) {
		throw "$Label missing: $PathToCheck"
	}
}

function Get-CsprogsChecksumFromFile {
	param([string]$FilePath)

	if (-not (Test-Path $FilePath)) {
		return [UInt64]0
	}

	$bytes = [System.IO.File]::ReadAllBytes($FilePath)
	$crc = 0xffff
	foreach ($b in $bytes) {
		$crc = ($crc -bxor (($b -band 0xff) -shl 8)) -band 0xffff
		for ($i = 0; $i -lt 8; $i++) {
			if (($crc -band 0x8000) -ne 0) {
				$crc = (($crc -shl 1) -bxor 0x1021) -band 0xffff
			}
			else {
				$crc = ($crc -shl 1) -band 0xffff
			}
		}
	}

	return [UInt64]($crc -band 0xffff)
}

function Resolve-ProgsOutputPath {
	param([string]$ProgsSrcPath)

	$content = Get-Content -Path $ProgsSrcPath
	foreach ($line in $content) {
		$trimmed = $line.Trim()
		if (-not $trimmed) {
			continue
		}
		if ($trimmed.StartsWith("//")) {
			continue
		}
		return [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $ProgsSrcPath) $trimmed))
	}

	throw "Unable to resolve output path from $ProgsSrcPath (missing first output line)"
}

function Build-CsprogsFromKtxQc {
	param(
		[string]$QcSrcPath,
		[string]$CompilerExe,
		[string]$WorkRoot,
		[bool]$InjectStub
	)

	Assert-Path -PathToCheck $QcSrcPath -Label "KTX qcsrc"
	Assert-Path -PathToCheck $CompilerExe -Label "fteqcc compiler"

	if (Test-Path $WorkRoot) {
		Remove-Item -Recurse -Force $WorkRoot
	}
	Copy-Item -Recurse -Force $QcSrcPath $WorkRoot

	$progsSrc = Join-Path $WorkRoot "progs.src"
	Assert-Path -PathToCheck $progsSrc -Label "progs.src"

	$stubInjected = $false
	if ($InjectStub) {
		# fteextensions.qc declares CSQC_Input_Frame; only skip stubbing when an implementation body exists.
		$hasInputFrameBody = @(Get-ChildItem -Path $WorkRoot -Filter "*.qc" -File -ErrorAction SilentlyContinue | Select-String -Pattern "\bCSQC_Input_Frame\s*=" -CaseSensitive:$false).Count -gt 0
		if (-not $hasInputFrameBody) {
			$stubPath = Join-Path $WorkRoot "autostubs.qc"
			"void() CSQC_Input_Frame { }" | Set-Content -Path $stubPath -Encoding ascii
			$lines = Get-Content -Path $progsSrc
			if (@($lines | Where-Object { $_.Trim() -eq "autostubs.qc" }).Count -eq 0) {
				$lines += "autostubs.qc"
				$lines | Set-Content -Path $progsSrc -Encoding ascii
			}
			$stubInjected = $true
		}
	}

	$outPath = Resolve-ProgsOutputPath -ProgsSrcPath $progsSrc
	$outPathSanitized = Join-Path $WorkRoot ([System.IO.Path]::GetFileName($outPath))
	if (Test-Path $outPath) {
		Remove-Item -Force $outPath
	}
	if ($outPathSanitized -ne $outPath -and (Test-Path $outPathSanitized)) {
		Remove-Item -Force $outPathSanitized
	}

	Push-Location $WorkRoot
	try {
		& $CompilerExe -srcfile $progsSrc | Out-Null
		if ($LASTEXITCODE -ne 0) {
			throw "fteqcc failed with exit code $LASTEXITCODE while compiling $progsSrc"
		}
	}
	finally {
		Pop-Location
	}

	$compiledPath = ""
	if (Test-Path $outPath) {
		$compiledPath = $outPath
	}
	elseif (Test-Path $outPathSanitized) {
		$compiledPath = $outPathSanitized
	}
	else {
		throw "compiled csprogs missing: $outPath"
	}

	return [PSCustomObject]@{
		output_path = $compiledPath
		stub_injected = $stubInjected
	}
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Assert-Path -PathToCheck $TemplateRuntimeBase -Label "template runtime"

$resolvedCsprogsPath = ""
$inputFrameStubInjected = $false
if ($BuildFromKtxQc) {
	$buildResult = Build-CsprogsFromKtxQc `
		-QcSrcPath $KtxQcSrc `
		-CompilerExe $FteqccExe `
		-WorkRoot $BuildWorkRoot `
		-InjectStub:(-not $NoInputFrameStub)
	$resolvedCsprogsPath = $buildResult.output_path
	$inputFrameStubInjected = [bool]$buildResult.stub_injected
}
elseif ($CsprogsPath) {
	$resolvedCsprogsPath = (Resolve-Path $CsprogsPath).Path
}
else {
	$fallback = Join-Path $repoRoot "csprogs.dat"
	if (Test-Path $fallback) {
		$resolvedCsprogsPath = $fallback
	}
	else {
		throw "No csprogs source provided. Use -CsprogsPath or -BuildFromKtxQc."
	}
}

Assert-Path -PathToCheck $resolvedCsprogsPath -Label "csprogs source"

if (Test-Path $OutputRuntimeBase) {
	Remove-Item -Recurse -Force $OutputRuntimeBase
}
New-Item -ItemType Directory -Force -Path $OutputRuntimeBase | Out-Null

$copiedDirs = @()
foreach ($dirName in @("id1", "ktx", "qw", "ezquake")) {
	$srcDir = Join-Path $TemplateRuntimeBase $dirName
	if (Test-Path $srcDir) {
		Copy-Item -Recurse -Force $srcDir (Join-Path $OutputRuntimeBase $dirName)
		$copiedDirs += $dirName
	}
}

$targetKtxDir = Join-Path $OutputRuntimeBase "ktx"
New-Item -ItemType Directory -Force -Path $targetKtxDir | Out-Null
$targetCsprogs = Join-Path $targetKtxDir "csprogs.dat"
Copy-Item -Force -Path $resolvedCsprogsPath -Destination $targetCsprogs

$checksum = Get-CsprogsChecksumFromFile -FilePath $targetCsprogs
$checksumHex = "{0:x}" -f $checksum
$targetAliasDir = Join-Path $targetKtxDir "csprogsvers"
New-Item -ItemType Directory -Force -Path $targetAliasDir | Out-Null
$targetAliasPath = Join-Path $targetAliasDir "$checksumHex.dat"
Copy-Item -Force -Path $targetCsprogs -Destination $targetAliasPath

$manifestPath = Join-Path $OutputRuntimeBase "phase2_runtime_manifest.txt"
$manifest = @(
	"template_runtime=$TemplateRuntimeBase"
	"output_runtime=$OutputRuntimeBase"
	"copied_dirs=$($copiedDirs -join ',')"
	"csprogs_source=$resolvedCsprogsPath"
	"csprogs_target=$targetCsprogs"
	"csprogs_size=$((Get-Item $targetCsprogs).Length)"
	"csprogs_checksum=$checksum"
	"csprogs_checksum_hex=0x$checksumHex"
	"csprogs_alias=$targetAliasPath"
	"build_from_ktx_qc=$([int][bool]$BuildFromKtxQc)"
	"input_frame_stub_injected=$([int]$inputFrameStubInjected)"
)
$manifest | Set-Content -Path $manifestPath -Encoding ascii

Get-Content -Path $manifestPath
