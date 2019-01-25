function isTrackTypeIsAudio(track) {
    return track.type === "audio";
}

function isTrackLanguageIsJapanese(track) {
    return track.lang.indexOf('jp') !== -1
    || track.lang.indexOf('apanese') !== -1
    || track.lang.indexOf('JAPANESE') !== -1;
}

function onFileLoaded() {
    var trackList = JSON.parse(mp.get_property('track-list'));
    var japaneseAudioTracks = trackList.filter(isTrackTypeIsAudio).filter(isTrackLanguageIsJapanese);
    var propertyName = 'track-list/' + japaneseAudioTracks[0]['ff-index'] + '/selected';
    mp.msg.log('info', propertyName);
    mp.set_property(propertyName, 'yes');
}

mp.register_event('file-loaded', onFileLoaded);
