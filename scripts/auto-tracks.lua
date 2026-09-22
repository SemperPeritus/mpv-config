-- Select preferred Japanese audio and Russian subtitles after mpv has loaded
-- all embedded and automatically discovered tracks.
--
-- This intentionally lives separately from subs.lua: a failure here must not
-- disable the subtitle search paths configured by that script.

local mp = require "mp"
local msg = require "mp.msg"
local options = require "mp.options"

local opts = {
    enabled = true,
    select_audio = true,
    select_subtitles = true,
}

options.read_options(opts, "auto-tracks")

local function lower(value)
    return string.lower(value or "")
end

local function contains(value, needle)
    return string.find(lower(value), needle, 1, true) ~= nil
end

local function has_token(value, token)
    local normalized = " " .. lower(value):gsub("[^%w]+", " ") .. " "
    return string.find(normalized, " " .. token .. " ", 1, true) ~= nil
end

local function any_contains(value, needles)
    for _, needle in ipairs(needles) do
        if contains(value, needle) then
            return true
        end
    end
    return false
end

local function language_is(language, aliases)
    local normalized = lower(language):gsub("[^%a]", "")
    for _, alias in ipairs(aliases) do
        if normalized == alias then
            return true
        end
    end
    return false
end

local function display_name(track)
    local title = track.title
    if title and title ~= "" then
        return title
    end

    local language = track.lang
    if language and language ~= "" then
        return language
    end

    return "track " .. tostring(track.id)
end

local function audio_score(track)
    local title = track.title or ""
    local filename = track["external-filename"] or ""
    local japanese_language = language_is(track.lang, {"jpn", "ja", "jp", "japanese"})
    local japanese_label = any_contains(title .. " " .. filename, {
        "japanese", "japan", "jpn", "日本語", "япон",
    })

    if not japanese_language and not japanese_label then
        return nil
    end

    local score = japanese_language and 1000 or 700
    local codec = lower(track.codec)
    local quality = {
        truehd = 100,
        flac = 95,
        alac = 90,
        pcm_s24le = 90,
        pcm_s16le = 85,
        dts = 80,
        eac3 = 65,
        ac3 = 55,
        opus = 50,
        aac = 45,
        mp3 = 30,
    }

    score = score + (quality[codec] or 0)
    score = score + math.min(tonumber(track["demux-channel-count"]) or 0, 8) * 2

    if any_contains(title, {"truehd", "true hd", "dts-hd", "dts hd", "lossless"}) then
        score = score + 25
    end
    if contains(title, "atmos") then
        score = score + 10
    end
    if track.default then
        score = score + 5
    end
    if track.dependent then
        score = score - 100
    end
    if track["visual-impaired"] or any_contains(title, {
        "commentary", "comment", "description", "descriptive", "коммент",
    }) then
        score = score - 500
    end

    return score
end

local function subtitle_score(track)
    local title = track.title or ""
    local filename = track["external-filename"] or ""
    local label = title .. " " .. filename
    local russian_language = language_is(track.lang, {"rus", "ru", "russian"})
    local russian_label = any_contains(label, {
        "russian", " rus ", ".rus.", "[rus]", "_rus", ".ru.", "[ru]",
        "русск", "Русск", "рус", "Рус",
    })

    if not russian_language and not russian_label then
        return nil
    end

    local score = russian_language and 1000 or 700
    local codec = lower(track.codec)

    -- Crunchyroll is the preferred Russian translation/source. "CR" is only
    -- treated as a whole token, so unrelated words do not accidentally match.
    if contains(label, "crunchyroll") or has_token(label, "cr") then
        score = score + 300
    end

    if any_contains(label, {"full", "complete", "полные", "Полные", "полный", "Полный"}) then
        score = score + 100
    end
    if any_contains(label, {
        "signs", "songs", "signs & songs", "надписи", "Надписи",
        "forced", "форсированные", "Форсированные",
    }) then
        score = score - 350
    end
    if track.forced then
        score = score - 350
    end
    if track["hearing-impaired"] or any_contains(label, {"sdh", "hearing impaired"}) then
        score = score - 100
    end

    if codec == "ass" or codec == "ssa" then
        score = score + 30
    elseif codec == "subrip" or codec == "srt" then
        score = score + 20
    elseif codec == "webvtt" then
        score = score + 10
    end
    if track.default then
        score = score + 5
    end

    return score
end

local function find_best_track(tracks, track_type, scorer)
    local best
    local best_score

    for _, track in ipairs(tracks) do
        if track.type == track_type and track.id ~= nil then
            local score = scorer(track)
            if score and (not best_score or score > best_score) then
                best = track
                best_score = score
            end
        end
    end

    return best, best_score
end

local function select_track(property, label, track, score)
    if not track then
        msg.verbose("No suitable " .. label .. " track found; keeping mpv's selection")
        return
    end

    local call_ok, set_ok = pcall(mp.set_property_native, property, track.id)
    if not call_ok or set_ok == false then
        msg.error("Could not select " .. label .. " track: " .. tostring(set_ok))
        return
    end

    msg.info(string.format(
        "Selected %s: id=%s, lang=%s, title=%s, codec=%s, score=%d",
        label,
        tostring(track.id),
        tostring(track.lang or "-"),
        display_name(track),
        tostring(track.codec or "-"),
        score
    ))
end

local function choose_tracks()
    if not opts.enabled then
        return
    end

    local tracks = mp.get_property_native("track-list", {})
    if type(tracks) ~= "table" then
        msg.warn("track-list is unavailable; keeping mpv's selections")
        return
    end

    if opts.select_audio then
        local audio, score = find_best_track(tracks, "audio", audio_score)
        select_track("aid", "Japanese audio", audio, score)
    end

    if opts.select_subtitles then
        local subtitles, score = find_best_track(tracks, "sub", subtitle_score)
        select_track("sid", "Russian subtitles", subtitles, score)
    end
end

mp.register_event("file-loaded", function()
    local ok, err = xpcall(choose_tracks, debug.traceback)
    if not ok then
        msg.error("Automatic track selection failed; playback will continue: " .. tostring(err))
    end
end)
