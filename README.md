# PowerShell Subnet Scanner

A fast, parallel IPv4 subnet scanner written for Windows PowerShell 5.1.

This script discovers live hosts on a subnet using ICMP (ping), with optional reverse DNS lookups, CIDR support, and configurable performance tuning. It is designed to be practical, dependency-light, and safe to run on real networks.

## Features

- Parallel scanning using ThreadJob
- Supports CIDR notation (192.168.1.0/24, 10.0.0.0/23)
- Supports shorthand /24 format (192.168.1)
- Configurable concurrency and ping timeout
- Optional reverse DNS lookups
- Optional inclusion of non-responding hosts
- Works in Windows PowerShell 5.1 (no PowerShell 7 required)
- No external tools or binaries required

## Requirements

- Windows PowerShell 5.1
- ThreadJob module (included by default on most modern Windows systems)

Verify availability:

`Get-Module ThreadJob -ListAvailable`

If needed:

`Install-Module ThreadJob -Scope CurrentUser`

## Usage

### Basic scan (responding hosts only)

`.\subscan.ps1 -Subnet 192.168.1`

Scans 192.168.1.0/24 and returns only hosts that respond to ping.

### CIDR scan with custom tuning

`.\subscan.ps1 -Subnet 192.168.1.0/24 -Throttle 96 -TimeoutMs 400`

Higher throttle and lower timeout for faster scans on reliable networks.

### Disable DNS lookups (fastest)

`.\subscan.ps1 -Subnet 10.0.0.0/23 -NoDNS`

Skips reverse DNS resolution entirely.

### Include non-responding hosts

`.\subscan.ps1 -Subnet 10.0.0.0/24 -IncludeDown`

Returns all scanned IPs, marking unreachable hosts with Response = False.

### Export results

`.\subscan.ps1 -Subnet 192.168.1 -IncludeDown | Export-Csv .\scan.csv -NoTypeInformation`

## Parameters

| Parameter | Description |
| --------- | ----------- |
| Subnet | Mandatory. Subnet to scan. Accepts 192.168.1 or CIDR notation. |
| Throttle | Maximum concurrent ping operations. Default: 64 |
| TimeoutMs | Ping timeout per host in milliseconds. Default: 600 |
| NoDNS | Skip reverse DNS lookups |
| IncludeDown | Emit non-responding hosts |

## Output

Each result is a PowerShell object with the following properties:

- IP – IPv4 address
- Name – Reverse DNS name (null if unavailable or -NoDNS)
- Response – True if host responded to ping

Example output:

```
IP            Name              Response
--            ----              --------
192.168.1.1   router.local      True
192.168.1.42  workstation.lab   True
192.168.1.99                    False
```

## Safety Notes

- Default limits prevent scanning extremely large subnets
- Tune Throttle conservatively on Wi-Fi or consumer routers
- Reverse DNS can introduce delays on networks without PTR records

## Why This Exists

This script is intended to be:

- Faster than native Test-Connection loops
- More predictable than GUI scanners
- Easier to audit and customize than third-party tools

It favors clarity and control over clever one-liners.

## License

MIT License.

## Author

Derek Wirch
https://fortypoundhead.com
