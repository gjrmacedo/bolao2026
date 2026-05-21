// ============================================================
// BOLÃO PISTOLANDO™ NAFTA EDITION 2026 — Motor de Pontuação
// ============================================================

const REPO_RAW = 'https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/main';

async function fetchJSON(path) {
  const res = await fetch(`${REPO_RAW}/${path}?_=${Date.now()}`);
  if (!res.ok) throw new Error(`Erro ao carregar ${path}: ${res.status}`);
  return res.json();
}

// Pontuação fase de grupos
function calcularPontosGrupos(palpite, resultado) {
  const pc = palpite.gols_casa, pf = palpite.gols_fora;
  const rc = resultado.gols_casa, rf = resultado.gols_fora;

  // Acerto exato (cravada)
  if (pc === rc && pf === rf) return { pts: 3, tipo: 'cravada' };

  // Cravada invertida™ (placar trocado)
  if (pc === rf && pf === rc && pc !== pf) return { pts: -3, tipo: 'cravada_invertida' };

  // Acerto do vencedor ou empate
  const pRes = Math.sign(pc - pf);
  const rRes = Math.sign(rc - rf);
  let pts = 0;
  let tipo = 'erro';

  if (pRes === rRes) {
    pts = 2;
    tipo = 'vencedor';
  }

  // Prêmio consolação: acertou gols de um dos times
  if (pc === rc || pf === rf) {
    if (pts === 0) { pts = 0.5; tipo = 'gols_parcial'; }
    // Se já acertou o vencedor, os 0.5 não são cumulativos
  }

  return { pts, tipo };
}

// Pontuação mata-mata
function calcularPontosMataM(palpite, resultado, regras) {
  const pc = palpite.gols_casa, pf = palpite.gols_fora;
  const rc = resultado.gols_casa, rf = resultado.gols_fora;

  let pts = 0, tipo = 'erro';

  if (rc !== rf) {
    // Vitória no tempo normal/prorrogação
    if (pc === rc && pf === rf) {
      pts = regras.vitoria_cravada; tipo = 'cravada';
    } else if (pc === rf && pf === rc) {
      pts = regras.vitoria_invertida; tipo = 'cravada_invertida';
    } else if (Math.sign(pc - pf) === Math.sign(rc - rf)) {
      pts = regras.vitoria_vencedor; tipo = 'vencedor';
      if (pc === rc || pf === rf) { /* gols parcial não acumula */ }
    } else if (pc === rc || pf === rf) {
      pts = regras.vitoria_gols; tipo = 'gols_parcial';
    }
  } else {
    // Empate (vai a pênaltis)
    if (pc === rc && pf === rf) {
      pts = regras.empate_cravado; tipo = 'empate_cravado';
    } else {
      pts = regras.empate_gols; tipo = 'empate_gols';
    }

    // Bônus pênaltis
    if (palpite.penaltis_vencedor && resultado.penaltis_vencedor) {
      if (palpite.penaltis_vencedor === resultado.penaltis_vencedor) {
        pts += regras.penaltis_acerto;
      } else {
        pts += regras.penaltis_erro; // já é negativo no JSON
      }
    }
  }

  return { pts, tipo };
}

function isDuplicado(jogo, anfitriaoBest) {
  if (jogo.duplicado) return true;
  if (anfitriaoBest && (jogo.casa === anfitriaoBest || jogo.fora === anfitriaoBest)) return true;
  return false;
}

function calcularPontosJogo(jogo, palpite, resultado, anfitriaoBest, fases) {
  if (!palpite || resultado.gols_casa === null || resultado.gols_casa === undefined) return null;

  const regras = fases[jogo.fase];
  let { pts, tipo } = jogo.fase === 'grupos'
    ? calcularPontosGrupos(palpite, resultado)
    : calcularPontosMataM(palpite, resultado, regras.pontos);

  if (isDuplicado(jogo, anfitriaoBest)) pts *= 2;

  return { pts, tipo, duplicado: isDuplicado(jogo, anfitriaoBest) };
}

function calcularExtras(extras, resultadosExtras, pontosExtras) {
  if (!extras || !resultadosExtras) return 0;
  let pts = 0;
  if (extras.melhor_ataque === resultadosExtras.melhor_ataque) pts += pontosExtras.melhor_ataque;
  if (extras.melhor_defesa === resultadosExtras.melhor_defesa) pts += pontosExtras.melhor_defesa;
  if (extras.favorito_eliminado === resultadosExtras.favorito_eliminado) pts += pontosExtras.favorito_eliminado;
  if (extras.zebra_classificada === resultadosExtras.zebra_classificada) pts += pontosExtras.zebra_classificada;
  if (extras.artilheiro === resultadosExtras.artilheiro) pts += pontosExtras.artilheiro;
  return pts;
}

async function calcularRanking() {
  const [dadosJogos, resultadosData, palpitesIndex] = await Promise.all([
    fetchJSON('data/jogos.json'),
    fetchJSON('data/resultados.json'),
    fetchJSON('data/palpites/index.json'),
  ]);

  const anfitriaoBest = resultadosData._anfitriao_melhor_campanha;
  const resultados = resultadosData.resultados || {};
  const resultadosExtras = resultadosData.extras || null;

  const participantes = await Promise.all(
    palpitesIndex.map(arquivo => fetchJSON(`data/palpites/${arquivo}`))
  );

  const ranking = participantes.map(p => {
    let totalPts = 0;
    let cravadas = 0, acertosVencedor = 0, acertosGols = 0, invertidasCount = 0;
    const detalheJogos = {};

    for (const jogo of dadosJogos.jogos) {
      const idStr = String(jogo.id);
      const palpite = p.palpites?.[idStr];
      const resultado = resultados[idStr];
      if (!resultado) continue;

      const calc = calcularPontosJogo(jogo, palpite, resultado, anfitriaoBest, dadosJogos.fases);
      if (!calc) continue;

      totalPts += calc.pts;
      detalheJogos[idStr] = calc;
      if (calc.tipo === 'cravada' || calc.tipo === 'empate_cravado') cravadas++;
      if (calc.tipo === 'vencedor') acertosVencedor++;
      if (calc.tipo === 'gols_parcial' || calc.tipo === 'empate_gols') acertosGols++;
      if (calc.tipo === 'cravada_invertida') invertidasCount++;
    }

    const ptsExtras = calcularExtras(p.extras, resultadosExtras, dadosJogos.pontuacoes_extras);
    totalPts += ptsExtras;

    return {
      nome: p.nome,
      pts: Math.round(totalPts * 100) / 100,
      cravadas,
      acertosVencedor,
      acertosGols,
      invertidas: invertidasCount,
      ptsExtras,
      detalheJogos,
    };
  });

  // Ordenação com critérios de desempate do regulamento
  ranking.sort((a, b) => {
    if (b.pts !== a.pts) return b.pts - a.pts;
    if (b.cravadas !== a.cravadas) return b.cravadas - a.cravadas;
    if (b.acertosVencedor !== a.acertosVencedor) return b.acertosVencedor - a.acertosVencedor;
    if (b.acertosGols !== a.acertosGols) return b.acertosGols - a.acertosGols;
    return a.invertidas - b.invertidas;
  });

  return { ranking, jogos: dadosJogos.jogos, resultados, anfitriaoBest };
}

window.BolaoEngine = { calcularRanking, fetchJSON, REPO_RAW };
