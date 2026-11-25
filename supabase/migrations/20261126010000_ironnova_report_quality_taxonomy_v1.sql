-- IRONNOVA report quality, exercise taxonomy and install metadata
alter table public.iron_workout_exercises_v2
  add column if not exists body_region text,
  add column if not exists training_goal text,
  add column if not exists primary_muscle text,
  add column if not exists secondary_muscles text[] not null default '{}';

update public.iron_workout_exercises_v2
set
  body_region = case
    when category in ('بالاتنه','بازو') then 'بالاتنه'
    when category = 'پایین‌تنه' then 'پایین‌تنه'
    when category = 'میان‌تنه' then 'میان‌تنه'
    when category = 'موبیلیتی' and muscle_group in ('فلکسور ران') then 'پایین‌تنه'
    when category = 'موبیلیتی' then 'بالاتنه'
    when category = 'اصلاحی' and muscle_group = 'گردن' then 'گردن'
    when category = 'اصلاحی' then 'بالاتنه'
    else 'نامشخص'
  end,
  training_goal = case
    when category = 'موبیلیتی' then 'موبیلیتی'
    when category = 'اصلاحی' then 'اصلاحی'
    else 'قدرتی'
  end,
  primary_muscle = case
    when muscle_group in ('سینه','سینه بالایی','قفسه سینه') then 'سینه'
    when muscle_group = 'چهارسر و باسن' then 'چهارسر'
    when muscle_group = 'همسترینگ و باسن' then 'همسترینگ'
    when muscle_group in ('میان‌تنه','شکم') then 'میان‌تنه'
    when muscle_group = 'موبیلیتی ستون فقرات' then 'ستون فقرات'
    when muscle_group = 'سرشانه و کتف' then 'سرشانه'
    else muscle_group
  end,
  secondary_muscles = case
    when muscle_group in ('چهارسر و باسن','همسترینگ و باسن') then array['باسن']::text[]
    when muscle_group = 'سرشانه و کتف' then array['کتف']::text[]
    else '{}'::text[]
  end;

create index if not exists iron_workout_exercises_v2_region_goal_idx
  on public.iron_workout_exercises_v2 (body_region, training_goal);

alter table public.iron_app_installs_v1
  add column if not exists app_version text;

alter table public.iron_app_installs_v1
  drop constraint if exists iron_app_installs_v1_app_version_length_check;
alter table public.iron_app_installs_v1
  add constraint iron_app_installs_v1_app_version_length_check
  check (app_version is null or char_length(app_version) <= 40);

create unique index if not exists iron_education_v2_content_dedupe_idx
  on public.iron_education_v2
  (lower(btrim(title)), lower(btrim(description)), lower(btrim(category)), media_type, video_url, coalesce(thumbnail_url, ''));

update public.iron_education_v2
set is_published = false, updated_at = now()
where title = 'تصویر تست'
  and description = 'Test این بخش'
  and category = 'Test apk'
  and media_type = 'image/jpeg'
  and is_published = true;
