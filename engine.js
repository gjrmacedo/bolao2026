// ============================================================
// BOLÃO PISTOLANDO™ NAFTA EDITION 2026 — Motor de Pontuação
// ============================================================

const REPO_RAW = 'https://raw.githubusercontent.com/gjrmacedo/bolao2026/refs/heads/main/';

// Palpites só ficam visíveis 10min antes do início OU quando todos já enviaram
function palpitesVisiveis(jogo, participantesArr) {
  const idStr = String(jogo.id);
  const agora = Date.now();
  const jogoTime = new Date(jogo.data).getTime();
  if (agora >= jogoTime - 600000) return true;
  return participantesArr.every(p => p.palpites?.[idStr] !== undefined);
}

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

  // Cravada invertida™ (placar trocado, só vale com vencedor)
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
    // Empate (decidido nos pênaltis)
    if (pc === pf) {
      // Apostador apostou empate — pontua e DEVE indicar o vencedor dos pênaltis
      if (pc === rc && pf === rf) {
        pts = regras.empate_cravado; tipo = 'empate_cravado';
      } else {
        pts = regras.empate_gols; tipo = 'empate_gols';
      }

      // Bônus/penalidade dos pênaltis (só para quem apostou empate)
      if (resultado.penaltis_vencedor && palpite.penaltis_vencedor) {
        if (palpite.penaltis_vencedor === resultado.penaltis_vencedor) {
          pts += regras.penaltis_acerto;
        } else {
          pts += regras.penaltis_erro; // já é negativo no JSON
        }
      }
    } else if (pc === rc || pf === rf) {
      // Apostou vitória, resultado foi empate — consolação por gol certo
      pts = regras.vitoria_gols; tipo = 'gols_parcial';
    }
  }

  return { pts, tipo };
}

// Fator de duplicação: conta os "motivos de dobra" presentes no jogo e eleva 2
// a essa potência. Cobre dobra simples (×2), quadruplicação em cruzamentos (×4)
// e a abertura do México ×4 (até 12) quando o México é o melhor anfitrião.
// Nos jogos de mata-mata os times reais vêm de resultado.casa / resultado.fora.
function fatorDuplicacao(jogo, resultado, anfitriaoBest) {
  const casa = (resultado && resultado.casa) || jogo.casa;
  const fora = (resultado && resultado.fora) || jogo.fora;
  const times = [casa, fora];
  let motivos = 0;
  if (jogo.motivo_duplicado === 'abertura') motivos++;           // jogo de abertura
  if (times.includes('Brasil')) motivos++;
  if (times.includes('Argentina')) motivos++;
  if (anfitriaoBest && times.includes(anfitriaoBest)) motivos++; // anfitrião de melhor campanha
  return Math.pow(2, motivos);
}

function calcularPontosJogo(jogo, palpite, resultado, anfitriaoBest, fases) {
  if (!palpite || resultado.gols_casa === null || resultado.gols_casa === undefined) return null;

  const regras = fases[jogo.fase];
  let { pts, tipo } = jogo.fase === 'grupos'
    ? calcularPontosGrupos(palpite, resultado)
    : calcularPontosMataM(palpite, resultado, regras.pontos);

  const fator = fatorDuplicacao(jogo, resultado, anfitriaoBest);
  pts *= fator;

  return { pts, tipo, fator, duplicado: fator > 1 };
}

// pontosExtras.zebra_classificada é um mapa { "1":30, "2":20, "3":10 }
// (pontos conforme a colocação final da zebra escolhida no seu grupo).
function calcularExtras(extras, resultadosExtras, pontosExtras) {
  if (!extras || !resultadosExtras) return 0;
  let pts = 0;
  if (extras.melhor_ataque && extras.melhor_ataque === resultadosExtras.melhor_ataque) pts += pontosExtras.melhor_ataque;
  if (extras.melhor_defesa && extras.melhor_defesa === resultadosExtras.melhor_defesa) pts += pontosExtras.melhor_defesa;
  if (extras.artilheiro && extras.artilheiro === resultadosExtras.artilheiro) pts += pontosExtras.artilheiro;

  // Favorito eliminado: pode haver mais de um favorito que cai; pontua se o escolhido está na lista
  const favsEliminados = resultadosExtras.favoritos_eliminados || [];
  if (extras.favorito_eliminado && favsEliminados.includes(extras.favorito_eliminado)) {
    pts += pontosExtras.favorito_eliminado;
  }

  // Zebra classificada: pontos variáveis conforme a posição final (1º=30, 2º=20, 3º=10)
  const posicoes = resultadosExtras.zebra_posicoes || {};
  const pos = extras.zebra_classificada ? posicoes[extras.zebra_classificada] : undefined;
  const tabelaZebra = pontosExtras.zebra_classificada || {};
  if (pos !== undefined && pos !== null && tabelaZebra[pos] !== undefined) {
    pts += tabelaZebra[pos];
  }

  return pts;
}

async function calcularRanking() {
  const [dadosJogos, palpitesIndex] = await Promise.all([
    fetchJSON('data/jogos.json'),
    fetchJSON('data/palpites/index.json'),
  ]);

  const resultadosData = await fetchResultados(dadosJogos.jogos); // busca repo + mescla API
  const anfitriaoBest = resultadosData._anfitriao_melhor_campanha;
  const resultados = resultadosData.resultados || {};
  const resultadosExtras = resultadosData.extras || null;

  const participantes = await Promise.all(
    palpitesIndex.map(arquivo => fetchJSON(`data/palpites/${arquivo}`))
  );

  const ranking = participantes.map(p => {
    let totalPts = 0;
    let cravadas = 0, acertosVencedor = 0, acertosGols = 0, invertidasCount = 0;
    // Contadores restritos a jogos duplicados (fator > 1) — usados no desempate final
    let cravadasDup = 0, acertosVencedorDup = 0, acertosGolsDup = 0, invertidasDup = 0;
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
      const ehDup = calc.fator > 1;
      if (calc.tipo === 'cravada' || calc.tipo === 'empate_cravado') { cravadas++; if (ehDup) cravadasDup++; }
      if (calc.tipo === 'vencedor') { acertosVencedor++; if (ehDup) acertosVencedorDup++; }
      if (calc.tipo === 'gols_parcial' || calc.tipo === 'empate_gols') { acertosGols++; if (ehDup) acertosGolsDup++; }
      if (calc.tipo === 'cravada_invertida') { invertidasCount++; if (ehDup) invertidasDup++; }
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
      cravadasDup,
      acertosVencedorDup,
      acertosGolsDup,
      invertidasDup,
      ptsExtras,
      detalheJogos,
    };
  });

  // Ordenação com critérios de desempate do regulamento.
  // Persistindo o empate, repetem-se os mesmos critérios só para os jogos duplicados.
  ranking.sort((a, b) => {
    if (b.pts !== a.pts) return b.pts - a.pts;
    if (b.cravadas !== a.cravadas) return b.cravadas - a.cravadas;
    if (b.acertosVencedor !== a.acertosVencedor) return b.acertosVencedor - a.acertosVencedor;
    if (b.acertosGols !== a.acertosGols) return b.acertosGols - a.acertosGols;
    if (a.invertidas !== b.invertidas) return a.invertidas - b.invertidas;
    // Desempate final: mesmos critérios, só jogos duplicados
    if (b.cravadasDup !== a.cravadasDup) return b.cravadasDup - a.cravadasDup;
    if (b.acertosVencedorDup !== a.acertosVencedorDup) return b.acertosVencedorDup - a.acertosVencedorDup;
    if (b.acertosGolsDup !== a.acertosGolsDup) return b.acertosGolsDup - a.acertosGolsDup;
    return a.invertidasDup - b.invertidasDup;
  });

  return {
    ranking,
    jogos: dadosJogos.jogos,
    resultados,
    anfitriaoBest,
    participantes: participantes.map(p => ({ nome: p.nome, palpites: p.palpites || {} })),
  };
}

window.BolaoEngine = { calcularRanking, fetchJSON, REPO_RAW, palpitesVisiveis, fatorDuplicacao };

async function fetchResultados(meusJogos) {
  // Busca em paralelo: repositório + API externa
  const [resultadosData, apiResp] = await Promise.all([
    fetchJSON('data/resultados.json'),
    fetch('https://worldcup26.ir/get/games').catch(() => null),
  ]);
 
  // Se a API respondeu, mescla — repositório preservado como base (manuais de mata-mata etc.)
  if (apiResp?.ok) {
    try {
      const { games } = await apiResp.json();
      const doApi = correlacionarResultados(meusJogos, games);
      resultadosData.resultados = {
        ...resultadosData.resultados,  // mantém manuais (penaltis, mata-mata)
        ...doApi,                      // sobrescreve com o que veio da API
      };
    } catch (e) {
      console.warn('[fetchResultados] Falha ao processar API externa, usando só o repositório.', e);
    }
  }
 
  return resultadosData;
}

function correlacionarResultados(meusJogos, apiGames, nomeMap = NOMES_EN_PT) {
  const indiceApi = {};
  for (const jogo of apiGames) {
    if(jogo.time_elapsed == "notstarted") continue;
    const casaPT = nomeMap[jogo.home_team_name_en];
    const foraPT = nomeMap[jogo.away_team_name_en];
    if (!casaPT || !foraPT) {
      console.warn(`[correlacionar] Time sem mapeamento: "${jogo.home_team_name_en}" ou "${jogo.away_team_name_en}"`);
      continue;
    }
    indiceApi[`${casaPT}|${foraPT}`] = {
      gols_casa: parseInt(jogo.home_score, 10),
      gols_fora: parseInt(jogo.away_score, 10),
    };
  }
 
  const resultados = {};
  for (const jogo of meusJogos) {
    const entry = indiceApi[`${jogo.casa}|${jogo.fora}`];
    if (entry) resultados[String(jogo.id)] = entry;
  }
  return resultados;
}

const NOMES_EN_PT = {
  "Mexico": "México",
  "South Africa": "África do Sul",
  "South Korea": "Coreia do Sul",
  "Czech Republic": "Tchéquia",
  "Canada": "Canadá",
  "Bosnia and Herzegovina": "Bósnia-Herz.",
  "United States": "Estados Unidos",
  "Paraguay": "Paraguai",
  "Australia": "Austrália",
  "Turkey": "Turquia",
  "Qatar": "Catar",
  "Switzerland": "Suíça",
  "Brazil": "Brasil",
  "Morocco": "Marrocos",
  "Haiti": "Haiti",
  "Scotland": "Escócia",
  "Germany": "Alemanha",
  "Curaçao": "Curaçao",
  "Netherlands": "Países Baixos",
  "Japan": "Japão",
  "Ivory Coast": "Costa do Marfim",
  "Ecuador": "Equador",
  "Sweden": "Suécia",
  "Tunisia": "Tunísia",
  "Spain": "Espanha",
  "Cape Verde": "Cabo Verde",
  "Belgium": "Bélgica",
  "Egypt": "Egito",
  "Saudi Arabia": "Arábia Saudita",
  "Uruguay": "Uruguai",
  "Iran": "Irã",
  "New Zealand": "Nova Zelândia",
  "France": "França",
  "Senegal": "Senegal",
  "Iraq": "Iraque",
  "Norway": "Noruega",
  "Argentina": "Argentina",
  "Algeria": "Argélia",
  "Austria": "Áustria",
  "Jordan": "Jordânia",
  "Portugal": "Portugal",
  "Democratic Republic of the Congo": "RD Congo",
  "England": "Inglaterra",
  "Croatia": "Croácia",
  "Ghana": "Gana",
  "Panama": "Panamá",
  "Uzbekistan": "Uzbequistão",
  "Colombia": "Colômbia",
};