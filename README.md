# ⚽ Bolão Pistolando™ NAFTA Edition 2026

Site estático do bolão hospedado no GitHub Pages. Zero servidor, zero custo.

---

## 🚀 Setup inicial (faça uma vez)

### 1. Crie o repositório no GitHub

1. Acesse [github.com/new](https://github.com/new)
2. Dê um nome (ex: `bolao2026`)
3. Deixe **público** (necessário para o GitHub Pages gratuito)
4. Clique em **Create repository**

### 2. Suba os arquivos

```bash
# Clone ou inicialize
git init
git remote add origin https://github.com/SEU_USUARIO/bolao2026.git

# Adicione todos os arquivos do projeto
git add .
git commit -m "🚀 Bolão Pistolando™ NAFTA Edition 2026"
git push -u origin main
```

### 3. Ative o GitHub Pages

1. Vá em **Settings** → **Pages**
2. Source: **Deploy from a branch**
3. Branch: `main` / `/ (root)`
4. Clique em **Save**

Em ~1 minuto o site estará em: `https://SEU_USUARIO.github.io/bolao2026`

### 4. Configure a URL no engine.js

Abra `engine.js` e edite a primeira linha:

```javascript
const REPO_RAW = 'https://raw.githubusercontent.com/SEU_USUARIO/bolao2026/main';
```

Faça commit e push desta alteração.

---

## 📋 Fluxo do bolão

### Recebendo palpites

1. Participante preenche o `BOLAO2026_NOME.json` (baseado em `data/palpites/exemplo.json`)
2. Você salva o arquivo em `data/palpites/BOLAO2026_NOME.json`
3. Adiciona o nome do arquivo ao `data/palpites/index.json`:

```json
["BOLAO2026_joao.json", "BOLAO2026_maria.json", "BOLAO2026_thiago.json"]
```

4. Faz commit e push — o ranking aparece automaticamente no site

### Atualizando resultados

Após cada jogo, edite `data/resultados.json` e adicione o resultado:

```json
{
  "resultados": {
    "1": { "gols_casa": 2, "gols_fora": 0 },
    "7": { "gols_casa": 3, "gols_fora": 1 },
    "73": { "gols_casa": 1, "gols_fora": 1, "penaltis_vencedor": "Brasil" }
  }
}
```

Faça commit e push — o site atualiza na hora.

### Definindo o anfitrião de melhor campanha

Ao fim da fase de grupos, edite `data/resultados.json`:

```json
{
  "_anfitriao_melhor_campanha": "Estados Unidos",
  "resultados": { ... }
}
```

Isso ativa a pontuação dupla para todos os jogos do anfitrião escolhido (retroativamente e nas próximas fases).

### Resultado dos extras (fim da fase de grupos)

Adicione ao `data/resultados.json`:

```json
{
  "_anfitriao_melhor_campanha": "Estados Unidos",
  "extras": {
    "melhor_ataque": "Brasil",
    "melhor_defesa": "França",
    "favorito_eliminado": "Alemanha",
    "zebra_classificada": "Haiti",
    "artilheiro": "Vinicius Jr."
  },
  "resultados": { ... }
}
```

---

## 📁 Estrutura do projeto

```
bolao2026/
├── index.html          ← Ranking + próximos jogos
├── jogos.html          ← Calendário completo dos 104 jogos
├── palpitar.html       ← Instruções + template JSON
├── regulamento.html    ← Regulamento completo
├── engine.js           ← Motor de cálculo de pontos
└── data/
    ├── jogos.json           ← Todos os 104 jogos + regras de pontuação
    ├── resultados.json      ← Você atualiza após cada jogo
    └── palpites/
        ├── index.json       ← Lista de arquivos de palpites
        ├── exemplo.json     ← Template para os participantes
        ├── BOLAO2026_joao.json
        └── BOLAO2026_maria.json
```

---

## 💡 Dicas

- **Edição rápida de resultados**: você pode editar arquivos direto no GitHub.com (clica no arquivo → ícone de lápis) sem precisar do terminal
- **Múltiplos commits**: você pode acumular vários resultados e dar um push só de vez
- **Backup automático**: o histórico de commits do git é um log completo de tudo que aconteceu

---

## 📝 Formato do palpite — Referência

```json
{
  "nome": "Nome do Participante",
  "palpites": {
    "1": { "gols_casa": 2, "gols_fora": 1 },
    "73": { "gols_casa": 1, "gols_fora": 1, "penaltis_vencedor": "Brasil" }
  },
  "extras": {
    "melhor_ataque": "Brasil",
    "melhor_defesa": "França",
    "favorito_eliminado": "Alemanha",
    "zebra_classificada": "Haiti",
    "artilheiro": "Vinicius Jr."
  }
}
```

**IDs dos jogos da fase de grupos**: 1 a 72
**IDs dos jogos do mata-mata**: 73 a 104
`penaltis_vencedor` só é necessário quando o apostador aposta em empate em jogos do mata-mata.
