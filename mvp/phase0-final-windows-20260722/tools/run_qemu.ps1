# tools/run_qemu.ps1 — P2 QEMU 会话运行器
#
# 启动 QEMU rv64 virt, 跑 kernel.elf, 期望:
#   - OpenSBI banner
#   - "COSMO BOOT OK" marker (C4)
#   - "shell> " 提示符 ≥3 次 (C5)
#   - "error: code=%d sub=0x%04X node=0x%04X" 三字段 (D156, C6)
#   - "shutting down" + qemu exit=0 (C2 shutdown)
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File tools/run_qemu.ps1 `
#     -KernelPath zig-out/bin/kernel.elf `
#     -LogPath artifacts/qemu_session.log `
#     -RunId 1
#
# 注: qemu 11 默认 -bios = builtin (OpenSBI v1.x 内嵌), 不传 -bios.
#     R51-M5: 加 -no-reboot 让 SBI SRST 触发 QEMU 立即退出 0.

param(
    [Parameter(Mandatory=$true)]
    [string]$KernelPath,

    [Parameter(Mandatory=$true)]
    [string]$LogPath,

    [Parameter(Mandatory=$true)]
    [int]$RunId
)

$QEMU = "C:\Users\LamKo\scoop\apps\qemu\current\qemu-system-riscv64.exe"
$QEMU_LOG = $LogPath

if (-not (Test-Path $KernelPath)) {
    Write-Error "kernel not found: $KernelPath"
    exit 2
}

# 启动 QEMU, -no-reboot 让 SBI SRST 干净退出
$proc = Start-Process -FilePath $QEMU -ArgumentList @(
    "-machine", "virt",
    "-cpu", "rv64",
    "-m", "256M",
    "-smp", "1",
    "-kernel", $KernelPath,
    "-nographic",
    "-monitor", "none",
    "-no-reboot",
    "-append", "root=/dev/null"
) -NoNewWindow -PassThru -RedirectStandardOutput $LogPath -RedirectStandardError "$LogPath.stderr"

# 等待 shell 跑完 (Rust shell 跑 3 次命令后 shutdown)
$timeout = 30
$elapsed = 0
while (-not $proc.HasExited -and $elapsed -lt $timeout) {
    Start-Sleep -Seconds 1
    $elapsed++
}

if (-not $proc.HasExited) {
    Write-Warning "QEMU timeout after ${timeout}s, killing"
    Stop-Process -Id $proc.Id -Force
    exit 3
}

# 合并 stdout + stderr
if (Test-Path "$LogPath.stderr") {
    Get-Content "$LogPath.stderr" | Add-Content $LogPath
    Remove-Item "$LogPath.stderr"
}

$rc = $proc.ExitCode
Write-Output "run_id=$RunId exit_code=$rc log=$LogPath"

if ($rc -ne 0) {
    exit $rc
}
exit 0
