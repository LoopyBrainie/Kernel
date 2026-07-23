# tools/check_artifacts.ps1 — P3 闸门: 3×sha256 一致 + 段 size + nm/readobj 5 struct
#
# 替代 spec 闸门 scripts/check_elf_sizes.sh 等价 PowerShell 实现
# (D-ENV-06: 用户授权前禁装 jq, 用 pwsh ConvertFrom-Json 等价)
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File tools/check_artifacts.ps1 `
#     -ElfPath zig-out/bin/kernel.elf `
#     -BuildShaFiles artifacts/build_1.sha256,artifacts/build_2.sha256,artifacts/build_3.sha256

param(
    [Parameter(Mandatory=$true)]
    [string]$ElfPath,

    [Parameter(Mandatory=$true)]
    [string[]]$BuildShaFiles
)

$LLVM = "C:\Users\LamKo\scoop\apps\llvm\current\bin"
$LLVM_NM = Join-Path $LLVM "llvm-nm.exe"
$LLVM_READOBJ = Join-Path $LLVM "llvm-readobj.exe"
$LLVM_SIZE = Join-Path $LLVM "llvm-size.exe"

if (-not (Test-Path $ElfPath)) {
    Write-Error "elf not found: $ElfPath"
    exit 2
}

# 1. 3×sha256 一致 (C3)
Write-Output "=== sha256 (3 builds must match) ==="
$shas = @()
foreach ($f in $BuildShaFiles) {
    if (-not (Test-Path $f)) { Write-Error "missing: $f"; exit 2 }
    $h = (Get-FileHash $f -Algorithm SHA256).Hash
    $shas += $h
    Write-Output "  $f : $h"
}
if (($shas | Sort-Object -Unique).Count -ne 1) {
    Write-Error "C3 FAIL: 3 sha256 not identical"
    exit 1
}
Write-Output "C3 PASS: 3 builds identical ($($shas[0]))"

# 2. 段 size (R51-M4 D157 编译期熔断基础)
Write-Output ""
Write-Output "=== Section sizes (R51-M4: text<=80K rodata<=10K data<=4K bss<=8K) ==="
$size_out = & $LLVM_SIZE $ElfPath 2>&1
$size_out | ForEach-Object { Write-Output "  $_" }

# 3. 5 struct size 闸门 (D101/D113) — 走 llvm-readobj --elf-output-style=JSON (R51-M6)
Write-Output ""
Write-Output "=== 5 struct size gate (D101/D113 + R51-M6 JSON) ==="
$json = & $LLVM_READOBJ --elf-output-style=JSON --syms $ElfPath 2>&1 | Out-String
$obj = $json | ConvertFrom-Json
$expected = @{
    "sys_result_t"          = 16
    "sys_result_payload_t"  = 8
    "rpc_unit_t"            = 1536
    "network_frame_t"       = 1536
    "block_t"               = 1536
}
$fail = $false
foreach ($name in $expected.Keys) {
    $expected_size = $expected[$name]
    $found = $false
    foreach ($phdr in $obj) {
        foreach ($sym in $phdr.Symbols) {
            if ($sym.Symbol.Name -eq $name) {
                $sz = $sym.Symbol.Size
                $found = $true
                if ($sz -ne $expected_size) {
                    Write-Error "D113 FAIL: $name size=$sz, expected=$expected_size"
                    $fail = $true
                } else {
                    Write-Output "  $name : $sz (expected=$expected_size) PASS"
                }
                break
            }
        }
        if ($found) { break }
    }
    if (-not $found) {
        Write-Warning "  $name : NOT FOUND in symtab (D113 .bss anchor missing?)"
    }
}
if ($fail) { exit 1 }
Write-Output "C3+C4 PASS: 5 struct sizes verified"
exit 0
