param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('EnableCollection', 'EnableTransportation', 'EnableGong', 'EnableTenHourWar', 'Status', 'DisableAll')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$ServerRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ServerRoot 'mangosd.conf'
$MySqlPath = Join-Path $ServerRoot 'mysql5\bin\mysql.exe'
$MySqlDumpPath = Join-Path $ServerRoot 'mysql5\bin\mysqldump.exe'
$MySqlServerPath = Join-Path $ServerRoot 'mysql5\bin\mysqld.exe'
$BackupRoot = Join-Path $ServerRoot 'autobak\AQ事件控制'
$SqlRoot = Join-Path $ServerRoot 'sql'

function Get-DatabaseConnection {
    param([string]$DatabaseName)

    $line = Get-Content -LiteralPath $ConfigPath | Where-Object {
        $_ -match 'DatabaseInfo\s*=\s*"[^"]*;' + [regex]::Escape($DatabaseName) + '"'
    } | Select-Object -First 1

    if (-not $line) {
        throw "在 mangosd.conf 中找不到数据库 $DatabaseName 的连接配置。"
    }

    $value = [regex]::Match($line, '"([^"]+)"').Groups[1].Value
    $parts = $value -split ';'
    if ($parts.Count -lt 5) {
        throw "数据库 $DatabaseName 的连接配置格式无效。"
    }

    [pscustomobject]@{
        Host = $parts[0]
        Port = $parts[1]
        User = $parts[2]
        Password = $parts[3]
        Database = $parts[4]
    }
}

function ConvertTo-NativeArguments {
    param([string[]]$Arguments)

    $quotedArguments = foreach ($argument in $Arguments) {
        $text = [string]$argument
        if ($text -notmatch '[\s"]') {
            $text
            continue
        }

        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append('"')
        $slashes = 0
        foreach ($character in $text.ToCharArray()) {
            if ($character -eq '\') {
                $slashes++
                continue
            }
            if ($character -eq '"') {
                [void]$builder.Append(('\' * (($slashes * 2) + 1)))
                [void]$builder.Append('"')
                $slashes = 0
                continue
            }
            if ($slashes -gt 0) {
                [void]$builder.Append(('\' * $slashes))
                $slashes = 0
            }
            [void]$builder.Append($character)
        }
        if ($slashes -gt 0) {
            [void]$builder.Append(('\' * ($slashes * 2)))
        }
        [void]$builder.Append('"')
        $builder.ToString()
    }
    return [string]::Join(' ', [string[]]$quotedArguments)
}

function Invoke-MySql {
    param(
        [Parameter(Mandatory = $true)]$Connection,
        [Parameter(Mandatory = $true)][string]$Sql,
        [switch]$Batch,
        [switch]$NoHeader
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $sqlFile = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("cmangos_aq_{0}.sql" -f [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($sqlFile, $Sql, $utf8NoBom)
    $sourcePath = $sqlFile.Replace('\', '/')

    $arguments = @(
        '--default-character-set=utf8', '--protocol=tcp', '--connect-timeout=3',
        '-h', $Connection.Host, '-P', $Connection.Port,
        '-u', $Connection.User, '-D', $Connection.Database,
        '--execute', "source $sourcePath"
    )
    if ($Batch -or $NoHeader) {
        $arguments += '-B'
    }
    if ($NoHeader) {
        $arguments += '-N'
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $MySqlPath
    $startInfo.Arguments = ConvertTo-NativeArguments -Arguments $arguments
    $startInfo.WorkingDirectory = $ServerRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8NoBom
    $startInfo.StandardErrorEncoding = $utf8NoBom
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $oldPassword = $env:MYSQL_PWD
    try {
        try {
            $env:MYSQL_PWD = $Connection.Password
            if (-not $process.Start()) {
                throw '无法启动 mysql.exe 客户端。'
            }
        }
        finally {
            $env:MYSQL_PWD = $oldPassword
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $standardOutput = $stdoutTask.Result
        $standardError = $stderrTask.Result.Trim()

        if ($process.ExitCode -ne 0) {
            $detail = if ($standardError) { "；$standardError" } else { '' }
            throw "MySQL 命令失败，退出码：$($process.ExitCode)$detail"
        }
        if ($standardOutput) {
            Write-Output $standardOutput.TrimEnd([char[]]"`r`n")
        }
    }
    finally {
        $process.Dispose()
        Remove-Item -LiteralPath $sqlFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-AqWorldStateTokens {
    param($CharacterConnection)

    $result = Invoke-MySql -Connection $CharacterConnection -NoHeader -Sql @'
SELECT Data
FROM world_state
WHERE Id = 1;
'@
    $data = (@($result) -join '').Trim()
    if (-not $data) {
        return [string[]](@('0') * 35)
    }

    $tokens = [string[]]($data -split '\s+')
    if ($tokens.Count -ne 35) {
        throw "角色库 world_state.Id=1 包含 $($tokens.Count) 个字段，预期为 35；已拒绝修改。"
    }
    foreach ($token in $tokens) {
        if ($token -notmatch '^\d+$') {
            throw "角色库 world_state.Id=1 含有非数字字段 '$token'；已拒绝修改。"
        }
    }
    return $tokens
}

function Set-AqWorldState {
    param(
        $CharacterConnection,
        [ValidateRange(0, 5)][int]$Phase,
        [ValidateRange(0, 5)][int]$Phase2Tier,
        [uint64]$PhaseExpiresAt = 0,
        [switch]$ResetResourceCounters
    )

    $tokens = Get-AqWorldStateTokens -CharacterConnection $CharacterConnection
    $tokens[0] = [string]$Phase
    $tokens[1] = [string]$PhaseExpiresAt
    if ($ResetResourceCounters) {
        foreach ($index in 2..31) {
            $tokens[$index] = '0'
        }
    }
    $tokens[32] = [string]$Phase2Tier
    $tokens[33] = '0'
    # The exact meaning of field 35 is not confirmed for this Larmer build.
    # Preserve it verbatim: the tested core opens the wall by changing events,
    # not by changing this field.

    $data = [string]::Join(' ', $tokens)
    if ($data -notmatch '^\d+( \d+){34}$') {
        throw '生成的 AQ world_state 数据格式无效；已拒绝写入。'
    }

    Invoke-MySql -Connection $CharacterConnection -Sql @"
INSERT INTO world_state (Id, Data)
VALUES (1, '$data')
ON DUPLICATE KEY UPDATE Data = VALUES(Data);
"@
}

function Invoke-MySqlFile {
    param(
        [Parameter(Mandatory = $true)]$Connection,
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Batch,
        [switch]$NoHeader
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "找不到 SQL 文件：$Path"
    }
    $sql = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    Invoke-MySql -Connection $Connection -Sql $sql -Batch:$Batch -NoHeader:$NoHeader
}

function Get-DatabaseUnixTimestamp {
    param($Connection)

    $result = Invoke-MySql -Connection $Connection -NoHeader -Sql `
        'SELECT UNIX_TIMESTAMP();'
    $value = (@($result) -join '').Trim()
    if ($value -notmatch '^\d+$') {
        throw "MySQL 未返回有效的 Unix 时间戳：'$value'"
    }
    return [uint64]$value
}

function Set-AqServerControlledEvents {
    param($WorldConnection)

    Invoke-MySql -Connection $WorldConnection -Sql @'
UPDATE game_event
SET schedule_type = 0
WHERE entry BETWEEN 120 AND 127;
'@
}

function Set-ClosedGateConfiguration {
    param($WorldConnection)

    Invoke-MySql -Connection $WorldConnection -Sql @'
DELETE FROM game_event_gameobject
WHERE guid IN (49390,49391,49392,66334,66335,66336);

INSERT INTO game_event_gameobject (guid, event)
VALUES (49390,120),(49391,120),(49392,120),
       (49390,121),(49391,121),(49392,121),
       (49390,122),(49391,122),(49392,122);

UPDATE gameobject_template
SET data0 = 0
WHERE entry IN (180898,180899,180904)
  AND type = 0;

INSERT INTO gameobject_addon (guid, animprogress, state, StringId)
VALUES (49390,100,1,0),(49391,100,1,0),(49392,100,1,0)
ON DUPLICATE KEY UPDATE
    animprogress = VALUES(animprogress),
    state = VALUES(state),
    StringId = VALUES(StringId);
'@
}

function Clear-AqEventStatus {
    param($CharacterConnection)

    Invoke-MySql -Connection $CharacterConnection -Sql @'
DELETE FROM game_event_status
WHERE event BETWEEN 120 AND 135;
'@
}

function Test-MySql {
    param($Connection)

    $script:LastMySqlConnectionError = ''
    try {
        $result = Invoke-MySql -Connection $Connection -NoHeader -Sql 'SELECT 1;'
        if ((@($result) -join '').Trim() -eq '1') {
            return $true
        }
        $script:LastMySqlConnectionError = 'mysql.exe 退出成功，但 SELECT 1 未返回预期结果。'
        return $false
    }
    catch {
        $script:LastMySqlConnectionError = $_.Exception.Message
        return $false
    }
}

function Start-BundledMySql {
    param($Connection)

    if (Test-MySql -Connection $Connection) {
        return
    }
    if (Get-Process -Name 'mysqld' -ErrorAction SilentlyContinue) {
        throw "检测到 mysqld 正在运行，但脚本无法连接。实际错误：$script:LastMySqlConnectionError"
    }

    Write-Host 'MySQL 未响应，正在启动随服务端附带的 MySQL...'
    $serverProcess = Start-Process -FilePath $MySqlServerPath `
        -ArgumentList '--defaults-file=my.ini', '--console' `
        -WorkingDirectory $ServerRoot -WindowStyle Hidden -PassThru

    foreach ($attempt in 1..60) {
        Start-Sleep -Milliseconds 500
        if (Test-MySql -Connection $Connection) {
            Write-Host 'MySQL 已启动。'
            return
        }
        if ($serverProcess.HasExited) {
            break
        }
    }
    throw ('随附 MySQL 无法连接。实际错误：' + $script:LastMySqlConnectionError)
}

function Assert-WorldServerStopped {
    if (Get-Process -Name 'mangosd' -ErrorAction SilentlyContinue) {
        throw '检测到 mangosd 正在运行。请先正常关闭世界服务器，再执行阶段切换。'
    }
}

function Set-WarEffortCoreEnabled {
    param([bool]$Enabled)

    $originalBytes = [System.IO.File]::ReadAllBytes($ConfigPath)
    $byteEncoding = [System.Text.Encoding]::GetEncoding(28591)
    $config = $byteEncoding.GetString($originalBytes)
    $value = if ($Enabled) { '1' } else { '0' }
    $pattern = '(?m)^([ \t]*WarEffort\.Enable[ \t]*=[ \t]*)([01])([ \t]*)(?=\r?$)'
    $regex = [regex]::new($pattern)
    $matches = $regex.Matches($config)
    if ($matches.Count -ne 1) {
        throw 'mangosd.conf 中 WarEffort.Enable 的有效配置行数不是 1，已拒绝修改。'
    }
    if ($matches[0].Groups[2].Value -eq $value) {
        Write-Host "mangosd.conf 中 WarEffort.Enable 已经是 $value，未改写文件。"
        return
    }

    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $configBackup = Join-Path $BackupRoot "mangosd.conf_$stamp.bak"
    [System.IO.File]::WriteAllBytes($configBackup, $originalBytes)
    $updated = $regex.Replace(
        $config,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $match.Groups[1].Value + $value + $match.Groups[3].Value
        },
        1
    )
    $updatedBytes = $byteEncoding.GetBytes($updated)

    try {
        [System.IO.File]::WriteAllBytes($ConfigPath, $updatedBytes)
        $writtenBytes = [System.IO.File]::ReadAllBytes($ConfigPath)
        if ($writtenBytes.Length -ne $originalBytes.Length) {
            throw 'mangosd.conf 写后长度发生异常变化。'
        }
        $differentBytes = 0
        for ($index = 0; $index -lt $originalBytes.Length; $index++) {
            if ($originalBytes[$index] -ne $writtenBytes[$index]) {
                $differentBytes++
            }
        }
        if ($differentBytes -ne 1) {
            throw "mangosd.conf 写后有 $differentBytes 个字节发生变化，预期只改变 1 个字节。"
        }
    }
    catch {
        [System.IO.File]::WriteAllBytes($ConfigPath, $originalBytes)
        throw
    }
    Write-Host "WarEffort.Enable 已改为 $value；配置备份：$configBackup"
}

function Set-WarEffortRateOne {
    $originalBytes = [System.IO.File]::ReadAllBytes($ConfigPath)
    $byteEncoding = [System.Text.Encoding]::GetEncoding(28591)
    $config = $byteEncoding.GetString($originalBytes)
    $pattern = '(?m)^([ \t]*WarEffort\.Rates[ \t]*=[ \t]*)([0-9]+(?:\.[0-9]+)?)([ \t]*)(?=\r?$)'
    $regex = [regex]::new($pattern)
    $matches = $regex.Matches($config)
    if ($matches.Count -ne 1) {
        throw 'mangosd.conf 中 WarEffort.Rates 的有效配置行数不是 1，已拒绝修改。'
    }

    $valueGroup = $matches[0].Groups[2]
    if ($valueGroup.Value -eq '1') {
        Write-Host 'mangosd.conf 中 WarEffort.Rates 已经是 1，未改写文件。'
        return
    }

    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $configBackup = Join-Path $BackupRoot "mangosd.conf_rate_$stamp.bak"
    [System.IO.File]::WriteAllBytes($configBackup, $originalBytes)

    # ISO-8859-1 keeps a one-to-one mapping between characters and bytes.
    # Replace only the ASCII value bytes; preserve every other byte exactly.
    $valueOffset = $valueGroup.Index
    $oldValueLength = $valueGroup.Length
    $suffixOffset = $valueOffset + $oldValueLength
    $newLength = $originalBytes.Length - $oldValueLength + 1
    $updatedBytes = New-Object byte[] $newLength
    if ($valueOffset -gt 0) {
        [System.Buffer]::BlockCopy(
            $originalBytes, 0, $updatedBytes, 0, $valueOffset
        )
    }
    $updatedBytes[$valueOffset] = 0x31
    $suffixLength = $originalBytes.Length - $suffixOffset
    if ($suffixLength -gt 0) {
        [System.Buffer]::BlockCopy(
            $originalBytes, $suffixOffset, $updatedBytes,
            $valueOffset + 1, $suffixLength
        )
    }

    try {
        [System.IO.File]::WriteAllBytes($ConfigPath, $updatedBytes)
        $writtenBytes = [System.IO.File]::ReadAllBytes($ConfigPath)
        if ($writtenBytes.Length -ne $newLength) {
            throw 'mangosd.conf 写后长度与预期不符。'
        }
        for ($index = 0; $index -lt $valueOffset; $index++) {
            if ($writtenBytes[$index] -ne $originalBytes[$index]) {
                throw "mangosd.conf 在倍率值之前的字节 $index 发生意外变化。"
            }
        }
        if ($writtenBytes[$valueOffset] -ne 0x31) {
            throw 'mangosd.conf 中 WarEffort.Rates 未正确写为 1。'
        }
        for ($index = 0; $index -lt $suffixLength; $index++) {
            if ($writtenBytes[$valueOffset + 1 + $index] -ne
                $originalBytes[$suffixOffset + $index]) {
                throw "mangosd.conf 在倍率值之后的字节 $index 发生意外变化。"
            }
        }
    }
    catch {
        [System.IO.File]::WriteAllBytes($ConfigPath, $originalBytes)
        throw
    }

    Write-Host "WarEffort.Rates 已改为 1；配置备份：$configBackup"
}

function Invoke-AqDump {
    param(
        $Connection,
        [string]$BackupFile,
        [string]$Where,
        [string[]]$Tables
    )

    $oldPassword = $env:MYSQL_PWD
    try {
        $env:MYSQL_PWD = $Connection.Password
        & $MySqlDumpPath --default-character-set=utf8 --protocol=tcp `
            -h $Connection.Host -P $Connection.Port -u $Connection.User `
            --no-create-info --skip-triggers --where=$Where `
            $Connection.Database @Tables |
            Add-Content -LiteralPath $BackupFile -Encoding UTF8
        if ($LASTEXITCODE -ne 0) {
            throw "备份数据库表 $($Tables -join ',') 失败，退出码：$LASTEXITCODE"
        }
    }
    finally {
        $env:MYSQL_PWD = $oldPassword
    }
}

function Backup-AqState {
    param($WorldConnection, $CharacterConnection)

    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = Join-Path $BackupRoot "AQ_state_$stamp.sql"
    "-- AQ event control backup created $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |
        Set-Content -LiteralPath $backupFile -Encoding UTF8

    Invoke-AqDump -Connection $WorldConnection -BackupFile $backupFile `
        -Where 'entry BETWEEN 120 AND 135' -Tables @('game_event', 'game_event_time')
    Invoke-AqDump -Connection $WorldConnection -BackupFile $backupFile `
        -Where 'guid IN (49390,49391,49392,66334,66335,66336)' `
        -Tables @('gameobject', 'game_event_gameobject', 'gameobject_addon')
    Invoke-AqDump -Connection $WorldConnection -BackupFile $backupFile `
        -Where 'entry IN (176146,176147,176148,180898,180899,180904)' `
        -Tables @('gameobject_template')
    Invoke-AqDump -Connection $CharacterConnection -BackupFile $backupFile `
        -Where 'event BETWEEN 120 AND 135' -Tables @('game_event_status')
    Invoke-AqDump -Connection $CharacterConnection -BackupFile $backupFile `
        -Where 'Id = 1' -Tables @('world_state')

    Write-Host "备份已保存：$backupFile"
}

function Assert-CommendationSchema {
    param($WorldConnection)

    $result = Invoke-MySql -Connection $WorldConnection -NoHeader -Sql @'
SELECT COUNT(*)
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME='quest_template' AND COLUMN_NAME IN
       ('entry','Method','SpecialFlags','PrevQuestId','RequestItemsText',
        'ReqItemId1','ReqItemCount1','RewItemId1','RewItemCount1',
        'RewRepFaction1','RewRepValue1'))
    OR (TABLE_NAME='locales_quest' AND COLUMN_NAME IN
       ('entry','RequestItemsText_loc4'))
    OR (TABLE_NAME IN ('creature_questrelation','creature_involvedrelation')
        AND COLUMN_NAME IN ('id','quest')));
'@
    if ((@($result) -join '').Trim() -ne '17') {
        throw '当前世界库任务表结构与本 Classic 1.12 修复不匹配，已拒绝修改。'
    }

    $questCount = Invoke-MySql -Connection $WorldConnection -NoHeader -Sql @'
SELECT COUNT(*) FROM quest_template
WHERE entry IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845,
                8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);
'@
    if ((@($questCount) -join '').Trim() -ne '42') {
        throw '目标 AQ 徽章任务不是 42/42，已拒绝修改。'
    }

    $localeCount = Invoke-MySql -Connection $WorldConnection -NoHeader -Sql @'
SELECT COUNT(*) FROM locales_quest
WHERE entry IN (8811,8812,8813,8814,8815,8816,8817,8818,
                8819,8820,8821,8822,8823,8824,8825,8826,
                8830,8831,8832,8833,8834,8835,8836,8837,
                8838,8839,8840,8841,8842,8843,8844,8845);
'@
    if ((@($localeCount) -join '').Trim() -ne '32') {
        throw '目标 AQ 声望任务的简体中文记录不是 32/32，已拒绝修改。'
    }
}

function Backup-CommendationQuestState {
    param($WorldConnection)

    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $backupFile = Join-Path $BackupRoot "AQ_commendation_rollback_$stamp.sql"

    @"
-- Exact rollback generated before AQ commendation repair.
-- Created $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
USE ``$($WorldConnection.Database)``;
SET NAMES utf8;
DELETE FROM creature_questrelation WHERE quest IN
(8811,8812,8813,8814,8815,8816,8817,8818,8819,8820,8821,8822,8823,8824,8825,8826,
 8830,8831,8832,8833,8834,8835,8836,8837,8838,8839,8840,8841,8842,8843,8844,8845,
 8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);
DELETE FROM creature_involvedrelation WHERE quest IN
(8811,8812,8813,8814,8815,8816,8817,8818,8819,8820,8821,8822,8823,8824,8825,8826,
 8830,8831,8832,8833,8834,8835,8836,8837,8838,8839,8840,8841,8842,8843,8844,8845,
 8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);
DELETE FROM locales_quest WHERE entry IN
(8811,8812,8813,8814,8815,8816,8817,8818,8819,8820,8821,8822,8823,8824,8825,8826,
 8830,8831,8832,8833,8834,8835,8836,8837,8838,8839,8840,8841,8842,8843,8844,8845,
 8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);
DELETE FROM quest_template WHERE entry IN
(8811,8812,8813,8814,8815,8816,8817,8818,8819,8820,8821,8822,8823,8824,8825,8826,
 8830,8831,8832,8833,8834,8835,8836,8837,8838,8839,8840,8841,8842,8843,8844,8845,
 8846,8847,8848,8849,8850,8851,8852,8853,8854,8855);
"@ | Set-Content -LiteralPath $backupFile -Encoding UTF8

    $entryWhere = 'entry IN (8811,8812,8813,8814,8815,8816,8817,8818,8819,8820,8821,8822,8823,8824,8825,8826,8830,8831,8832,8833,8834,8835,8836,8837,8838,8839,8840,8841,8842,8843,8844,8845,8846,8847,8848,8849,8850,8851,8852,8853,8854,8855)'
    $questWhere = 'quest IN (8811,8812,8813,8814,8815,8816,8817,8818,8819,8820,8821,8822,8823,8824,8825,8826,8830,8831,8832,8833,8834,8835,8836,8837,8838,8839,8840,8841,8842,8843,8844,8845,8846,8847,8848,8849,8850,8851,8852,8853,8854,8855)'
    Invoke-AqDump -Connection $WorldConnection -BackupFile $backupFile `
        -Where $entryWhere -Tables @('quest_template','locales_quest')
    Invoke-AqDump -Connection $WorldConnection -BackupFile $backupFile `
        -Where $questWhere -Tables @('creature_questrelation','creature_involvedrelation')
    Write-Host "徽章任务精确回滚文件：$backupFile"
    return $backupFile
}

function Get-CommendationFixStatus {
    param($WorldConnection)

    $verifyPath = Join-Path $SqlRoot '04_verify_commendation_fix.sql'
    $output = @(Invoke-MySqlFile -Connection $WorldConnection -Path $verifyPath `
        -Batch -NoHeader) -join "`n"
    $values = @{}
    foreach ($line in ($output -split "`r?`n")) {
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2) {
            $values[$parts[0]] = $parts[1]
        }
    }
    foreach ($required in @('REP_CORRECT','REP_WRONG_IDS',
                             'SUPPLY_REPEATABLE','SUPPLY_DELIVERABLE',
                             'SUPPLY_WRONG_IDS')) {
        if (-not $values.ContainsKey($required)) {
            throw "徽章任务验证未返回 $required。"
        }
    }
    return [pscustomobject]@{
        ReputationCorrect = [int]$values['REP_CORRECT']
        ReputationWrongIds = $values['REP_WRONG_IDS']
        SupplyRepeatable = [int]$values['SUPPLY_REPEATABLE']
        SupplyDeliverable = [int]$values['SUPPLY_DELIVERABLE']
        SupplyWrongIds = $values['SUPPLY_WRONG_IDS']
    }
}

function Ensure-AqCommendationQuestFix {
    param($WorldConnection)

    Assert-CommendationSchema -WorldConnection $WorldConnection
    $before = Get-CommendationFixStatus -WorldConnection $WorldConnection
    if ($before.ReputationCorrect -eq 32 -and
        $before.SupplyRepeatable -eq 10 -and
        $before.SupplyDeliverable -eq 10) {
        Write-Host 'AQ 徽章任务修复已经完整，无须重复写入。'
        return
    }

    $rollbackFile = Backup-CommendationQuestState -WorldConnection $WorldConnection
    try {
        $applyPath = Join-Path $SqlRoot '03_apply_commendation_fix.sql'
        Invoke-MySqlFile -Connection $WorldConnection -Path $applyPath
        $after = Get-CommendationFixStatus -WorldConnection $WorldConnection
        if ($after.ReputationCorrect -ne 32 -or
            $after.SupplyRepeatable -ne 10 -or
            $after.SupplyDeliverable -ne 10) {
            throw ("应用后校验失败：声望 {0}/32；物资重复 {1}/10；可交付 {2}/10；错误任务 {3},{4}" -f
                $after.ReputationCorrect, $after.SupplyRepeatable,
                $after.SupplyDeliverable, $after.ReputationWrongIds,
                $after.SupplyWrongIds)
        }
        Write-Host 'AQ 徽章任务修复完成：声望 32/32；物资兑换 10/10。'
    }
    catch {
        $failure = $_.Exception.Message
        Write-Host '任务修复失败，正在自动恢复修改前数据...'
        try {
            Invoke-MySqlFile -Connection $WorldConnection -Path $rollbackFile
        }
        catch {
            throw "任务修复失败：$failure；自动回滚也失败：$($_.Exception.Message)；请保留 $rollbackFile。"
        }
        throw "任务修复失败且已自动回滚：$failure"
    }
}

function Format-AqTimer {
    param([uint64]$UnixTimestamp)

    if ($UnixTimestamp -eq 0) {
        return '0（不会自动推进）'
    }

    try {
        $expires = [DateTimeOffset]::FromUnixTimeSeconds([int64]$UnixTimestamp).ToLocalTime()
        $remaining = $expires - [DateTimeOffset]::Now
        if ($remaining.TotalSeconds -le 0) {
            $remainingText = '已到期'
        }
        elseif ($remaining.TotalDays -ge 1) {
            $days = [math]::Floor($remaining.TotalDays)
            $remainingText = ('{0}天 {1:hh\:mm\:ss}' -f $days, $remaining)
        }
        else {
            $remainingText = $remaining.ToString('hh\:mm\:ss')
        }
        return ('{0}（到期：{1}；剩余：{2}）' -f `
            $UnixTimestamp, $expires.ToString('yyyy-MM-dd HH:mm:ss zzz'), $remainingText)
    }
    catch {
        return "$UnixTimestamp（无法解析为 Unix 秒时间戳）"
    }
}

function Show-CoreIdentity {
    $exePath = Join-Path $ServerRoot 'mangosd.exe'
    $pdbPath = Join-Path $ServerRoot 'mangosd.pdb'
    if (-not (Test-Path -LiteralPath $exePath)) {
        Write-Host 'mangosd.exe：MISSING'
        return
    }

    $exe = Get-Item -LiteralPath $exePath
    Write-Host "mangosd.exe：$($exe.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))  $($exe.Length) bytes"
    $testedHash = 'FC4CEC8D5861DBEFEF34745434235B9F7531B5DAC580D8BAB80FB83F0F5811AC'
    $actualHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
    Write-Host "mangosd.exe SHA256：$actualHash"
    if (Test-Path -LiteralPath $pdbPath) {
        $pdb = Get-Item -LiteralPath $pdbPath
        Write-Host "mangosd.pdb：$($pdb.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))  $($pdb.Length) bytes"
        if ($pdb.LastWriteTime -ne $exe.LastWriteTime) {
            Write-Host '警告：EXE/PDB 时间不一致，不得把该 PDB 当作匹配符号进行二进制修改。'
        }
    }
    if ($actualHash -eq $testedHash) {
        Write-Host '敲锣流程：此 Larmer Build 已实测可由事件 122 自动进入事件 123 并开放大门。'
    }
    else {
        Write-Host '敲锣流程：当前 EXE 与已实测构建不同，请重新进行事件 122→123 游戏内验证。'
    }
}

function Show-Status {
    param($WorldConnection, $CharacterConnection)

    Write-Host ''
    Write-Host 'AQ 荣誉徽章与物资兑换任务：'
    try {
        Assert-CommendationSchema -WorldConnection $WorldConnection
        $questStatus = Get-CommendationFixStatus -WorldConnection $WorldConnection
        Write-Host "主城声望任务：$($questStatus.ReputationCorrect)/32 正确"
        if ($questStatus.ReputationCorrect -ne 32) {
            Write-Host "错误任务 ID：$($questStatus.ReputationWrongIds)"
        }
        Write-Host ("物资箱兑换任务：{0}/10 可重复，{1}/10 可交付" -f
            $questStatus.SupplyRepeatable, $questStatus.SupplyDeliverable)
        if ($questStatus.SupplyRepeatable -ne 10 -or
            $questStatus.SupplyDeliverable -ne 10) {
            Write-Host "错误任务 ID：$($questStatus.SupplyWrongIds)"
        }
    }
    catch {
        Write-Host "任务检查失败：$($_.Exception.Message)"
    }

    Write-Host ''
    Write-Host '世界库中的 AQ 事件定义：'
    Invoke-MySql -Connection $WorldConnection -Batch -Sql @'
SELECT entry AS event_id, schedule_type, description
FROM game_event
WHERE entry BETWEEN 120 AND 135
ORDER BY entry;
'@

    Write-Host ''
    Write-Host '角色库中的 AQ 持久事件（不等于服务器当前内存状态）：'
    Invoke-MySql -Connection $CharacterConnection -Batch -Sql @'
SELECT event AS active_event
FROM game_event_status
WHERE event BETWEEN 120 AND 135
ORDER BY event;
'@

    Write-Host ''
    Write-Host 'AQ 核心世界状态（classiccharacters.world_state.Id=1）：'
    try {
        $tokens = Get-AqWorldStateTokens -CharacterConnection $CharacterConnection
        $phaseNames = @{
            0 = '禁用'
            1 = '物资收集（事件 120）'
            2 = '物资运输（事件 121）'
            3 = '等待敲锣（事件 122）'
            4 = '十小时战争（事件 123）'
            5 = '完成（事件 124）'
        }
        $phase = [int]$tokens[0]
        $timer = [uint64]$tokens[1]
        $phaseName = if ($phaseNames.ContainsKey($phase)) { $phaseNames[$phase] } else { '未知' }
        if ($phase -in @(1, 2, 3)) {
            $gateText = '预期关闭（关门组绑定当前事件）'
        }
        elseif ($phase -in @(0, 4, 5)) {
            $gateText = '预期开放（关门组不在当前事件生成）'
        }
        else {
            $gateText = '未知'
        }
        Write-Host "字段数量：$($tokens.Count) / 35"
        Write-Host "核心阶段：$phase - $phaseName"
        Write-Host "阶段计时器：$(Format-AqTimer -UnixTimestamp $timer)"
        Write-Host "运输物资层级：$($tokens[32])"
        Write-Host "甲虫之墙状态（按阶段与事件绑定推断）：$gateText"
        Write-Host "扩展字段（第 35 字段）：$($tokens[34])（用途未确认；脚本保持原值）"
    }
    catch {
        Write-Host "AQ 核心世界状态无效：$($_.Exception.Message)"
    }

    Write-Host ''
    Write-Host '关门组和事件绑定：'
    Invoke-MySql -Connection $WorldConnection -Batch -Sql @'
SELECT g.guid, g.id AS template_id, gt.displayId,
       COALESCE(ga.state, -1) AS spawn_state,
       COALESCE(GROUP_CONCAT(geg.event ORDER BY geg.event), 'always') AS event_binding,
       gt.name
FROM gameobject g
JOIN gameobject_template gt ON gt.entry = g.id
LEFT JOIN gameobject_addon ga ON ga.guid = g.guid
LEFT JOIN game_event_gameobject geg ON geg.guid = g.guid
WHERE g.guid IN (49390,49391,49392,66334,66335,66336)
GROUP BY g.guid, g.id, gt.displayId, ga.state, gt.name
ORDER BY g.guid;
'@

    Write-Host ''
    Write-Host '事件 123 数据量（不会重新创建）：'
    Invoke-MySql -Connection $WorldConnection -Batch -Sql @'
SELECT 'creature' AS object_type,
       SUM(CASE WHEN event = 123 THEN 1 ELSE 0 END) AS spawned,
       SUM(CASE WHEN event = -123 THEN 1 ELSE 0 END) AS removed
FROM game_event_creature WHERE ABS(event) = 123
UNION ALL
SELECT 'gameobject',
       SUM(CASE WHEN event = 123 THEN 1 ELSE 0 END),
       SUM(CASE WHEN event = -123 THEN 1 ELSE 0 END)
FROM game_event_gameobject WHERE ABS(event) = 123;
'@

    Write-Host ''
    Write-Host '敲锣任务与世界广播资源：'
    Invoke-MySql -Connection $WorldConnection -Batch -Sql @'
SELECT 'quest_event' AS record_type, quest AS id,
       GROUP_CONCAT(event ORDER BY event) AS value_text
FROM game_event_quest WHERE quest = 8743 GROUP BY quest
UNION ALL
SELECT 'broadcast_text', Id,
       CONCAT('ChatType=', ChatTypeID, ' ', LEFT(Text, 90))
FROM broadcast_text WHERE Id IN (11427,11432)
ORDER BY record_type, id;
'@

    Write-Host ''
    $warEffortSettings = Get-Content -LiteralPath $ConfigPath |
        Where-Object { $_ -match '^\s*WarEffort\.(Enable|Rates)\s*=' }
    Write-Host '战争物资核心配置：'
    $warEffortSettings | ForEach-Object { Write-Host $_ }
    Show-CoreIdentity

    $dbcPath = Join-Path $ServerRoot 'data\dbc\GameObjectDisplayInfo.dbc'
    $vmapModelPath = Join-Path $ServerRoot 'data\vmaps\temp_gameobject_models'
    Write-Host "GameObjectDisplayInfo.dbc：$(if (Test-Path -LiteralPath $dbcPath) { 'OK' } else { 'MISSING' })"
    Write-Host "temp_gameobject_models：$(if (Test-Path -LiteralPath $vmapModelPath) { 'OK' } else { 'MISSING' })"

    if (Get-Process -Name 'mangosd' -ErrorAction SilentlyContinue) {
        Write-Host 'mangosd 正在运行；最终内存状态请在服务器控制台执行：event list'
    }
    else {
        Write-Host 'mangosd 未运行；数据库不能证明当前内存事件。'
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath) -or
    -not (Test-Path -LiteralPath $MySqlPath) -or
    -not (Test-Path -LiteralPath $MySqlDumpPath)) {
    throw '脚本必须放在含 mangosd.conf 和 mysql5 目录的服务端根目录。'
}

$world = Get-DatabaseConnection -DatabaseName 'classicmangos'
$characters = Get-DatabaseConnection -DatabaseName 'classiccharacters'
Start-BundledMySql -Connection $world

switch ($Action) {
    'Status' {
        Show-Status -WorldConnection $world -CharacterConnection $characters
    }
    'EnableCollection' {
        Assert-WorldServerStopped
        Backup-AqState -WorldConnection $world -CharacterConnection $characters
        Ensure-AqCommendationQuestFix -WorldConnection $world
        Set-AqServerControlledEvents -WorldConnection $world
        Set-ClosedGateConfiguration -WorldConnection $world
        Set-WarEffortRateOne
        Set-WarEffortCoreEnabled -Enabled $true
        Set-AqWorldState -CharacterConnection $characters -Phase 1 `
            -Phase2Tier 0 -ResetResourceCounters
        Clear-AqEventStatus -CharacterConnection $characters
        Write-Host ''
        Write-Host '物资收集阶段已配置：启动 mangosd 后核心将激活事件 120。'
        Write-Host '关门组 49390-49392 将随事件 120 生成为关闭状态。'
        Show-Status -WorldConnection $world -CharacterConnection $characters
    }
    'EnableTransportation' {
        Assert-WorldServerStopped
        Backup-AqState -WorldConnection $world -CharacterConnection $characters
        Ensure-AqCommendationQuestFix -WorldConnection $world
        Set-AqServerControlledEvents -WorldConnection $world
        Set-ClosedGateConfiguration -WorldConnection $world
        Set-WarEffortRateOne
        Set-WarEffortCoreEnabled -Enabled $true
        Set-AqWorldState -CharacterConnection $characters -Phase 2 `
            -Phase2Tier 5
        Clear-AqEventStatus -CharacterConnection $characters
        Write-Host ''
        Write-Host '物资运输阶段已配置：启动 mangosd 后核心将激活事件 121。'
        Write-Host '计时器为 0，会一直停留在 121；关门组随事件 121 生成。'
        Show-Status -WorldConnection $world -CharacterConnection $characters
    }
    'EnableGong' {
        Assert-WorldServerStopped
        Backup-AqState -WorldConnection $world -CharacterConnection $characters
        Ensure-AqCommendationQuestFix -WorldConnection $world
        Set-AqServerControlledEvents -WorldConnection $world
        Set-ClosedGateConfiguration -WorldConnection $world
        Set-WarEffortRateOne
        Set-WarEffortCoreEnabled -Enabled $true
        Set-AqWorldState -CharacterConnection $characters -Phase 3 `
            -Phase2Tier 0
        Clear-AqEventStatus -CharacterConnection $characters
        Write-Host ''
        Write-Host '等待敲锣阶段已配置：启动 mangosd 后核心将激活事件 122。'
        Write-Host '任务 8743 激活；关门组随事件 122 生成，敲锣前大门关闭。'
        Write-Host '实测此 Larmer Build 会在敲锣后进入事件 123，并移除关门组与碰撞。'
        Show-Status -WorldConnection $world -CharacterConnection $characters
    }
    'EnableTenHourWar' {
        Assert-WorldServerStopped
        Backup-AqState -WorldConnection $world -CharacterConnection $characters
        Ensure-AqCommendationQuestFix -WorldConnection $world
        Set-AqServerControlledEvents -WorldConnection $world
        Set-ClosedGateConfiguration -WorldConnection $world
        Set-WarEffortRateOne
        Set-WarEffortCoreEnabled -Enabled $true
        $databaseNow = Get-DatabaseUnixTimestamp -Connection $characters
        $expiresAt = $databaseNow + [uint64]36000
        Set-AqWorldState -CharacterConnection $characters -Phase 4 `
            -Phase2Tier 0 -PhaseExpiresAt $expiresAt
        Clear-AqEventStatus -CharacterConnection $characters
        Write-Host ''
        Write-Host '事件 123 十小时战争已配置。'
        Write-Host '启动 mangosd 后战争剩余时间约 10 小时，使用 CMaNGOS 原始持续时间。'
        Write-Host '此操作不会修改 mangosd.exe，也不会修改 Windows 系统时间。'
        Show-Status -WorldConnection $world -CharacterConnection $characters
    }
    'DisableAll' {
        Assert-WorldServerStopped
        Backup-AqState -WorldConnection $world -CharacterConnection $characters
        Set-AqServerControlledEvents -WorldConnection $world
        Set-WarEffortCoreEnabled -Enabled $false
        Set-AqWorldState -CharacterConnection $characters -Phase 0 `
            -Phase2Tier 0
        Clear-AqEventStatus -CharacterConnection $characters
        Write-Host ''
        Write-Host 'AQ 事件 120-135 已全部关闭；关门组不会由事件生成。'
        Show-Status -WorldConnection $world -CharacterConnection $characters
    }
}
