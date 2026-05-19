# Windows OSC 777 emitter for Warp. Walks parent processes, AttachConsole, writes bytes.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Title,
    [Parameter(Mandatory = $true)] [string] $Body,
    [int] $MaxDepth = 12
)

$ErrorActionPreference = 'SilentlyContinue'

$DebugLog = if ($env:WARP_NOTIFY_LOG) { $env:WARP_NOTIFY_LOG } else { Join-Path $HOME ".warp-notify-debug.log" }
$DebugEnabled = if ($env:WARP_NOTIFY_DEBUG) { $env:WARP_NOTIFY_DEBUG -eq '1' } else { $true }

function Write-DebugLine([string]$msg) {
    if (-not $DebugEnabled) { return }
    try {
        $line = "[{0}] [ps-pid={1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $msg
        Add-Content -Path $DebugLog -Value $line -ErrorAction SilentlyContinue
    } catch {}
}

Write-DebugLine "ENTRY Title='$Title' Body-len=$($Body.Length)"

$signature = @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool AttachConsole(uint dwProcessId);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool FreeConsole();
[DllImport("kernel32.dll", SetLastError = true)] public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool WriteConsoleW(System.IntPtr hConsoleOutput, string lpBuffer, uint nNumberOfCharsToWrite, out uint lpNumberOfCharsWritten, System.IntPtr lpReserved);
'@

try { Add-Type -Namespace WarpNotify -Name Native -MemberDefinition $signature } catch { Write-DebugLine "Add-Type FAILED: $_" }

function Get-ParentChain([int]$StartPid, [int]$Depth) {
    $list = New-Object System.Collections.Generic.List[psobject]
    $cur = $StartPid
    for ($i = 0; $i -lt $Depth; $i++) {
        if ($cur -le 1) { break }
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $cur"
        if (-not $proc) { break }
        $parent = [int]$proc.ParentProcessId
        if ($parent -le 1 -or $parent -eq $cur) { break }
        $pname = ''
        try { $pname = (Get-CimInstance Win32_Process -Filter "ProcessId = $parent").Name } catch {}
        $list.Add([pscustomobject]@{ Pid = $parent; Name = $pname })
        $cur = $parent
    }
    return ,$list
}

function Try-Attach([int]$TargetPid, [string]$Name, [string]$Sequence) {
    [void][WarpNotify.Native]::FreeConsole()
    $attached = [WarpNotify.Native]::AttachConsole([uint32]$TargetPid)
    if (-not $attached) {
        Write-DebugLine "AttachConsole($TargetPid '$Name') FAILED LastErr=$([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        return $false
    }
    try {
        $stdout = [WarpNotify.Native]::GetStdHandle(-11)
        $invalid = [System.IntPtr]::new(-1)
        if ($stdout -eq [System.IntPtr]::Zero -or $stdout -eq $invalid) {
            Write-DebugLine "GetStdHandle returned invalid handle for pid=$TargetPid"
            return $false
        }
        $written = [uint32]0
        $ok = [WarpNotify.Native]::WriteConsoleW($stdout, $Sequence, [uint32]$Sequence.Length, [ref]$written, [System.IntPtr]::Zero)
        Write-DebugLine "WriteConsoleW pid=$TargetPid name='$Name' ok=$ok written=$written"
        return ($ok -and $written -gt 0)
    }
    finally {
        [void][WarpNotify.Native]::FreeConsole()
    }
}

$esc = [char]0x1b
$bel = [char]0x07
$sequence = "$esc]777;notify;$Title;$Body$bel"

$chain = Get-ParentChain -StartPid ([int]$PID) -Depth $MaxDepth
Write-DebugLine ("PARENT_CHAIN=" + (($chain | ForEach-Object { "$($_.Pid):$($_.Name)" }) -join ' -> '))

foreach ($entry in $chain) {
    if (Try-Attach -TargetPid $entry.Pid -Name $entry.Name -Sequence $sequence) {
        Write-DebugLine "SUCCESS via pid=$($entry.Pid) name='$($entry.Name)'"
        exit 0
    }
}

Write-DebugLine "FALLTHROUGH no parent accepted; writing to stdout"
[Console]::Out.Write($sequence)
exit 0
