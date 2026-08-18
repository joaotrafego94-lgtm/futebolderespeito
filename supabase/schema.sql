-- ============================================================
--  FUTEBOL DE RESPEITO — esquema da base de dados
--  Corre este ficheiro inteiro no SQL Editor do Supabase.
--  Podes correr outra vez sem estragar nada (é idempotente).
-- ============================================================

-- ------------------------------------------------------------
--  JOGOS
--  Uma linha por jogo. Guarda a data, hora, vagas, preço e as
--  equipas sorteadas. Fica aqui (e não no telemóvel de cada um)
--  para que toda a gente veja exatamente o mesmo jogo.
-- ------------------------------------------------------------
create table if not exists games (
  game_date  date primary key,
  kickoff    text        not null default '10:00',
  slots      integer     not null default 15,
  price      numeric(6,2) not null default 0,
  teams      jsonb,
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
--  JOGADORES
--  Uma linha por inscrição. A ordem de chegada (created_at)
--  decide quem é titular e quem fica como suplente.
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
--  ACESSO
--  Grupo de amigos: quem tiver o link pode ler e escrever.
--  A chave anon é pública por natureza (vai dentro do HTML).
--  Se um dia quiseres fechar isto, troca as políticas abaixo
--  por políticas com autenticação Supabase.
-- ------------------------------------------------------------
alter table games   enable row level security;
alter table players enable row level security;

drop policy if exists "games_acesso_publico"   on games;
drop policy if exists "players_acesso_publico" on players;

create policy "games_acesso_publico"   on games   for all using (true) with check (true);
create policy "players_acesso_publico" on players for all using (true) with check (true);

-- ------------------------------------------------------------
--  TEMPO REAL
--  Faz a lista mexer sozinha no telemóvel de todos assim que
--  alguém entra, paga ou sai.
-- ------------------------------------------------------------
alter table games   replica identity full;
alter table players replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table games;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table players;
  exception when duplicate_object then null;
  end;
end $$;
