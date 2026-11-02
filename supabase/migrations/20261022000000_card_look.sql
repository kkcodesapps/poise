-- A card's look, chosen by the user: a name of their own and one of Poise's finishes for its art. Null keeps the
-- bank's name and the finish Poise picks for that issuer. Nothing on the sync path writes these.
alter table accounts add column nickname text check (nickname is null or length(nickname) between 1 and 40);
alter table accounts add column finish text check (finish in ('ocean', 'sapphire', 'sky', 'forest', 'plum', 'graphite', 'gold', 'titanium'));
