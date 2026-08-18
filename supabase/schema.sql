-- Corre isto no SQL Editor do teu projeto Supabase (Database -> SQL Editor)

create table if not exists players (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  paid boolean not null default false,
  game_date date not null,
  created_at timestamptz not null default now()
);

create index if not exists players_game_date_idx on players (game_date);

-- Ativa Row Level Security
alter table players enable row level security;

-- Política simples e aberta: qualquer pessoa com a chave anon (pública)
-- pode ler e escrever. Adequado para um grupo de amigos onde o link
-- não é publicamente divulgado. Se quiseres mais restrição no futuro,
-- troca isto por políticas com autenticação.
create policy "Acesso público de leitura" on players
  for select using (true);

create policy "Acesso público de escrita" on players
  for insert with check (true);

create policy "Acesso público de atualização" on players
  for update using (true);

create policy "Acesso público de remoção" on players
  for delete using (true);

-- Ativa Realtime para esta tabela (para a lista atualizar sozinha
-- nos telemóveis de todos assim que alguém adiciona/paga/remove)
alter publication supabase_realtime add table players;
