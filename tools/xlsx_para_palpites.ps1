<#
.SYNOPSIS
  Converte uma planilha de palpites BOLAO2026_NOME.xlsx no JSON do bolão e valida o preenchimento.

.DESCRIPTION
  Lê a aba GRUPOS (72 jogos) e a aba PONTUAÇÃO EXTRA, casa os jogos com data/jogos.json
  pelos nomes das seleções (normalizando divergências de grafia), monta o JSON do participante
  e roda validações. Se houver ERROS, o arquivo NÃO é gravado.

  Estrutura esperada da planilha (padrão do comitê — não alterar a formatação):
    GRUPOS  — linhas 6..51
      bloco esquerdo:  data=C  casa=D  gols_casa=H  'x'=I  gols_fora=J  fora=N
      bloco direito:   data=P  casa=Q  gols_casa=U  'x'=V  gols_fora=W  fora=AA
    PONTUAÇÃO EXTRA
      melhor ataque=E6   melhor defesa=M6   artilheiro=I8
      favorito eliminado: 'X' na coluna E (linhas 12..23, opções em C)
      zebra classificada: 'X' na coluna N (linhas 12..23, opções em L)

.PARAMETER Path
  Caminho do .xlsx de palpites.

.PARAMETER Nome
  Nome do participante (default: derivado do arquivo BOLAO2026_<NOME>.xlsx).

.PARAMETER JogosJson
  Caminho de data/jogos.json (default: ..\data\jogos.json relativo ao script).

.PARAMETER OutDir
  Pasta de saída (default: ..\data\palpites).

.EXAMPLE
  .\tools\xlsx_para_palpites.ps1 -Path "C:\Users\Macedo\Downloads\BOLAO2026_MACEDO.xlsx"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Path,
  [string]$Nome,
  [string]$JogosJson,
  [string]$OutDir,
  [switch]$SkipIndex
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $JogosJson) { $JogosJson = Join-Path $scriptDir '..\data\jogos.json' }
if (-not $OutDir)    { $OutDir    = Join-Path $scriptDir '..\data\palpites' }

if (-not (Test-Path $Path))      { throw "Planilha não encontrada: $Path" }
if (-not (Test-Path $JogosJson)) { throw "jogos.json não encontrado: $JogosJson" }

$erros   = New-Object System.Collections.Generic.List[string]
$avisos  = New-Object System.Collections.Generic.List[string]

# Nome do participante a partir do arquivo, se não informado
if (-not $Nome) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
  $m = [regex]::Match($base, '(?i)BOLAO2026[_\- ]*(.+)')
  $raw = if ($m.Success) { $m.Groups[1].Value } else { $base }
  $raw = $raw.Trim()
  if ($raw.Length -gt 0) {
    $Nome = (Get-Culture).TextInfo.ToTitleCase($raw.ToLower())
  } else { $Nome = $base }
}
if ($base -and $base -notmatch '(?i)^BOLAO2026[_\- ]') {
  $avisos.Add("Nome do arquivo fora do padrão BOLAO2026_NOME (achei: '$base').")
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
    'RD do Congo'         { return 'RD Congo' }
    default               { return $n }
  }
}

# ---- Extrai células da planilha (xlsx = zip) ----
$tmp = Join-Path $env:TEMP ("bolao_conv_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Copy-Item $Path (Join-Path $tmp 'book.zip')
  Expand-Archive -Path (Join-Path $tmp 'book.zip') -DestinationPath $tmp -Force

  $strings = @()
  $ssPath = Join-Path $tmp 'xl\sharedStrings.xml'
  if (Test-Path $ssPath) {
    [xml]$ss = Get-Content $ssPath -Encoding utf8
    foreach ($si in $ss.sst.si) {
      if ($si.t -is [string]) { $strings += $si.t }
      elseif ($si.t.'#text')  { $strings += $si.t.'#text' }
      elseif ($si.r)          { $strings += ($si.r | ForEach-Object { if ($_.t.'#text') { $_.t.'#text' } else { $_.t } }) -join '' }
      else                    { $strings += '' }
    }
  }

  function Read-Sheet([string]$file) {
    $cells = @{}
    [xml]$sh = Get-Content $file -Encoding utf8
    foreach ($row in $sh.worksheet.sheetData.row) {
      foreach ($c in $row.c) {
        $val = $c.v
        if ($c.t -eq 's' -and $val -ne $null) { $val = $strings[[int]$val] }
        if ($val -ne $null) { $cells[$c.r] = "$val" }
      }
    }
    return $cells
  }

  # Descobre quais sheetN.xml correspondem a GRUPOS e PONTUAÇÃO EXTRA
  [xml]$wb   = Get-Content (Join-Path $tmp 'xl\workbook.xml') -Encoding utf8
  [xml]$rels = Get-Content (Join-Path $tmp 'xl\_rels\workbook.xml.rels') -Encoding utf8
  $relMap = @{}
  foreach ($rel in $rels.Relationships.Relationship) { $relMap[$rel.Id] = $rel.Target }
  $sheetFile = @{}
  foreach ($s in $wb.workbook.sheets.sheet) {
    $rid = $s.id   # r:id
    if (-not $rid) { $rid = $s.Attributes['r:id'].Value }
    $tgt = $relMap[$rid]
    if ($tgt) { $sheetFile[$s.name] = (Join-Path $tmp ('xl\' + ($tgt -replace '/','\'))) }
  }
  $fGrupos = $sheetFile.Keys | Where-Object { $_ -match '(?i)grupos' } | Select-Object -First 1
  $fExtra  = $sheetFile.Keys | Where-Object { $_ -match '(?i)extra'  } | Select-Object -First 1
  if (-not $fGrupos) { throw "Aba GRUPOS não encontrada na planilha." }

  $grupos = Read-Sheet $sheetFile[$fGrupos]
  $extra  = if ($fExtra) { Read-Sheet $sheetFile[$fExtra] } else { @{} }
}
finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- Mapa de jogos da fase de grupos (pares de seleções -> id) ----
$dados = Get-Content $JogosJson -Raw -Encoding utf8 | ConvertFrom-Json
$mapa = @{}   # "casa::fora" -> id  (e inverso marcado)
foreach ($j in $dados.jogos) {
  if ($j.fase -ne 'grupos') { continue }
  $mapa["$($j.casa)::$($j.fora)"] = $j.id
}
$opcoesFav   = @($dados.opcoes_favorito)
$opcoesZebra = @($dados.opcoes_zebra)
$todosTimes  = @($dados.jogos | Where-Object { $_.fase -eq 'grupos' } | ForEach-Object { $_.casa, $_.fora } | Sort-Object -Unique)

# ---- Lê os palpites dos 72 jogos ----
$palpites = [ordered]@{}
$vistos = @{}

# blocos: cada um define colunas data/casa/golCasa/golFora/fora/coluna-extra-suspeita
$blocos = @(
  @{ d='C'; casa='D'; gc='H'; gf='J'; fora='N'; stray='K' },
  @{ d='P'; casa='Q'; gc='U'; gf='W'; fora='AA'; stray='X' }
)

for ($r = 6; $r -le 51; $r++) {
  foreach ($b in $blocos) {
    $casa = $grupos["$($b.casa)$r"]
    $fora = $grupos["$($b.fora)$r"]
    if (-not $casa -or -not $fora) { continue }   # linha de cabeçalho/grupo

    $nCasa = Norm $casa
    $nFora = Norm $fora
    $par   = "$nCasa x $nFora (linha $r)"

    # localiza o jogo (orientação direta ou invertida)
    $id = $null; $invertido = $false
    if ($mapa.ContainsKey("$nCasa::$nFora")) { $id = $mapa["$nCasa::$nFora"] }
    elseif ($mapa.ContainsKey("$nFora::$nCasa")) { $id = $mapa["$nFora::$nCasa"]; $invertido = $true }

    if (-not $id) { $erros.Add("Jogo não reconhecido: $par. Confira a grafia das seleções (não altere a formatação).") ; continue }
    if ($vistos.ContainsKey($id)) { $erros.Add("Jogo #$id ($par) aparece duplicado na planilha."); continue }
    $vistos[$id] = $true

    # lê os gols
    $sgc = $grupos["$($b.gc)$r"]
    $sgf = $grupos["$($b.gf)$r"]
    $gc = $null; $gf = $null
    if ($sgc -eq $null -or "$sgc".Trim() -eq '') { $erros.Add("Jogo #$id ($par): gols da casa em branco.") }
    elseif (-not [int]::TryParse("$sgc", [ref]$gc) -or $gc -lt 0) { $erros.Add("Jogo #$id ($par): gols da casa inválidos ('$sgc').") }
    if ($sgf -eq $null -or "$sgf".Trim() -eq '') { $erros.Add("Jogo #$id ($par): gols do fora em branco.") }
    elseif (-not [int]::TryParse("$sgf", [ref]$gf) -or $gf -lt 0) { $erros.Add("Jogo #$id ($par): gols do fora inválidos ('$sgf').") }

    # célula suspeita (valor solto fora do padrão)
    $stray = $grupos["$($b.stray)$r"]
    if ($stray -ne $null -and "$stray".Trim() -ne '') {
      $avisos.Add("Jogo #$id ($par): valor inesperado na coluna $($b.stray)$r ('$stray') — ignorado. Limpe a célula.")
    }

    if ($gc -ne $null -and $gf -ne $null) {
      if ($invertido) { $tmpG = $gc; $gc = $gf; $gf = $tmpG }
      $palpites["$id"] = [ordered]@{ gols_casa = $gc; gols_fora = $gf }
    }
  }
}

# checa cobertura dos 72 jogos
for ($id = 1; $id -le 72; $id++) {
  if (-not $vistos.ContainsKey($id)) {
    $j = $dados.jogos | Where-Object { $_.id -eq $id }
    $erros.Add("Jogo #$id ($($j.casa) x $($j.fora)) não foi encontrado/preenchido na planilha.")
  }
}

# ---- Extras ----
function ValOrNull($v) { if ($v -ne $null -and "$v".Trim() -ne '' -and "$v" -notmatch '(?i)sua resposta') { return "$v".Trim() } return $null }

$melhorAtaque = Norm (ValOrNull $extra['E6'])
$melhorDefesa = Norm (ValOrNull $extra['M6'])
$artilheiro   = ValOrNull $extra['I8']

# favorito: 'X' na coluna E (opções em C12..C23); zebra: 'X' na coluna N (opções em L12..L23)
$favSel = @(); $zebSel = @()
for ($r = 12; $r -le 23; $r++) {
  if ("$($extra["E$r"])".Trim() -match '(?i)^x$') { $favSel += (Norm $extra["C$r"]) }
  if ("$($extra["N$r"])".Trim() -match '(?i)^x$') { $zebSel += (Norm $extra["L$r"]) }
}

$favorito = $null; $zebra = $null
if ($favSel.Count -eq 1) { $favorito = $favSel[0] }
elseif ($favSel.Count -eq 0) { $erros.Add("Favorito eliminado: nenhuma opção marcada com 'X' (coluna E).") }
else { $erros.Add("Favorito eliminado: marcada mais de uma opção ($($favSel -join ', ')). Marque só uma.") }

if ($zebSel.Count -eq 1) { $zebra = $zebSel[0] }
elseif ($zebSel.Count -eq 0) { $erros.Add("Zebra classificada: nenhuma opção marcada com 'X' (coluna N).") }
else { $erros.Add("Zebra classificada: marcada mais de uma opção ($($zebSel -join ', ')). Marque só uma.") }

if (-not $melhorAtaque) { $erros.Add("Melhor ataque (E6) em branco.") }
elseif ($todosTimes -notcontains $melhorAtaque) { $avisos.Add("Melhor ataque '$melhorAtaque' não é uma seleção reconhecida — confira a grafia.") }
if (-not $melhorDefesa) { $erros.Add("Melhor defesa (M6) em branco.") }
elseif ($todosTimes -notcontains $melhorDefesa) { $avisos.Add("Melhor defesa '$melhorDefesa' não é uma seleção reconhecida — confira a grafia.") }
if (-not $artilheiro) { $erros.Add("Artilheiro (I8) em branco.") }

if ($favorito -and $opcoesFav -notcontains $favorito) { $erros.Add("Favorito '$favorito' não está na lista de opções permitidas.") }
if ($zebra -and $opcoesZebra -notcontains $zebra) { $erros.Add("Zebra '$zebra' não está na lista de opções permitidas.") }

# ---- Relatório ----
Write-Host ""
Write-Host "===== Conversão BOLAO2026 -> JSON =====" -ForegroundColor Cyan
Write-Host ("Participante : {0}" -f $Nome)
Write-Host ("Jogos lidos  : {0} de 72" -f $palpites.Count)
Write-Host ("Extras       : ataque={0} | defesa={1} | artilheiro={2} | favorito={3} | zebra={4}" -f $melhorAtaque,$melhorDefesa,$artilheiro,$favorito,$zebra)
Write-Host ""

if ($avisos.Count -gt 0) {
  Write-Host "AVISOS:" -ForegroundColor Yellow
  $avisos | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
  Write-Host ""
}
if ($erros.Count -gt 0) {
  Write-Host "ERROS (corrija e rode de novo):" -ForegroundColor Red
  $erros | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  Write-Host ""
  Write-Host "Arquivo NÃO gerado." -ForegroundColor Red
  exit 1
}

# ---- Monta e grava o JSON ----
$obj = [ordered]@{
  nome     = $Nome
  palpites = $palpites
  extras   = [ordered]@{
    melhor_ataque      = $melhorAtaque
    melhor_defesa      = $melhorDefesa
    artilheiro         = $artilheiro
    favorito_eliminado = $favorito
    zebra_classificada = $zebra
  }
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$outFile = Join-Path $OutDir ("BOLAO2026_{0}.json" -f $Nome)
$json = $obj | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outFile, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ("OK — arquivo gerado: {0}" -f $outFile) -ForegroundColor Green

# ---- Registra no index.json ----
$nomeArq = "BOLAO2026_{0}.json" -f $Nome
if ($SkipIndex) {
  Write-Host ("Pulei o index.json (-SkipIndex). Adicione '{0}' manualmente." -f $nomeArq) -ForegroundColor Yellow
} else {
  $indexPath = Join-Path $OutDir 'index.json'
  $lista = @()
  if (Test-Path $indexPath) {
    try { $lista = @(Get-Content $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $lista = @() }
  }
  $lista = @($lista | Where-Object { $_ })   # remove vazios
  if ($lista -contains $nomeArq) {
    Write-Host ("index.json já continha '{0}'." -f $nomeArq) -ForegroundColor Green
  } else {
    $lista += $nomeArq
    $jsonIdx = ($lista | ConvertTo-Json -Compress)
    if ($lista.Count -eq 1) { $jsonIdx = '["' + $nomeArq + '"]' }  # ConvertTo-Json vira string solta com 1 item
    [System.IO.File]::WriteAllText($indexPath, $jsonIdx, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("index.json atualizado com '{0}'." -f $nomeArq) -ForegroundColor Green
  }
}

Write-Host "Falta só dar commit/push na branch main para entrar no ranking." -ForegroundColor Green
