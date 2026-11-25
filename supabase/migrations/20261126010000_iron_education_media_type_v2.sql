-- Persist the original MIME type so Android-selected videos render as videos
-- even when a content-provider filename has no recognizable extension.
alter table public.iron_education_v2
  add column if not exists media_type text not null default 'image/jpeg';

update public.iron_education_v2
set media_type = case
  when lower(video_url) ~ '\\.(mp4|m4v)([?].*)?$' then 'video/mp4'
  when lower(video_url) ~ '\\.webm([?].*)?$' then 'video/webm'
  when lower(video_url) ~ '\\.mov([?].*)?$' then 'video/quicktime'
  else 'image/jpeg'
end
where media_type is null or media_type = 'image/jpeg';
