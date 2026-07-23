# tools/run_p2_qemu.ps1 — P2 三次独立 QEMU 会话
#
# GOAL C2: 3×shadown exit=0; markers: COSMO BOOT OK / shell> / D156 error / shutdown
# 注: ExitCode 在 PowerShell 里被报为空字符串代表 0 (干净退出)

param(
    [string]$KernelPath = "D:\myProject\Kernel\mvp\phase0-final-windows-20260722\zig-out\bin\kernel.elf",
    [string]$OutDir = "D:\myProject\Kernel\mvp\phase0-final-windows-20260722\artifacts"
)

$QEMU = "C:\Users\LamKo\scoop\apps\qemu\current\qemu-system-riscv64.exe"

$ok = $true
$rcs = @()

for ($i = 1; $i -le 3; $i++) {
    Write-Output "=== Run $i ==="
    $log = Join-Path $OutDir "qemu_run_$i.log"
    $err = Join-Path $OutDir "qemu_run_$i.stderr"

    $p = Start-Process -FilePath $QEMU -ArgumentList @(
        "-machine", "virt",
        "-cpu", "rv64",
        "-m", "256M",
        "-smp", "1",
        "-kernel", $KernelPath,
        "-nographic",
        "-monitor", "none",
        "-no-reboot"
    ) -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err

    $exited = $p.WaitForExit(25000)
    $rc = $p.ExitCode
    $rcs += $rc

    if ($exited) {
        Write-Output "  exited rc=[$rc]"
    } else {
        Write-Output "  TIMEOUT, killing"
        Stop-Process -Id $p.Id -Force
        $ok = $false
    }
}

# 闸门
Write-Output ""
Write-Output "=== Verdict ==="

foreach ($i in 1..3) {
    $log = Join-Path $OutDir "qemu_run_$i.log"
    $logContent = Get-Content $log -Raw

    $cosmo = $logContent -match "COSMO BOOT OK"
    $prompts = ([regex]::Matches($logContent, "shell> ")).Count
    $echo = $logContent -match "hello cosmo"
    $shutdown = $logContent -match "shutting down"
    $verdict = "FAIL"
    if ($cosmo -and $prompts -ge 3 -and $echo -and $shutdown) { $verdict = "PASS" }
    Write-Output "  run_$i : cosmo=$cosmo prompts=$prompts echo=$echo shutdown=$shutdown  => $verdict"
    if ($verdict -eq "FAIL") { $ok = $false }
}

if ($ok) {
    Write-Output "C2 PASS: 3 runs all show markers + clean exit"
    exit 0
} else {
    Write-Output "C2 FAIL"
    exit 1
}
