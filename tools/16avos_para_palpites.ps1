<#
.SYNOPSIS
  Lê os palpites dos 16avos em formato texto (data\palpites\16avos\BOLAO2026_NOME.txt)
  e injeta os jogos 73..88 no JSON correspondente do participante (data\palpites\BOLAO2026_NOME.json).

.DESCRIPTION
  Cada arquivo .txt tem uma linha por jogo, no formato recebido pelo grupo:

      JOGO 73: África do Sul 0 X 2 Canadá
      JOGO 75: Países Baixos 2 X 2 Marrocos*
      JOGO 88: Austrália* 0 X 0 Egito

  Regras:
    - O número do JOGO é o próprio id do jogo no data\jogos.json (73..88).
    - Os nomes das seleções são conferidos contra o jogo correspondente (normalizando
      divergências de grafia). Se não baterem, é ERRO e o arquivo não é alterado.
    - O '*' marca a seleção que vence nos pênaltis. Só faz sentido em empate:
        * empate com '*'  -> penaltis_vencedor = seleção marcada
        * vitória          -> penaltis_vencedor = null  ('*' nesse caso vira aviso)
        * empate sem '*'   -> ERRO (falta dizer quem passa)
    - Os palpites de 1..72 (e quaisquer outros já existentes) são preservados na ordem
      original; os jogos 73..88 são adicionados/atualizados ao final.

  Por padrão processa TODOS os .txt da pasta. Use -Path para um arquivo específico.

.PARAMETER Path
  Caminho de um .txt específico. Se omitido, processa data\palpites\16avos\*.txt.

.PARAMETER TxtDir
  Pasta dos .txt (default: ..\data\palpites\16avos relativo ao script).

.PARAMETER JogosJson
  Caminho de data\jogos.json (default: ..\data\jogos.json).

.PARAMETER OutDir
  Pasta dos JSON de palpites (default: ..\data\palpites).

.EXAMPLE
  .\tools\16avos_para_palpites.ps1
  .\tools\16avos_para_palpites.ps1 -Path .\data\palpites\16avos\BOLAO2026_Viniciusmartins.txt
#>
[CmdletBinding()]
param(
  [string]$Path,
  [string]$TxtDir,
  [string]$JogosJson,
  [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $TxtDir)    { $TxtDir    = Join-Path $scriptDir '..\data\palpites\16avos' }
if (-not $JogosJson) { $JogosJson = Join-Path $scriptDir '..\data\jogos.json' }
if (-not $OutDir)    { $OutDir    = Join-Path $scriptDir '..\data\palpites' }

if (-not (Test-Path $JogosJson)) { throw "jogos.json não encontrado: $JogosJson" }

# Comparação de seleções ignorando acentos e caixa (ex.: 'Australia' == 'Austrália')
function Slug([string]$s) {
  if (-not $s) { return '' }
  $d = $s.Normalize([System.Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $d.ToCharArray()) {
    if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
  }
  return $sb.ToString().ToLowerInvariant().Trim()
}

# Normaliza nomes de seleções para a convenção do jogos.json
function Norm([string]$n) {
  if (-not $n) { return $n }
  $n = $n.Trim()
  switch -regex ($n) {
    'Cor.?ia do Sul'      { return 'Coreia do Sul' }
    'Rep.?blica Tcheca'   { return 'Tchéquia' }
    '^Tch[eé]quia$'       { return 'Tchéquia' }
    'B.?snia'             { return 'Bósnia-Herz.' }
    '^Holanda$'           { return 'Países Baixos' }
    'Pa.?ses Baixos'      { return 'Países Baixos' }
    'RD( do)? Congo'      { return 'RD Congo' }
    '^EUA$'               { return 'Estados Unidos' }
    'Estados Unidos'      { return 'Estados Unidos' }
    default               { return $n }
  }
}

# ---- Jogos 73..88 (id -> casa/fora) ----
$dados = Get-Content $JogosJson -Raw -Encoding utf8 | ConvertFrom-Json
$jogo16 = @{}
foreach ($j in $dados.jogos) {
  if ($j.fase -eq '16avos') { $jogo16[[int]$j.id] = $j }
}
$idsEsperados = 73..88

# ---- Lista de arquivos a processar ----
if ($Path) {
  if (-not (Test-Path $Path)) { throw "Arquivo não encontrado: $Path" }
  $arquivos = @(Get-Item $Path)
} else {
  if (-not (Test-Path $TxtDir)) { throw "Pasta de txt não encontrada: $TxtDir" }
  $arquivos = @(Get-ChildItem -Path $TxtDir -Filter '*.txt' -File | Sort-Object Name)
}
if ($arquivos.Count -eq 0) { Write-Host "Nenhum .txt para processar em $TxtDir" -ForegroundColor Yellow; exit 0 }

$totalOk = 0; $totalFalhou = 0

foreach ($arq in $arquivos) {
  $erros  = New-Object System.Collections.Generic.List[string]
  $avisos = New-Object System.Collections.Generic.List[string]

  $base = [System.IO.Path]::GetFileNameWithoutExtension($arq.FullName)
  $jsonFile = Join-Path $OutDir ($base + '.json')

  Write-Host ""
  Write-Host "===== $($arq.Name) =====" -ForegroundColor Cyan

  if (-not (Test-Path $jsonFile)) {
    Write-Host "  ERRO: JSON do participante não encontrado: $jsonFile" -ForegroundColor Red
    $totalFalhou++; continue
  }

  # ---- Lê e parseia o txt ----
  $linhas = Get-Content $arq.FullName -Encoding utf8
  $novos  = [ordered]@{}   # id(string) -> entry
  $vistos = @{}
  $penList = New-Object System.Collections.Generic.List[string]

  foreach ($raw in $linhas) {
    $line = "$raw".Trim()
    if ($line -eq '') { continue }

    $mid = [regex]::Match($line, '(?i)^JOGO\s+(\d+)\s*:\s*(.+)$')
    if (-not $mid.Success) { $erros.Add("Linha não reconhecida: '$line'"); continue }
    $id   = [int]$mid.Groups[1].Value
    $rest = $mid.Groups[2].Value

    if (-not $jogo16.ContainsKey($id)) {
      $erros.Add("JOGO $id não é um jogo dos 16avos (esperado 73..88).")
      continue
    }
    if ($vistos.ContainsKey($id)) { $erros.Add("JOGO $id aparece duplicado no txt."); continue }
    $vistos[$id] = $true

    # separa "casa  GC x GF  fora" — aceita placar com/sem espaços (2x1, 2 X 1) e '*' em qualquer posição
    $ms = [regex]::Match($rest, '^(.+?)\s*(\d+)\s*[xX]\s*(\d+)\s*(.+)$')
    if (-not $ms.Success) { $erros.Add("JOGO ${id}: não consegui ler o placar em '$rest'."); continue }
    $hPart = $ms.Groups[1].Value
    $gc    = [int]$ms.Groups[2].Value
    $gf    = [int]$ms.Groups[3].Value
    $aPart = $ms.Groups[4].Value

    # '*' marca quem vence nos pênaltis: do lado da casa ou do visitante (relativo ao placar)
    $homeStar = $hPart.Contains('*')
    $awayStar = $aPart.Contains('*')
    $timeCasa = Norm (($hPart -replace '\*','').Trim())
    $timeFora = Norm (($aPart -replace '\*','').Trim())

    $jg = $jogo16[$id]
    if ((Slug $timeCasa) -ne (Slug $jg.casa) -or (Slug $timeFora) -ne (Slug $jg.fora)) {
      $erros.Add("JOGO ${id}: seleções não batem. txt='$timeCasa x $timeFora' / esperado='$($jg.casa) x $($jg.fora)'. Confira a grafia/ordem.")
      continue
    }

    # penaltis_vencedor
    $pen = $null
    if ($gc -eq $gf) {
      if ($homeStar -and $awayStar) { $erros.Add("JOGO ${id}: empate com '*' nas duas seleções. Marque só uma."); continue }
      elseif ($homeStar) { $pen = $jg.casa }
      elseif ($awayStar) { $pen = $jg.fora }
      else { $erros.Add("JOGO $id ($($jg.casa) x $($jg.fora)): empate ${gc} x ${gf} sem '*'. Falta marcar quem vence nos pênaltis."); continue }
    } else {
      if ($homeStar -or $awayStar) {
        $vencedor = if ($gc -gt $gf) { $jg.casa } else { $jg.fora }
        $starred  = if ($homeStar) { $jg.casa } else { $jg.fora }
        if ($starred -ne $vencedor) {
          $avisos.Add("JOGO ${id}: '*' em '$starred' mas o placar dá vitória de '$vencedor' no tempo normal — '*' ignorado.")
        } else {
          $avisos.Add("JOGO ${id}: '*' em vitória (não vai a pênaltis) — ignorado.")
        }
      }
    }

    if ($pen) { $penList.Add("${id}->$pen") }
    $novos["$id"] = [ordered]@{ gols_casa = $gc; gols_fora = $gf; penaltis_vencedor = $pen }
  }

  # cobertura 73..88
  foreach ($id in $idsEsperados) {
    if (-not $vistos.ContainsKey($id)) {
      $jg = $jogo16[$id]
      $erros.Add("JOGO $id ($($jg.casa) x $($jg.fora)) não encontrado no txt.")
    }
  }

  if ($erros.Count -gt 0) {
    if ($avisos.Count -gt 0) { $avisos | ForEach-Object { Write-Host "  AVISO: $_" -ForegroundColor Yellow } }
    Write-Host "  ERROS (corrija e rode de novo) — JSON NÃO alterado:" -ForegroundColor Red
    $erros | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    $totalFalhou++; continue
  }

  # ---- Mescla no JSON do participante, preservando ordem existente ----
  $atual = Get-Content $jsonFile -Raw -Encoding utf8 | ConvertFrom-Json

  $palpites = [ordered]@{}
  foreach ($p in $atual.palpites.PSObject.Properties) {
    $v = $p.Value
    $entry = [ordered]@{ gols_casa = [int]$v.gols_casa; gols_fora = [int]$v.gols_fora }
    if ($v.PSObject.Properties.Name -contains 'penaltis_vencedor') { $entry.penaltis_vencedor = $v.penaltis_vencedor }
    $palpites[$p.Name] = $entry
  }
  # adiciona/atualiza 73..88 na ordem dos ids
  foreach ($id in $idsEsperados) { $palpites["$id"] = $novos["$id"] }

  $extras = [ordered]@{}
  if ($atual.PSObject.Properties.Name -contains 'extras') {
    foreach ($e in $atual.extras.PSObject.Properties) { $extras[$e.Name] = $e.Value }
  }

  $obj = [ordered]@{
    nome     = $atual.nome
    palpites = $palpites
    extras   = $extras
  }

  $json = $obj | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($jsonFile, $json, (New-Object System.Text.UTF8Encoding($false)))

  if ($avisos.Count -gt 0) { $avisos | ForEach-Object { Write-Host "  AVISO: $_" -ForegroundColor Yellow } }
  if ($penList.Count -gt 0) { Write-Host ("  Pênaltis: {0}" -f ($penList -join '  |  ')) -ForegroundColor DarkCyan }
  Write-Host ("  OK — 16 jogos (73..88) gravados em {0}" -f (Split-Path -Leaf $jsonFile)) -ForegroundColor Green
  $totalOk++
}

Write-Host ""
Write-Host ("===== Resumo: {0} OK, {1} com erro =====" -f $totalOk, $totalFalhou) -ForegroundColor Cyan
if ($totalFalhou -gt 0) { exit 1 }
