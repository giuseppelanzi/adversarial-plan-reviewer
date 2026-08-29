# plan-review

Review avversariale dei piani di Claude Code da parte di un modello esterno, con risposta forzata punto per punto.

Non è un gate automatico: il piano viene salvato sempre, la review la chiedi tu quando serve.

---

## Come funziona

1. Fai un piano in plan mode.
2. Esci dal piano approvandolo. Un hook salva il testo del piano in `.claude/plans/latest.md` **del repo corrente**. Costa millisecondi, non blocca nulla, non chiama nessun modello.
3. Quando vuoi, chiedi la review: *"fai la review del piano"*. Si attiva la skill, che lancia il reviewer esterno in sola lettura sul repo.
4. Claude riporta ogni punto della critica con verdetto `ACCEPTED` / `REJECTED` e la conseguenza concreta, e riscrive il piano se ha accolto qualcosa.

Tre reviewer disponibili. Gemini è il default; gli altri due si attivano solo se li nomini.

| Skill | Comando | Read-only | Campo output |
|---|---|---|---|
| `plan-review-gemini` | `gemini --approval-mode plan` | garantito dal flag | `.response` |
| `plan-review-claude` | `claude -p --permission-mode plan` | flag + allowlist | `.result` |
| `plan-review-antigravity` | `agy -p` | **non garantito** (vedi sotto) | stdout diretto |

---

## Struttura del repo

```
claude-ai-reviewer-plugin/
├── .claude-plugin/
│   ├── plugin.json          manifest — solo questo file sta qui dentro
│   └── marketplace.json     catalogo, permette di installare da questo stesso repo
├── skills/
│   ├── plan-review-gemini/SKILL.md
│   ├── plan-review-claude/SKILL.md
│   └── plan-review-antigravity/SKILL.md
├── reviewers/
│   ├── plan-critic.md        system prompt del critico — condiviso dalle tre skill
│   └── response-protocol.md  come rispondere alla critica — condiviso
├── hooks/
│   ├── hooks.json            registra l'hook su ExitPlanMode
│   └── save-plan.sh          salva il piano ed esce 0
├── .gitignore
└── README.md
```

Cosa è convenzione di Claude Code e cosa no:

- **Standard**: `.claude-plugin/plugin.json`, `skills/`, `hooks/hooks.json`. Vengono scoperti da soli.
- **Non standard**: `reviewers/`. È una cartella mia, letta solo perché i SKILL.md ne citano il path. In un plugin questo è legittimo: i file viaggiano col bundle e si risolvono con `${CLAUDE_PLUGIN_ROOT}`.

L'errore più comune è mettere `skills/` o `hooks/` **dentro** `.claude-plugin/`. Lì ci va solo il manifest.

---

## Installazione

### Opzione A — come plugin (consigliata)

Pubblica questo repo su GitHub, poi in Claude Code:

```
/plugin marketplace add <utente>/claude-ai-reviewer-plugin
/plugin install plan-review@plan-review-marketplace
```

Per provarlo prima di pubblicare, senza marketplace:

```bash
claude --plugin-dir /percorso/locale/claude-ai-reviewer-plugin
```

Dopo l'installazione i file stanno sotto `~/.claude/plugins/`. Non li tocchi a mano: modifichi il repo e reinstalli.

### Opzione B — senza plugin, a livello utente

Se il marketplace ti sembra troppa macchina per uso personale:

```bash
mkdir -p ~/.claude/skills ~/.claude/reviewers ~/.claude/hooks
cp -r skills/* ~/.claude/skills/
cp reviewers/*.md ~/.claude/reviewers/
cp hooks/save-plan.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/save-plan.sh
```

Poi sostituisci `${CLAUDE_PLUGIN_ROOT}` con `$HOME/.claude` nei tre `SKILL.md`, e aggiungi a `~/.claude/settings.json` il contenuto di `hooks/hooks.json`, con il path assoluto dello script al posto di `${CLAUDE_PLUGIN_ROOT}`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "ExitPlanMode",
        "hooks": [{ "type": "command",
                    "command": "/home/UTENTE/.claude/hooks/save-plan.sh",
                    "timeout": 5 }] }
    ]
  }
}
```

Scrivi il path per esteso: `$CLAUDE_PROJECT_DIR` viene espanso di sicuro nei comandi degli hook, su `$HOME` e `~` non c'è la stessa garanzia.

### Opzione C — un solo progetto

Stessa cosa dell'opzione B, ma in `<repo>/.claude/` invece di `~/.claude/`, e i path diventano `$CLAUDE_PROJECT_DIR/.claude/...`. Sensato solo se vuoi tarare il prompt del critico su quel repo specifico.

---

## Dove finiscono i piani

Sempre nel repo su cui stai lavorando, mai nel plugin:

```
<repo>/.claude/plans/
├── 20260829-143012.md
└── latest.md          ← quello che la skill legge
```

È l'unica cosa che il sistema scrive nei tuoi progetti. Aggiungi `.claude/plans/` al `.gitignore`, o mettilo nel tuo gitignore globale una volta sola.

---

## Prerequisiti

- `jq` — usato dall'hook e da due skill su tre.
- Almeno uno tra: `gemini`, `claude`, `agy`. Le skill degli altri semplicemente non le usi.
- Per `agy`: credenziali già in cache da un login interattivo precedente su quella macchina.

---

## Uso

```
> [plan mode] progetta la migrazione dello schema multi-tenant
> [approvi il piano]
> fai la review del piano
```

Oppure, nominando il reviewer: *"senti Antigravity su questo piano"*, *"fai rivedere il piano a Claude"*.

Funziona anche su un documento di analisi invece che su un piano: *"fai la review di docs/analisi-auth.md"*.

**Vincolo**: dentro plan mode Claude non può eseguire bash, quindi la review va chiesta dopo essere usciti dal piano, non durante.

---

## Personalizzazione

- **Prompt del critico**: `reviewers/plan-critic.md`. È il file che ritoccherai più spesso. Uno solo per tutti e tre i reviewer, di proposito: se diverge, le critiche non sono più confrontabili.
- **Protocollo di risposta**: `reviewers/response-protocol.md`. Qui vive la regola del verdetto binario `ACCEPTED`/`REJECTED`.
- **Reviewer di default**: sta nella `description` di `plan-review-gemini` ("use it as the default when the user asks for a review without naming a reviewer"). Per cambiarlo, sposta quella frase in un'altra skill.
- **Lingua**: le istruzioni sono in inglese, l'output segue la lingua della conversazione o del piano. Regola scritta in due punti — nel prompt del critico e nel protocollo di risposta.

---

## Trappole note

- **Antigravity non è read-only per davvero.** In headless `agy` auto-approva lettura *e scrittura* dentro il workspace; solo i comandi shell chiedono conferma. Il divieto di modificare file sta nel prompt, che è un'istruzione, non una sandbox. Se ti serve la garanzia: regola `permissions.deny` nelle impostazioni di agy, oppure lancia la review su un `git worktree` usa e getta.
- **Campo JSON diverso** tra i reviewer: `.response` per Gemini, `.result` per Claude Code. Sbagliarlo dà output vuoto senza errore.
- **`${CLAUDE_PLUGIN_ROOT}` nelle skill**: è garantito nei comandi degli hook, meno nel contesto in cui la skill lancia bash. Ogni SKILL.md ha un fallback con `find` se la variabile risulta vuota.
- **Modifiche al plugin**: i cambi ai `SKILL.md` hanno effetto subito; quelli a `hooks/` no. Serve `/reload-plugins` o un riavvio.
- **Le skill si attivano ovunque.** A livello utente o come plugin valgono in tutti i repo, anche dove `gemini` non è installato. Se diventa rumoroso, restringi le `description`.
- **Namespacing**: da plugin le skill diventano `/plan-review:plan-review-gemini`, che è ridondante. Se ti dà fastidio, rinominale in `gemini`, `claude`, `antigravity` e diventano `/plan-review:gemini`.

---

## Scelte discutibili

Due cose sono rigide di proposito, ma potrebbero non piacerti all'uso:

- **Verdetto binario.** "Parzialmente valido" è la scappatoia con cui una critica viene assorbita senza cambiare niente. Su alcune critiche però la risposta onesta è davvero intermedia. Se vedi risposte forzate, ammorbidisci il protocollo.
- **Tetto di dieci punti** per review. Arbitrario: evita trenta osservazioni cosmetiche, ma taglia informazione sui piani grossi.

E un limite che non si risolve: il critico giudica la coerenza interna e la completezza apparente. Non ti dice se il piano guarda nel posto giusto — quello lo sai solo tu. La review riduce il lavoro di verifica, non lo sostituisce.
