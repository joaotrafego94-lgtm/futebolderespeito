# Futebol de Respeito

App para organizar a pelada de domingo: lista de jogadores, controlo de pagamentos (IBAN / MB Way) e sorteio de 3 equipas.

Site estático (`index.html`), sem processo de build — corre diretamente no browser.

## Deploy no Vercel (via GitHub)

1. Cria um repositório vazio no GitHub chamado `futebolderespeito`
2. Neste diretório:
   ```bash
   git init
   git add .
   git commit -m "Primeiro commit"
   git branch -M main
   git remote add origin https://github.com/<o-teu-user>/futebolderespeito.git
   git push -u origin main
   ```
3. Em vercel.com -> **Add New Project** -> importa o repositório `futebolderespeito`
4. Deploy automático — sem configuração adicional necessária (é um site estático)
5. Cada `git push` depois disto atualiza o site sozinho

## Ativar a lista partilhada (Supabase)

Sem isto, a lista de jogadores fica guardada só no telemóvel de cada pessoa (localStorage). Com Supabase, todos veem e editam a mesma lista em tempo real.

1. Cria um projeto grátis em [supabase.com](https://supabase.com)
2. Vai a **SQL Editor** e corre o conteúdo de `supabase/schema.sql` (cria a tabela `players` e ativa a partilha em tempo real)
3. Vai a **Project Settings -> API** e copia:
   - `Project URL`
   - `anon public key`
4. Abre `index.html` e substitui no topo do `<script type="text/babel">`:
   ```js
   const SUPABASE_URL = "COLOCAR_AQUI";       // -> o teu Project URL
   const SUPABASE_ANON_KEY = "COLOCAR_AQUI";  // -> a tua anon key
   ```
5. Commit + push — o Vercel atualiza sozinho

Sem estes dois valores preenchidos, a app funciona na mesma (fallback automático para localStorage).

## Estrutura

```
index.html            Site completo (React via CDN, sem build)
supabase/schema.sql    Tabela + políticas + realtime para o Supabase
```

## Dados fixos no código

- IBAN e MB Way: no topo do `index.html` (`IBAN`, `MBWAY`)
- Local do jogo: `MAPS_LINK` (link do Google Maps)

Para alterar qualquer um destes, edita as constantes no início do ficheiro.
