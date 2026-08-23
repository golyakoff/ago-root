param(
    [int]$ApiOperatorPid,
    [int]$ApiVisitorPid,
    [int]$WorkerPid,
    [int]$DurationSeconds = 280,
    [int]$IntervalSeconds = 5,
    [string]$OutPath = "resource-samples.csv"
)

"timestamp_utc,role,pid,cpu_seconds,working_set_mb,thread_count,handle_count" | Out-File -FilePath $OutPath -Encoding utf8

$deadline = (Get-Date).ToUniversalTime().AddSeconds($DurationSeconds)
$roles = @{ $ApiOperatorPid = "api-operator-5009"; $ApiVisitorPid = "api-visitor-5010"; $WorkerPid = "worker" }

while ((Get-Date).ToUniversalTime() -lt $deadline) {
    $ts = (Get-Date).ToUniversalTime().ToString("o")
    foreach ($procId in $roles.Keys) {
        try {
            $p = Get-Process -Id $procId -ErrorAction Stop
            $line = "$ts,$($roles[$procId]),$procId,$($p.CPU),$([math]::Round($p.WorkingSet64/1MB,2)),$($p.Threads.Count),$($p.HandleCount)"
        } catch {
            $line = "$ts,$($roles[$procId]),$procId,,,,"
        }
        Add-Content -Path $OutPath -Value $line
    }
    Start-Sleep -Seconds $IntervalSeconds
}
