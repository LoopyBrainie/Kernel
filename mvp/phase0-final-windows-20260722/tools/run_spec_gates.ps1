# tools/run_spec_gates.ps1 — P3 spec 内部门禁 (C5)
#
# 跑 docs/ci/ 三个 + tools/spec_lab/ 两个, 全过即 PASS.
# 注: 这些是 spec 内部一致性检查, 不依赖本机实现.
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File tools/run_spec_gates.ps1 [-RepoRoot D:\myProject\Kernel]

param(
    [string]$RepoRoot = "D:\myProject\Kernel"
)

$BASH = "C:\Users\LamKo\scoop\apps\git\current\bin\bash.exe"

# 路径标准化 (用 / 分隔符兼容 Git Bash cygwin)
$RepoRootFwd = $RepoRoot -replace "\\","/"

Write-Output "=== check-docs.sh ==="
& $BASH "$RepoRootFwd/docs/ci/check-docs.sh"
if ($LASTEXITCODE -ne 0) { Write-Output "check-docs FAILED rc=$LASTEXITCODE"; exit $LASTEXITCODE }

Write-Output ""
Write-Output "=== check-d-backlinks.sh ==="
& $BASH "$RepoRootFwd/docs/ci/check-d-backlinks.sh"
if ($LASTEXITCODE -ne 0) { Write-Output "check-d-backlinks FAILED rc=$LASTEXITCODE"; exit $LASTEXITCODE }

Write-Output ""
Write-Output "=== check_goal_manifest.sh ==="
& $BASH "$RepoRootFwd/docs/ci/check_goal_manifest.sh"
if ($LASTEXITCODE -ne 0) { Write-Output "check_goal_manifest FAILED rc=$LASTEXITCODE"; exit $LASTEXITCODE }

Write-Output ""
Write-Output "=== spec_lab run_all.sh ==="
& $BASH "$RepoRootFwd/tools/spec_lab/run_all.sh"
if ($LASTEXITCODE -ne 0) { Write-Output "spec_lab run_all FAILED rc=$LASTEXITCODE"; exit $LASTEXITCODE }

Write-Output ""
Write-Output "=== spec_lab run_negative.sh ==="
& $BASH "$RepoRootFwd/tools/spec_lab/run_negative.sh"
if ($LASTEXITCODE -ne 0) { Write-Output "spec_lab run_negative FAILED rc=$LASTEXITCODE"; exit $LASTEXITCODE }

Write-Output ""
Write-Output "ALL SPEC GATES PASS (5/5)"
exit 0
