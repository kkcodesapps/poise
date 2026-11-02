-- Eight more finishes, and the chip's metal. Null chip keeps the one the finish comes with.
alter table accounts drop constraint if exists accounts_finish_check;
alter table accounts add constraint accounts_finish_check check (finish in (
  'ocean', 'sapphire', 'sky', 'forest', 'plum', 'graphite', 'gold', 'titanium',
  'rose', 'copper', 'midnight', 'lagoon', 'sage', 'violet', 'ruby', 'sunset'));
alter table accounts add column chip text check (chip in ('gold', 'silver', 'rose', 'black'));
