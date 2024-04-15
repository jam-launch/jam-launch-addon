<#
.Description
Runs the provided command with a timeout. First arg is timeout in seconds,
remaining args are the command to run.
#>

$jobArgs = @( $args | Select-Object -Skip 1 )
$timeoutSeconds = $args[0]
$wrapped = {
    Write-Output "Running: $using:jobArgs"
    powershell.exe -Command "$using:jobArgs"
}
Write-Output "Starting command with timeout of ${timeoutSeconds} seconds..."
$j = Start-Job -ScriptBlock $wrapped
if (Wait-Job $j -Timeout $timeoutSeconds) {
    Receive-Job $j
    Write-Output "Finished command before timeout"
    Remove-Job -force $j
    exit 0
}
else {
    Receive-Job $j
    Write-Output "ERROR: timed out after ${timeoutSeconds} seconds!"
    Remove-Job -force $j
    exit 1
}
