<#
.SYNOPSIS
    Fast parallel IPv4 subnet scanner for Windows PowerShell 5.1.

.DESCRIPTION
    Scans an IPv4 subnet and reports hosts that respond to ICMP echo (ping).
    Work is parallelized using ThreadJob for speed. Ping timeout and concurrency
    are configurable.

    Input formats supported:
      - "192.168.1"        (treated as 192.168.1.0/24)
      - "192.168.1.0/24"   (CIDR)
      - "10.0.0.5/32"      (single host)
      - "10.0.0.0/31"      (two hosts, point-to-point style)

.PARAMETER Subnet
    Subnet to scan. Mandatory.

    Accepts:
      - Three-octet /24 shorthand: 192.168.1
      - CIDR notation:            192.168.1.0/24

.PARAMETER Throttle
    Maximum number of concurrent ping operations.
    Default: 64 (range 1–256)

.PARAMETER TimeoutMs
    Ping timeout in milliseconds per host.
    Default: 600 (range 100–5000)

.PARAMETER NoDNS
    If specified, skip reverse DNS lookups.

.PARAMETER IncludeDown
    If specified, emit all scanned hosts, including those that do not respond.
    When not specified, only responding hosts are emitted.

.EXAMPLE
    .\subscan.ps1 -Subnet 192.168.1

.EXAMPLE
    .\subscan.ps1 -Subnet 192.168.1.0/24 -Throttle 96 -TimeoutMs 400 -NoDNS

.EXAMPLE
    .\subscan.ps1 -Subnet 10.0.0.0/23 -IncludeDown | Export-Csv .\scan.csv -NoTypeInformation

.OUTPUTS
    PSCustomObject:
      IP       (string)
      Name     (string|null)  # unless -NoDNS or host is down
      Response (bool)
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Subnet,

    [ValidateRange(1,256)]
    [int]$Throttle = 64,

    [ValidateRange(100,5000)]
    [int]$TimeoutMs = 600,

    [switch]$NoDNS,

    [switch]$IncludeDown
)

function Convert-IPv4ToUInt32 {
    param([Parameter(Mandatory=$true)][System.Net.IPAddress]$Ip)

    $b = $Ip.GetAddressBytes()
    if ($b.Length -ne 4) { throw "Only IPv4 is supported." }

    # bytes are network-order; convert to host-order UInt32
    return ([uint32]$b[0] -shl 24) -bor ([uint32]$b[1] -shl 16) -bor ([uint32]$b[2] -shl 8) -bor ([uint32]$b[3])
}

function Convert-UInt32ToIPv4String {
    param([Parameter(Mandatory=$true)][uint32]$Value)

    $b0 = ($Value -shr 24) -band 0xFF
    $b1 = ($Value -shr 16) -band 0xFF
    $b2 = ($Value -shr 8)  -band 0xFF
    $b3 = $Value -band 0xFF
    return "$b0.$b1.$b2.$b3"
}

function Get-IPv4TargetsFromSubnet {
    param([Parameter(Mandatory=$true)][string]$Subnet)

    # Support shorthand "192.168.1" => "192.168.1.0/24"
    if ($Subnet -match '^\d{1,3}(\.\d{1,3}){2}$') {
        $Subnet = "$Subnet.0/24"
    }

    if ($Subnet -notmatch '^(\d{1,3}(\.\d{1,3}){3})\/(\d|[12]\d|3[0-2])$') {
        throw "Invalid Subnet format. Use '192.168.1' or CIDR like '192.168.1.0/24'."
    }

    $ipStr = $matches[1]
    $prefix = [int]$matches[3]

    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($ipStr, [ref]$ip)) {
        throw "Invalid IP address: $ipStr"
    }

	# Convert IP to uint32
	$ipU = Convert-IPv4ToUInt32 -Ip $ip

	# Build mask in UInt64 without hex literals (PS5.1-safe)
	$mask64 = if ($prefix -eq 0) {
		[uint64]0
	} else {
		# (2^32 - 1) XOR (2^(32-prefix) - 1)  => top prefix bits set
		$all32 = [uint64]([math]::Pow(2,32) - 1)
		$lowBits = [uint64]([math]::Pow(2,(32 - $prefix)) - 1)
		($all32 -bxor $lowBits)
	}

	$mask = [uint32]$mask64

	$network   = [uint32]($ipU -band $mask)
	$wildcard  = [uint32]($mask64 -bxor ([uint64]([math]::Pow(2,32) - 1)))
	$broadcast = [uint32](([uint64]$network -bor $wildcard))


    # Decide host range
    if ($prefix -eq 32) {
        $start = $network
        $end = $network
    }
    elseif ($prefix -eq 31) {
        # point-to-point: both addresses usable
        $start = $network
        $end = $broadcast
    }
    else {
        # typical subnet: skip network + broadcast
        $start = $network + 1
        $end = $broadcast - 1
        if ($end -lt $start) { return @() }
    }

    $count = [int64]($end - $start + 1)
    if ($count -gt 131072) {
        throw "Subnet expands to $count hosts. Refusing to scan that many in one run."
    }

    $targets = New-Object System.Collections.Generic.List[string]
    for ($v = $start; $v -le $end; $v++) {
        $targets.Add((Convert-UInt32ToIPv4String -Value ([uint32]$v)))
    }
    return $targets
}

Import-Module ThreadJob -ErrorAction Stop

$targets = Get-IPv4TargetsFromSubnet -Subnet $Subnet

$jobs = $targets | ForEach-Object {
    Start-ThreadJob -ThrottleLimit $Throttle -ArgumentList $_, $TimeoutMs, $NoDNS.IsPresent, $IncludeDown.IsPresent -ScriptBlock {
        param($ip, $TimeoutMs, $NoDNS, $IncludeDown)

        $alive = $false
        try {
            $p = New-Object System.Net.NetworkInformation.Ping
            $reply = $p.Send($ip, $TimeoutMs)
            if ($reply -and $reply.Status -eq 'Success') { $alive = $true }
        } catch { $alive = $false }

        if ($alive -or $IncludeDown) {
            $name = $null
            if ($alive -and -not $NoDNS) {
                try {
                    $name = (Resolve-DnsName -Name $ip -ErrorAction Stop -QuickTimeout |
                             Select-Object -ExpandProperty NameHost -First 1)
                } catch {}
            }

            [pscustomobject]@{
                IP       = $ip
                Name     = $name
                Response = $alive
            }
        }
    }
}

Receive-Job -Job $jobs -Wait -AutoRemoveJob | Sort-Object IP
