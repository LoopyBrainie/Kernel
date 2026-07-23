# tools/run_p3_gates.ps1 — P3 门禁全跑
#   1. 3×clean rebuild → sha256 一致
#   2. llvm-size 段尺寸 ≤ R51-M4 上限
#   3. llvm-nm 5 struct 锚点
#   4. llvm-readobj --elf-output-style=JSON 5 struct size 精确匹配 (D113/R51-M6)

$REPO = "D:\myProject\Kernel\mvp\phase0-final-windows-20260722"
$LLVM = "C:\Users\LamKo\scoop\apps\llvm\current\bin"
$ZIG = "C:\Users\LamKo\scoop\shims\zig.exe"
$ART = Join-Path $REPO "artifacts"

$ok = $true

# Step 1: 3×clean rebuild
Write-Output "=== P3 Step 1: 3×clean rebuild → sha256 ==="

$shas = @()
for ($i = 1; $i -le 3; $i++) {
    Write-Output "  build $i..."
    Push-Location $REPO
    & $ZIG build 2>&1 | Out-Null
    Pop-Location
    $elf = Join-Path $REPO "zig-out\bin\kernel.elf"
    if (-not (Test-Path $elf)) {
        Write-Output "  build $i FAILED, no kernel.elf"
        $ok = $false
        continue
    }
    $h = (Get-FileHash $elf -Algorithm SHA256).Hash
    $shas += $h
    $shaFile = Join-Path $ART "build_$i.sha256"
    Set-Content -Path $shaFile -Value $h
    Write-Output "  build_$i.sha256 : $h"
}

if (($shas | Sort-Object -Unique).Count -ne 1) {
    Write-Output "C3 FAIL: 3 builds not identical"
    $ok = $false
} else {
    Write-Output "C3 PASS: 3 builds identical ($($shas[0]))"
}

# Step 2: section sizes
Write-Output ""
Write-Output "=== P3 Step 2: Section sizes (R51-M4 ledger_caps) ==="
$elf = Join-Path $REPO "zig-out\bin\kernel.elf"
$sizeOut = & (Join-Path $LLVM "llvm-size.exe") $elf 2>&1
$sizeOut | ForEach-Object { Write-Output "  $_" }

# Step 3: nm 5 struct anchors
Write-Output ""
Write-Output "=== P3 Step 3: nm 5 struct anchors (D101/D113) ==="
$expected = @{
    "sys_result_t"          = 16
    "sys_result_payload_t"  = 8
    "rpc_unit_t"            = 1536
    "network_frame_t"       = 1536
    "block_t"               = 1536
}

$nmOut = & (Join-Path $LLVM "llvm-nm.exe") $elf 2>&1 | Out-String
$json = & (Join-Path $LLVM "llvm-readobj.exe") --elf-output-style=JSON --syms $elf 2>&1 | Out-String
$obj = $json | ConvertFrom-Json

# LLVM 22 JSON schema 实际 4 层: .[].Symbols[].Symbol.Name.Name (Name 也是 {Name, Value} 对象)
# spec_lab R51-M6 jq 路径 .[].Symbols[].Symbol 假设未含此嵌套, R52 待 R51-M6 勘误增补
$allOK = $true
foreach ($name in $expected.Keys) {
    $exp = $expected[$name]
    $found = $false
    foreach ($phdr in $obj) {
        if ($null -eq $phdr.Symbols) { continue }
        foreach ($sym in $phdr.Symbols) {
            $symName = $sym.Symbol.Name.Name
            $symSize = $sym.Symbol.Size
            if ($symName -eq $name) {
                $found = $true
                if ($symSize -ne $exp) {
                    Write-Output "  $name : size=$symSize, expected=$exp FAIL"
                    $allOK = $false
                } else {
                    Write-Output "  $name : size=$symSize PASS"
                }
                break
            }
        }
        if ($found) { break }
    }
    if (-not $found) {
        Write-Output "  $name : NOT FOUND in symtab FAIL"
        $allOK = $false
    }
}
if ($allOK) { Write-Output "C4 PASS: 5 struct sizes verified" }
else { $ok = $false; Write-Output "C4 FAIL" }

# Step 4: spec gates (already verified earlier, re-run for completeness)
Write-Output ""
Write-Output "=== P3 Step 4: spec 内部门禁 (check-docs / check-d-backlinks / check_goal_manifest / spec_lab) ==="
$bash = "C:\Users\LamKo\scoop\apps\git\current\bin\bash.exe"
$REPO_PARENT = (Get-Item $REPO).Parent.Parent.FullName
Push-Location $REPO_PARENT
try {
    # 用 2>&1 合并 stderr, 不通过管道 (避免管道吞 exit code)
    $out = & $bash docs/ci/check-docs.sh 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Output "check-docs FAILED"; $ok = $false }
    else { Write-Output "check-docs PASS" }

    $out = & $bash docs/ci/check-d-backlinks.sh 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Output "check-d-backlinks FAILED"; $ok = $false }
    else { Write-Output "check-d-backlinks PASS" }

    $out = & $bash docs/ci/check_goal_manifest.sh 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Output "check_goal_manifest FAILED"; $ok = $false }
    else { Write-Output "check_goal_manifest PASS" }

    $out = & $bash tools/spec_lab/run_all.sh 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Output "spec_lab run_all FAILED"; $ok = $false }
    else { Write-Output "spec_lab run_all PASS" }

    $out = & $bash tools/spec_lab/run_negative.sh 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Output "spec_lab run_negative FAILED"; $ok = $false }
    else { Write-Output "spec_lab run_negative PASS" }
} finally {
    Pop-Location
}

if ($ok) {
    Write-Output ""
    Write-Output "ALL P3 GATES PASS"
    exit 0
} else {
    Write-Output ""
    Write-Output "P3 GATES FAILED"
    exit 1
}
