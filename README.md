# Futebol de Respeito

App para organizar a pelada de domingo: lista de confirmados, reservas automáticas, controlo de pagamentos (IBAN / MB Way) e sorteio de três times.

Site estático, sem processo de build. Roda direto no navegador.

**No ar:** https://futebolderespeito.vercel.app

---

## Como funciona

- **Um jogo de cada vez.** A app mostra sempre o próximo jogo com data igual ou posterior a hoje. Toda a gente que abre o link vê o mesmo jogo, a mesma hora e a mesma lista.
- **Cada um entra sozinho.** Quem abre escreve o nome e carrega em Entrar. O celular guarda quem é, e a partir daí a app trata a pessoa pelo nome e destaca a linha dela.
- **Reservas automáticas.** Quem entra depois de as vagas esgotarem fica em Reservas, por ordem de chegada. Ninguém tem de gerir a fila à mão.
- **Sorteio partilhado.** Os times sorteados ficam guardadas no jogo, por isso aparecem iguais no celular de todos.
- **Uma mensagem para o WhatsApp.** O botão copia a lista já formatada, com confirmados, reservas, times, quanto falta pagar e o IBAN.

---

## Ativar a lista partilhada (Supabase)

Sem isto a app funciona, mas guarda tudo só no celular de quem a abriu — cada pessoa vê a sua lista. Com o Supabase ligado, todos veem e editam a mesma, em tempo real.

1. Cria um projeto grátis em [supabase.com](https://supabase.com)
2. Vai a **SQL Editor**, cola o conteúdo de `supabase/schema.sql` e corre. Cria as tabelas `games` e `players`, as políticas de acesso e o tempo real.
3. Vai a **Project Settings → API** e copia o `Project URL` e a `anon public key`
4. Abre `index.html` e preenche, logo a seguir ao comentário CONFIGURAÇÃO:
   ```js
   const SUPABASE_URL = "COLOCAR_AQUI";
   const SUPABASE_ANON_KEY = "COLOCAR_AQUI";
   ```
5. `git push` — o Vercel publica sozinho

A `anon key` é pública por natureza: vai dentro do HTML e qualquer pessoa a consegue ler. A segurança está nas políticas do `schema.sql`, que permitem escrever a quem tiver o link. Para um grupo de amigos com um link que não se divulga, chega. Se um dia isto passar a ser público, troca as políticas por políticas com autenticação.

---

## Dados do grupo

No topo do `<script type="module">` em `index.html`:

| Constante | O que é |
|---|---|
| `IBAN` | Conta que recebe o dinheiro |
| `MBWAY` | Número de MB Way |
| `MAPS_LINK` | Link do Google Maps para o campo |
| `CAMPO` | Texto do botão do mapa |
| `DEFAULTS` | Hora, vagas e preço por omissão de cada jogo novo |
| `KITS` | Nomes e cores das três equipas |

Hora, vagas, preço e data mudam-se dentro da própria app, na secção **Organização**, sem tocar no código.

---

## Estrutura

```
index.html           App completa (Preact + htm, sem build)
manifest.json        Instalar no celular como app
icon.svg / icon.png  Ícone
og.png               Imagem do link partilhado no WhatsApp
supabase/schema.sql  Tabelas, políticas e tempo real
```

## Deploy

Já está ligado ao Vercel. Cada `git push` para `main` publica em produção.
