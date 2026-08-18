-- ============================================================
--  FUTEBOL DE RESPEITO — esquema da base de dados
--  Cola isto inteiro no SQL Editor do Supabase e clica em Run.
--  Pode rodar de novo sem estragar nada.
--
--  QUEM PODE O QUÊ
--    Qualquer pessoa (sem código nenhum): ver o jogo, entrar na
--      lista, e sair da própria vaga.
--    Organizador (com o código secreto): abrir o jogo da próxima
--      semana, mudar hora/vagas/valor, confirmar pagamentos,
--      tirar qualquer pessoa da lista e sortear os times.
--
--  SEM LOGIN, SEM CONTA. Em vez de email+senha, os 2 organizadores
--  guardam um código no celular deles (tipo uma chave PIX). Toda
--  ação de organizador manda esse código pro servidor, que confere
--  o hash antes de fazer qualquer coisa — é o servidor que decide,
--  não a tela.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
--  JOGOS
-- ------------------------------------------------------------
create table if not exists games (
  game_date  date primary key,
  kickoff    text         not null default '10:00',
  slots      integer      not null default 15,
  price      numeric(6,2) not null default 0,
  teams      jsonb,
  updated_at timestamptz  not null default now()
);

-- ------------------------------------------------------------
--  JOGADORES
--  A ordem de chegada (created_at) decide quem é confirmado e
--  quem fica de reserva.
-- ------------------------------------------------------------
create table if not exists players (
  id         uuid primary key default gen_random_uuid(),
  game_date  date not null references games (game_date) on delete cascade,
  name       text not null,
  paid       boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists players_game_date_idx on players (game_date, created_at);

-- ------------------------------------------------------------
--  SENHA DA VAGA
--  Quando alguém entra, o celular gera uma senha e guarda. Serve
--  só pra provar, na hora de sair, que quem está saindo é o dono
--  da vaga — ninguém tira a vaga de outra pessoa por engano.
-- ------------------------------------------------------------
create table if not exists player_claims (
  player_id uuid primary key references players (id) on delete cascade,
  token     uuid not null
);

-- ------------------------------------------------------------
--  CÓDIGOS DOS ORGANIZADORES
--  Uma linha por organizador. Guarda só o hash, nunca o código
--  em texto puro — nem o Claude nem ninguém que olhar essa tabela
--  descobre o código de ninguém.
-- ------------------------------------------------------------
create table if not exists admin_secrets (
  id    uuid primary key default gen_random_uuid(),
  label text not null,
  hash  text not null
);

-- ============================================================
--  REGRAS DE ACESSO
--  games e players: qualquer um lê. Escrever direto na tabela
--  fica bloqueado pra todo mundo — só as funções abaixo escrevem,
--  e cada uma decide sozinha quem pode chamá-la.
--  player_claims e admin_secrets: ninguém lê nem escreve de fora.
-- ============================================================
alter table games          enable row level security;
alter table players        enable row level security;
alter table player_claims  enable row level security;
alter table admin_secrets  enable row level security;

-- Limpa políticas de versões anteriores deste arquivo.
drop policy if exists "games_acesso_publico"          on games;
drop policy if exists "players_acesso_publico"        on players;
drop policy if exists "Acesso público de leitura"     on players;
drop policy if exists "Acesso público de escrita"     on players;
drop policy if exists "Acesso público de atualização" on players;
drop policy if exists "Acesso público de remoção"     on players;
drop policy if exists games_leitura         on games;
drop policy if exists games_organizador     on games;
drop policy if exists players_leitura       on players;
drop policy if exists players_organizador   on players;

create policy games_leitura   on games   for select using (true);
create policy players_leitura on players for select using (true);

-- ============================================================
--  FUNÇÕES
--  security definer = a função corre com permissões elevadas,
--  por isso consegue escrever apesar das regras acima. Cada uma
--  faz só uma coisa, valida o que recebe, e as de organizador
--  conferem o código antes de tocar em qualquer dado.
-- ============================================================

drop function if exists join_game(date, text, uuid);
drop function if exists leave_game(uuid, uuid);
drop function if exists is_admin(text);
drop function if exists admin_set_paid(uuid, boolean, text);
drop function if exists admin_remove_player(uuid, text);
drop function if exists admin_open_game(date, text, integer, numeric, text);
drop function if exists admin_update_game(date, text, integer, numeric, text);
drop function if exists admin_set_teams(date, jsonb, text);

-- ---------- entrar e sair sem código ----------

create function join_game(p_date date, p_name text, p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_nome text := btrim(p_name);
begin
  if v_nome = '' or length(v_nome) > 60 then
    raise exception 'Nome inválido';
  end if;
  if not exists (select 1 from games where game_date = p_date) then
    raise exception 'Não há jogo aberto nessa data';
  end if;

  insert into players (game_date, name, paid) values (p_date, v_nome, false)
  returning id into v_id;

  insert into player_claims (player_id, token) values (v_id, p_token);
  return v_id;
end $$;

create function leave_game(p_id uuid, p_token uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_ok boolean;
begin
  select exists (
    select 1 from player_claims where player_id = p_id and token = p_token
  ) into v_ok;
  if v_ok then delete from players where id = p_id; end if;
  return v_ok;
end $$;

-- ---------- conferir o código do organizador ----------

create function is_admin(p_secret text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from admin_secrets where hash = crypt(p_secret, hash)
  );
$$;

-- ---------- ações de organizador ----------

create function admin_set_paid(p_id uuid, p_paid boolean, p_secret text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin(p_secret) then raise exception 'Código incorreto'; end if;
  update players set paid = p_paid where id = p_id;
  return found;
end $$;

create function admin_remove_player(p_id uuid, p_secret text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin(p_secret) then raise exception 'Código incorreto'; end if;
  delete from players where id = p_id;
  return found;
end $$;

-- Cria (ou reabre) o jogo de uma data — usado tanto pro primeiro
-- jogo quanto pra abrir a próxima semana. Não mexe num jogo que já
-- existe além de atualizar hora/vagas/valor.
create function admin_open_game(p_date date, p_kickoff text, p_slots integer, p_price numeric, p_secret text)
returns games
language plpgsql
security definer
set search_path = public
as $$
declare v_row games;
begin
  if not is_admin(p_secret) then raise exception 'Código incorreto'; end if;

  insert into games (game_date, kickoff, slots, price, teams)
  values (p_date, coalesce(p_kickoff, '10:00'), coalesce(p_slots, 15), coalesce(p_price, 0), null)
  on conflict (game_date) do update
    set kickoff = excluded.kickoff, slots = excluded.slots, price = excluded.price
  returning * into v_row;

  return v_row;
end $$;

-- Muda hora/vagas/valor do jogo atual. Sempre limpa o sorteio,
-- porque mudar vagas muda quem é titular e quem é reserva.
create function admin_update_game(p_date date, p_kickoff text, p_slots integer, p_price numeric, p_secret text)
returns games
language plpgsql
security definer
set search_path = public
as $$
declare v_row games;
begin
  if not is_admin(p_secret) then raise exception 'Código incorreto'; end if;

  update games set
    kickoff = coalesce(p_kickoff, kickoff),
    slots   = coalesce(p_slots, slots),
    price   = coalesce(p_price, price),
    teams   = null,
    updated_at = now()
  where game_date = p_date
  returning * into v_row;

  return v_row;
end $$;

create function admin_set_teams(p_date date, p_teams jsonb, p_secret text)
returns games
language plpgsql
security definer
set search_path = public
as $$
declare v_row games;
begin
  if not is_admin(p_secret) then raise exception 'Código incorreto'; end if;

  update games set teams = p_teams, updated_at = now() where game_date = p_date
  returning * into v_row;

  return v_row;
end $$;

revoke all on function join_game(date, text, uuid)                          from public;
revoke all on function leave_game(uuid, uuid)                               from public;
revoke all on function is_admin(text)                                       from public;
revoke all on function admin_set_paid(uuid, boolean, text)                  from public;
revoke all on function admin_remove_player(uuid, text)                      from public;
revoke all on function admin_open_game(date, text, integer, numeric, text)  from public;
revoke all on function admin_update_game(date, text, integer, numeric, text) from public;
revoke all on function admin_set_teams(date, jsonb, text)                   from public;

grant execute on function join_game(date, text, uuid)                          to anon, authenticated;
grant execute on function leave_game(uuid, uuid)                               to anon, authenticated;
grant execute on function is_admin(text)                                      to anon, authenticated;
grant execute on function admin_set_paid(uuid, boolean, text)                  to anon, authenticated;
grant execute on function admin_remove_player(uuid, text)                      to anon, authenticated;
grant execute on function admin_open_game(date, text, integer, numeric, text)  to anon, authenticated;
grant execute on function admin_update_game(date, text, integer, numeric, text) to anon, authenticated;
grant execute on function admin_set_teams(date, jsonb, text)                   to anon, authenticated;

-- ============================================================
--  TEMPO REAL
-- ============================================================
alter table games   replica identity full;
alter table players replica identity full;

do $$
begin
  begin alter publication supabase_realtime add table games;
  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table players;
  exception when duplicate_object then null; end;
end $$;

-- ============================================================
--  ÚLTIMO PASSO — DEPOIS DE RODAR TUDO ACIMA
--  Troque os dois códigos abaixo pelos que só vocês dois vão
--  saber (qualquer texto, quanto mais longo e menos óbvio,
--  melhor), e rode só este bloco separado:
--
--   insert into admin_secrets (label, hash) values
--     ('joao',  crypt('TROQUE-PELO-CODIGO-DO-JOAO', gen_salt('bf'))),
--     ('socio', crypt('TROQUE-PELO-CODIGO-DO-SOCIO', gen_salt('bf')));
--
--  Os códigos nunca ficam salvos em texto puro, nem aqui nem no
--  banco — só o hash. Guarda-os num gerenciador de senhas.
-- ============================================================
