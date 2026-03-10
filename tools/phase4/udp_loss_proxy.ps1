param(
	[int]$ListenPort,
	[string]$ServerHost = "127.0.0.1",
	[int]$ServerPort,
	[double]$LossPercentClientToServer = 0,
	[double]$LossPercentServerToClient = -1,
	[int]$BaseDelayMs = 0,
	[int]$JitterMs = 0,
	[int]$PollSleepMs = 2,
	[int]$Seed = 0,
	[string]$StopFilePath = "",
	[string]$StatsFilePath = ""
)

$ErrorActionPreference = "Stop"

if ($ListenPort -le 0 -or $ListenPort -gt 65535) {
	throw "Invalid ListenPort: $ListenPort"
}
if ($ServerPort -le 0 -or $ServerPort -gt 65535) {
	throw "Invalid ServerPort: $ServerPort"
}
if ($LossPercentServerToClient -lt 0) {
	$LossPercentServerToClient = $LossPercentClientToServer
}
if ($LossPercentClientToServer -lt 0 -or $LossPercentClientToServer -gt 100) {
	throw "LossPercentClientToServer must be between 0 and 100"
}
if ($LossPercentServerToClient -lt 0 -or $LossPercentServerToClient -gt 100) {
	throw "LossPercentServerToClient must be between 0 and 100"
}
if ($BaseDelayMs -lt 0) {
	throw "BaseDelayMs must be >= 0"
}
if ($JitterMs -lt 0) {
	throw "JitterMs must be >= 0"
}
if ($PollSleepMs -lt 0) {
	throw "PollSleepMs must be >= 0"
}

function New-EndpointClone {
	param([System.Net.IPEndPoint]$Endpoint)

	if ($null -eq $Endpoint) {
		return $null
	}

	return New-Object System.Net.IPEndPoint($Endpoint.Address, $Endpoint.Port)
}

function Should-Drop {
	param(
		[double]$LossPercent,
		[System.Random]$Random
	)

	if ($LossPercent -le 0) {
		return $false
	}
	if ($LossPercent -ge 100) {
		return $true
	}
	return (($Random.NextDouble() * 100.0) -lt $LossPercent)
}

function Compute-DelayMs {
	param(
		[int]$BaseDelayMs,
		[int]$JitterMs,
		[System.Random]$Random
	)

	$delay = $BaseDelayMs
	if ($JitterMs -gt 0) {
		$delay += $Random.Next(-$JitterMs, $JitterMs + 1)
	}
	if ($delay -lt 0) {
		$delay = 0
	}
	return $delay
}

function Write-Stats {
	param(
		[string]$StatsFilePath,
		[hashtable]$Stats,
		[double]$LossPercentClientToServer,
		[double]$LossPercentServerToClient,
		[System.Net.IPEndPoint]$LastClient
	)

	if (-not $StatsFilePath) {
		return
	}

	$statsDir = Split-Path -Parent $StatsFilePath
	if ($statsDir) {
		New-Item -ItemType Directory -Force -Path $statsDir | Out-Null
	}

	$totalIn = [int]$Stats.c2s_in + [int]$Stats.s2c_in
	$totalForward = [int]$Stats.c2s_forward + [int]$Stats.s2c_forward
	$totalDrop = [int]$Stats.c2s_drop + [int]$Stats.s2c_drop + [int]$Stats.queue_drop
	$lastClientText = ""
	if ($LastClient) {
		$lastClientText = $LastClient.ToString()
	}

	@(
		"started_utc=$($Stats.started_utc)"
		"now_utc=$((Get-Date).ToUniversalTime().ToString('o'))"
		"listen_port=$($Stats.listen_port)"
		"server=$($Stats.server)"
		"loss_percent_c2s=$LossPercentClientToServer"
		"loss_percent_s2c=$LossPercentServerToClient"
		"c2s_in=$($Stats.c2s_in)"
		"c2s_forward=$($Stats.c2s_forward)"
		"c2s_drop=$($Stats.c2s_drop)"
		"s2c_in=$($Stats.s2c_in)"
		"s2c_forward=$($Stats.s2c_forward)"
		"s2c_drop=$($Stats.s2c_drop)"
		"queue_drop=$($Stats.queue_drop)"
		"total_in=$totalIn"
		"total_forward=$totalForward"
		"total_drop=$totalDrop"
		"last_client=$lastClientText"
	) | Set-Content -Path $StatsFilePath -Encoding ascii
}

$serverAddress = [System.Net.Dns]::GetHostAddresses($ServerHost) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | Select-Object -First 1
if ($null -eq $serverAddress) {
	throw "Could not resolve IPv4 address for server host: $ServerHost"
}
$serverEndpoint = New-Object System.Net.IPEndPoint($serverAddress, $ServerPort)

$rand = if ($Seed -ne 0) { New-Object System.Random($Seed) } else { New-Object System.Random }
$queue = New-Object "System.Collections.Generic.List[object]"
$maxQueueItems = 8192

$stats = @{
	started_utc = (Get-Date).ToUniversalTime().ToString("o")
	listen_port = $ListenPort
	server = "$serverAddress`:$ServerPort"
	c2s_in = 0
	c2s_forward = 0
	c2s_drop = 0
	s2c_in = 0
	s2c_forward = 0
	s2c_drop = 0
	queue_drop = 0
}

$clientSocket = $null
$serverSocket = $null
$lastClient = $null
$lastStatsFlush = [DateTime]::UtcNow

try {
	$clientSocket = New-Object System.Net.Sockets.UdpClient($ListenPort)
	$clientSocket.Client.Blocking = $false

	$serverSocket = New-Object System.Net.Sockets.UdpClient(0)
	$serverSocket.Client.Blocking = $false

	Write-Output ("udp-loss-proxy listen={0} server={1}:{2} loss_c2s={3}% loss_s2c={4}% delay={5} jitter={6}" -f $ListenPort, $serverAddress, $ServerPort, $LossPercentClientToServer, $LossPercentServerToClient, $BaseDelayMs, $JitterMs)

	while ($true) {
		if ($StopFilePath -and (Test-Path $StopFilePath)) {
			break
		}

		# Client -> Server
		while ($true) {
			$clientSource = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
			$packet = $null
			try {
				$packet = $clientSocket.Receive([ref]$clientSource)
			}
			catch [System.Net.Sockets.SocketException] {
				if ($_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::WouldBlock) {
					break
				}
				throw
			}

			$stats.c2s_in++
			$lastClient = New-EndpointClone -Endpoint $clientSource

			if (Should-Drop -LossPercent $LossPercentClientToServer -Random $rand) {
				$stats.c2s_drop++
				continue
			}

			if ($queue.Count -ge $maxQueueItems) {
				$stats.queue_drop++
				continue
			}

			$dataCopy = New-Object byte[] $packet.Length
			[Array]::Copy($packet, $dataCopy, $packet.Length)
			$delay = Compute-DelayMs -BaseDelayMs $BaseDelayMs -JitterMs $JitterMs -Random $rand
			$due = [DateTime]::UtcNow.AddMilliseconds($delay)
			$queue.Add([pscustomobject]@{
				direction = "c2s"
				due = $due
				socket = $serverSocket
				target = $serverEndpoint
				data = $dataCopy
			})
		}

		# Server -> Client
		while ($true) {
			$serverSource = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
			$packet = $null
			try {
				$packet = $serverSocket.Receive([ref]$serverSource)
			}
			catch [System.Net.Sockets.SocketException] {
				if ($_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::WouldBlock) {
					break
				}
				throw
			}

			$stats.s2c_in++
			if ($null -eq $lastClient) {
				$stats.s2c_drop++
				continue
			}

			if (Should-Drop -LossPercent $LossPercentServerToClient -Random $rand) {
				$stats.s2c_drop++
				continue
			}

			if ($queue.Count -ge $maxQueueItems) {
				$stats.queue_drop++
				continue
			}

			$dataCopy = New-Object byte[] $packet.Length
			[Array]::Copy($packet, $dataCopy, $packet.Length)
			$delay = Compute-DelayMs -BaseDelayMs $BaseDelayMs -JitterMs $JitterMs -Random $rand
			$due = [DateTime]::UtcNow.AddMilliseconds($delay)
			$queue.Add([pscustomobject]@{
				direction = "s2c"
				due = $due
				socket = $clientSocket
				target = $lastClient
				data = $dataCopy
			})
		}

		$now = [DateTime]::UtcNow
		for ($i = $queue.Count - 1; $i -ge 0; $i--) {
			$item = $queue[$i]
			if ($item.due -gt $now) {
				continue
			}

			try {
				$item.socket.Send($item.data, $item.data.Length, $item.target) | Out-Null
				if ($item.direction -eq "c2s") {
					$stats.c2s_forward++
				}
				else {
					$stats.s2c_forward++
				}
			}
			catch {
				$stats.queue_drop++
			}
			finally {
				$queue.RemoveAt($i)
			}
		}

		if (($now - $lastStatsFlush).TotalSeconds -ge 1.0) {
			Write-Stats -StatsFilePath $StatsFilePath -Stats $stats -LossPercentClientToServer $LossPercentClientToServer -LossPercentServerToClient $LossPercentServerToClient -LastClient $lastClient
			$lastStatsFlush = $now
		}

		if ($PollSleepMs -gt 0) {
			Start-Sleep -Milliseconds $PollSleepMs
		}
	}
}
finally {
	if ($clientSocket) {
		$clientSocket.Close()
	}
	if ($serverSocket) {
		$serverSocket.Close()
	}

	Write-Stats -StatsFilePath $StatsFilePath -Stats $stats -LossPercentClientToServer $LossPercentClientToServer -LossPercentServerToClient $LossPercentServerToClient -LastClient $lastClient
}
