// Suno Desktop - AI Song & Music Composer Studio + Auto-Download WAV Engine
// ជំនួយការនិពន្ធទំនុកច្រៀង, បទភ្លេង, ចំណងជើង និង ទាញយកជា WAV ដោយស្វ័យប្រវត្តិ (v6 - Auto WAV Downloader)

(function() {
    if (window.__sunoStudioInjected) {
        // Clean up previous elements if reloaded
        const ids = [
            'suno-studio-drawer', 'suno-wav-drawer', 'suno-studio-toggle', 
            'suno-wav-toggle', 'suno-quick-bar', 'suno-studio-dock', 
            'suno-native-inline-bar', 'suno-studio-toast', 'suno-studio-css'
        ];
        ids.forEach(id => {
            const el = document.getElementById(id);
            if (el) el.remove();
        });
    }
    window.__sunoStudioInjected = true;

    // =========================================================================
    // 1. AUTO-DOWNLOAD WAV STATE & CONFIGURATION
    // =========================================================================
    let autoDownloadWav = localStorage.getItem('suno_auto_download_wav') !== 'false'; // Default TRUE
    
    // Track downloaded clip IDs in sessionStorage so we don't re-download within this session
    const downloadedClips = new Set(JSON.parse(sessionStorage.getItem('suno_downloaded_clips') || '[]'));
    
    // Existing clips on initial page load (do not auto-download these unless user asks)
    const initialExistingClips = new Set();
    let isInitialLoad = true;
    
    // Track clips actively being generated during this session
    const activeGenerations = new Set();
    let lastCreateClickTime = 0;

    function saveDownloadedClip(id) {
        downloadedClips.add(id);
        try {
            sessionStorage.setItem('suno_downloaded_clips', JSON.stringify(Array.from(downloadedClips)));
        } catch (e) {}
    }

    // Clip Database (id -> { id, title, audio_url, media_urls, status, duration, createdAt })
    const clipDatabase = new Map();

    // =========================================================================
    // 2. RIFF PCM 16-BIT STEREO WAV ENCODER (Lossless Browser Audio Synth)
    // =========================================================================
    function audioBufferToWav(buffer) {
        const numChannels = buffer.numberOfChannels;
        const sampleRate = buffer.sampleRate;
        const format = 1; // 16-bit PCM
        const bitDepth = 16;

        let samples;
        if (numChannels === 2) {
            samples = interleave(buffer.getChannelData(0), buffer.getChannelData(1));
        } else {
            samples = buffer.getChannelData(0);
        }

        const bytesPerSample = bitDepth / 8;
        const blockAlign = numChannels * bytesPerSample;
        const arrayBuf = new ArrayBuffer(44 + samples.length * bytesPerSample);
        const view = new DataView(arrayBuf);

        /* RIFF header */
        writeString(view, 0, 'RIFF');
        view.setUint32(4, 36 + samples.length * bytesPerSample, true);
        writeString(view, 8, 'WAVE');
        /* format chunk */
        writeString(view, 12, 'fmt ');
        view.setUint32(16, 16, true); // Subchunk1Size (16 for PCM)
        view.setUint16(20, format, true); // AudioFormat 1 = PCM
        view.setUint16(22, numChannels, true);
        view.setUint32(24, sampleRate, true);
        view.setUint32(28, sampleRate * blockAlign, true); // ByteRate
        view.setUint16(32, blockAlign, true);
        view.setUint16(34, bitDepth, true);
        /* data chunk */
        writeString(view, 36, 'data');
        view.setUint32(40, samples.length * bytesPerSample, true);

        // Convert Float32 [-1.0 .. 1.0] to Int16 PCM
        let offset = 44;
        for (let i = 0; i < samples.length; i++, offset += 2) {
            const s = Math.max(-1, Math.min(1, samples[i]));
            view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7FFF, true);
        }

        return new Blob([view], { type: 'audio/wav' });
    }

    function interleave(inputL, inputR) {
        const length = inputL.length + inputR.length;
        const result = new Float32Array(length);
        let index = 0;
        let inputIndex = 0;
        while (index < length) {
            result[index++] = inputL[inputIndex];
            result[index++] = inputR[inputIndex];
            inputIndex++;
        }
        return result;
    }

    function writeString(view, offset, string) {
        for (let i = 0; i < string.length; i++) {
            view.setUint8(offset + i, string.charCodeAt(i));
        }
    }

    // =========================================================================
    // 3. AUTOMATIC WAV DOWNLOAD ENGINE
    // =========================================================================
    async function downloadClipAsWav(clipId, songTitle, directAudioUrl) {
        if (!clipId) return false;
        if (downloadedClips.has(clipId)) return false;

        const cleanTitle = (songTitle || 'Suno_Song').trim().replace(/[/\\?%*:|"<>]/g, '_');
        showToast(`⏳ កំពុងដំណើរការទាញយក "${cleanTitle}" ជា WAV...`, 'warn');

        try {
            let audioData = null;
            const AudioContextClass = window.AudioContext || window.webkitAudioContext;
            const audioCtx = new AudioContextClass();

            // 1. Fetch master audio via Suno's authorized download endpoint
            try {
                console.log(`[Suno Studio] Requesting authorized master audio for clip ${clipId}...`);
                let clerkToken = null;
                try {
                    if (window.Clerk && window.Clerk.session) {
                        clerkToken = await window.Clerk.session.getToken();
                    }
                } catch (e) {}

                const dlHeaders = {};
                if (clerkToken) dlHeaders['Authorization'] = 'Bearer ' + clerkToken;

                const dlResp = await fetch(`https://suno.com/a/api/download/clip/${clipId}?format=mp3`, {
                    headers: dlHeaders,
                    credentials: 'include'
                });
                if (dlResp.ok) {
                    audioData = await dlResp.arrayBuffer();
                    console.log(`[Suno Studio] Successfully fetched master audio (${audioData.byteLength} bytes)`);
                }
            } catch (e) {
                console.warn('[Suno Studio] Authorized download endpoint notice:', e);
            }

            // 2. Fallback to direct audio URL / API if endpoint not accessible
            if (!audioData) {
                let audioUrl = directAudioUrl;
                if (!audioUrl || audioUrl.includes('forbidden')) {
                    try {
                        const apiRes = await fetch(`https://studio-api.prod.suno.com/api/clip/${clipId}`, { credentials: 'include' });
                        if (apiRes.ok) {
                            const data = await apiRes.json();
                            audioUrl = data.audio_url || data.media_urls?.[0]?.url;
                        }
                    } catch (e) {}
                }
                if (audioUrl) {
                    const res = await fetch(audioUrl, { mode: 'cors' });
                    if (res.ok) audioData = await res.arrayBuffer();
                }
            }

            if (!audioData) {
                throw new Error('Unable to retrieve audio stream from Suno.');
            }

            // 3. Decode raw audio into PCM AudioBuffer
            showToast(`⚙️ កំពុងបំលែងទៅជា Lossless 16-bit WAV (PCM)...`, 'warn');
            const audioBuffer = await audioCtx.decodeAudioData(audioData);

            // 4. Encode AudioBuffer to RIFF PCM 16-bit Stereo WAV
            const wavBlob = audioBufferToWav(audioBuffer);

            // 5. Trigger silent browser download to Downloads folder
            const fileName = `${cleanTitle}.wav`;
            const blobUrl = URL.createObjectURL(wavBlob);
            const a = document.createElement('a');
            a.style.display = 'none';
            a.href = blobUrl;
            a.download = fileName;
            document.body.appendChild(a);
            a.click();

            setTimeout(() => {
                document.body.removeChild(a);
                URL.revokeObjectURL(blobUrl);
            }, 5000);

            saveDownloadedClip(clipId);
            showToast(`🎉 បានទាញយកចម្រៀងជា WAV ជោគជ័យ!\n📁 "${fileName}"`, 'success');
            updateDownloadedUI(clipId);
            return true;
        } catch (err) {
            console.error('[Suno Studio] Auto-download WAV error:', err);
            showToast(`⚠️ បរាជ័យក្នុងការទាញយក WAV៖ ${err.message}\nកំពុងសាកល្បងចុច Download ក្នុង Suno...`, 'warn');
            return tryNativeSunoDownload(songTitle);
        }
    }

    // Native Suno download menu fallback
    async function tryNativeSunoDownload(songTitle) {
        try {
            const songRows = Array.from(document.querySelectorAll('[role="group"], [class*="song"], [class*="clip"]'));
            for (const row of songRows) {
                if (songTitle && row.textContent.includes(songTitle)) {
                    const moreBtn = row.querySelector('button[aria-label*="More options" i]') || row.querySelector('button:has(svg)');
                    if (moreBtn) {
                        moreBtn.click();
                        await new Promise(r => setTimeout(r, 300));
                        const menuItems = Array.from(document.querySelectorAll('[role="menuitem"]'));
                        const dlItem = menuItems.find(el => el.textContent.toLowerCase().includes('download'));
                        if (dlItem) {
                            dlItem.click();
                            await new Promise(r => setTimeout(r, 400));
                            const subItems = Array.from(document.querySelectorAll('[role="menuitem"]'));
                            const wavItem = subItems.find(el => el.textContent.toLowerCase().includes('wav'));
                            if (wavItem) {
                                wavItem.click();
                                showToast(`✓ បានចុចទាញយក WAV តាម Suno Menu!`, 'success');
                                return true;
                            }
                        }
                    }
                }
            }
        } catch (e) {
            console.error('Native download attempt failed:', e);
        }
        return false;
    }

    // Expose download API globally for host and external scripts
    window.downloadClipAsWav = downloadClipAsWav;
    window.sunoDirectDownload = async function(url) {
        if (!url) return false;
        const match = url.match(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/i);
        if (!match) return false;
        const clipId = match[0];
        console.log('[Suno Studio] sunoDirectDownload triggered for clip:', clipId);
        showToast(`⏳ កំពុងដំណើរការទាញយក ${clipId} ជា WAV...`, 'warn');
        return await downloadClipAsWav(clipId, 'Suno_Song_' + clipId.slice(0, 8));
    };

    // =========================================================================
    // 4. NETWORK INTERCEPTOR (window.fetch & XMLHttpRequest)
    // =========================================================================
    function handleClipData(clips) {
        if (!Array.isArray(clips)) clips = [clips];

        clips.forEach(clip => {
            if (!clip || !clip.id) return;

            const prev = clipDatabase.get(clip.id);
            let audioUrl = clip.audio_url;
            if (clip.media_urls && clip.media_urls.length > 0) {
                audioUrl = clip.media_urls[0].url;
            }

            const title = clip.title || prev?.title || 'Suno_Song';
            const status = clip.status || prev?.status || 'unknown';

            clipDatabase.set(clip.id, {
                id: clip.id,
                title: title,
                audio_url: audioUrl,
                status: status,
                duration: clip.metadata?.duration || clip.duration,
                discoveredAt: prev?.discoveredAt || Date.now()
            });

            // On initial load, register existing complete clips so they aren't auto-downloaded
            if (isInitialLoad && status === 'complete') {
                initialExistingClips.add(clip.id);
            }

            // AUTO-DOWNLOAD TRIGGER CONDITION:
            // 1. Auto-download is ON
            // 2. Status is 'complete'
            // 3. Not already downloaded in this session
            // 4. Not an existing old clip from initial page load OR was actively generated in this session
            const isCompleted = (status === 'complete');
            const isNotDownloaded = !downloadedClips.has(clip.id);
            const isTargetSessionClip = activeGenerations.has(clip.id) || !initialExistingClips.has(clip.id) || (Date.now() - lastCreateClickTime < 900000);

            if (autoDownloadWav && isCompleted && isNotDownloaded && isTargetSessionClip && !isInitialLoad) {
                console.log(`[Suno Studio] Auto-downloading new completed clip: ${title} (${clip.id})`);

                // 1. Send IPC message to host (Suno.exe) to trigger SunoDownloader.exe
                if (window.chrome && window.chrome.webview) {
                    try {
                        window.chrome.webview.postMessage({
                            type: 'song_completed',
                            clipId: clip.id,
                            title: title,
                            url: `https://suno.com/song/${clip.id}`,
                            format: 'wav'
                        });
                    } catch (e) {}
                }

                // 2. Decode and save locally in browser
                downloadClipAsWav(clip.id, title, audioUrl);
            }
        });

        updateRecentSongsUI();

        // Auto-Check and deduplicate sibling clip titles in real-time
        if (!isInitialLoad && typeof autoCheckAndDedupSiblingClips === 'function') {
            setTimeout(autoCheckAndDedupSiblingClips, 1800);
        }
    }

    function parseResponseForClips(data) {
        if (!data) return;
        try {
            if (Array.isArray(data)) {
                handleClipData(data);
            } else if (typeof data === 'object') {
                if (data.id && (data.audio_url || data.status || data.title)) {
                    handleClipData(data);
                }
                if (Array.isArray(data.clips)) handleClipData(data.clips);
                if (Array.isArray(data.feed)) handleClipData(data.feed);
                if (Array.isArray(data.data)) handleClipData(data.data);
            }
        } catch (e) {
            console.error('[Suno Studio] Error parsing clip data:', e);
        }
    }

    // Intercept window.fetch & XMLHttpRequest (Guarded against double wrapping)
    if (!window.__sunoNetworkIntercepted) {
        window.__sunoNetworkIntercepted = true;
        const rawFetch = window.fetch;
        window.fetch = async function(...args) {
            try {
                // Capture device-id header if sent by Suno client
                const reqHeaders = args[1]?.headers || (args[0] instanceof Request ? args[0].headers : null);
                if (reqHeaders) {
                    if (reqHeaders instanceof Headers) {
                        const did = reqHeaders.get('device-id') || reqHeaders.get('Device-Id') || reqHeaders.get('DEVICE-ID');
                        if (did) window.__sunoDeviceId = did;
                    } else if (typeof reqHeaders === 'object') {
                        const did = reqHeaders['device-id'] || reqHeaders['Device-Id'] || reqHeaders['DEVICE-ID'];
                        if (did) window.__sunoDeviceId = did;
                    }
                }
            } catch (e) {}

            const response = await rawFetch.apply(this, args);
            try {
                const url = (typeof args[0] === 'string' ? args[0] : (args[0]?.url || ''));
                if (url.includes('/feed') || url.includes('/clip') || url.includes('/project') || url.includes('suno.com') || url.includes('studio-api')) {
                    const clone = response.clone();
                    clone.json().then(data => parseResponseForClips(data)).catch(() => {});
                }
            } catch (e) {}
            return response;
        };

        // Intercept XMLHttpRequest
        const rawXhrOpen = XMLHttpRequest.prototype.open;
        const rawXhrSend = XMLHttpRequest.prototype.send;
        const rawSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
        XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
            try {
                if (header && header.toLowerCase() === 'device-id' && value) {
                    window.__sunoDeviceId = value;
                }
            } catch (e) {}
            return rawSetRequestHeader.apply(this, arguments);
        };
        XMLHttpRequest.prototype.open = function(method, url) {
            this._sunoUrl = url;
            return rawXhrOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function(body) {
            this.addEventListener('load', function() {
                try {
                    if (this._sunoUrl && (this._sunoUrl.includes('/feed') || this._sunoUrl.includes('/clip') || this._sunoUrl.includes('suno.com'))) {
                        const data = JSON.parse(this.responseText);
                        parseResponseForClips(data);
                    }
                } catch (e) {}
            });
            return rawXhrSend.apply(this, arguments);
        };
    }

    // Mark initial load finished after 4 seconds
    setTimeout(() => {
        isInitialLoad = false;
        console.log(`[Suno Studio] Initial catalog indexed: ${initialExistingClips.size} existing clips.`);
    }, 4000);

    // =========================================================================
    // 5. DOM OBSERVER & GENERATION MONITOR
    // =========================================================================
    // Track when user clicks "Create"
    document.addEventListener('click', (e) => {
        const btn = e.target.closest('button, [role="button"]');
        if (btn) {
            const text = (btn.textContent || '').trim().toLowerCase();
            const aria = (btn.getAttribute('aria-label') || '').toLowerCase();
            if (text === 'create' || text.includes('create song') || aria.includes('create song')) {
                lastCreateClickTime = Date.now();
                showToast('🚀 កំពុងបង្កើតចម្រៀងលើ Suno... កម្មវិធីនឹងទាញយកជា WAV ដោយស្វ័យប្រវត្តិនៅពេលរួចរាល់!', 'success');
            }
        }
    }, true);

    // Periodic DOM poller (every 2.5 seconds) to catch finished songs
    setInterval(() => {
        const songLinks = Array.from(document.querySelectorAll('a[href*="/song/"]'));
        songLinks.forEach(link => {
            const href = link.getAttribute('href') || '';
            const match = href.match(/\/song\/([a-f0-9-]{36})/i);
            if (!match) return;
            const clipId = match[1];

            // Get row element
            const row = link.closest('[role="group"]') || link.closest('article') || link.parentElement?.parentElement;
            if (!row) return;

            const rowText = row.innerText || '';
            const titleEl = row.querySelector('h4, [class*="title"], a[href*="/song/"]');
            const title = (titleEl ? titleEl.innerText : link.innerText || 'Suno_Song').trim();

            // Check if duration is visible (e.g. 5:17, 3:30) which signifies complete audio
            const hasDuration = /\d+:\d{2}/.test(rowText);
            const isGenerating = rowText.toLowerCase().includes('generating') || 
                                 rowText.toLowerCase().includes('streaming') || 
                                 row.querySelector('[role="progressbar"], [class*="spinner"], [class*="loading"]');

            if (isGenerating) {
                activeGenerations.add(clipId);
            }

            if (hasDuration && !isGenerating) {
                // If this was an active generation, or created recently
                if (autoDownloadWav && !downloadedClips.has(clipId)) {
                    if (activeGenerations.has(clipId) || (!initialExistingClips.has(clipId) && !isInitialLoad)) {
                        console.log(`[Suno Studio] DOM poller detected newly completed song: ${title} (${clipId})`);
                        downloadClipAsWav(clipId, title);
                    }
                }
            }
        });
    }, 2500);

    // =========================================================================
    // 6. SONG KNOWLEDGE ENGINE (Themes, Lyrics & Styles)
    // =========================================================================
    const songData = {
        genres: [
            { id: 'khmer_modern_pop', name: '១. ខ្មែរ Modern Pop (ពីរោះ រំជួលចិត្ត)', style: 'Contemporary Khmer Pop, melodic piano, acoustic guitar, soft khmer kloy flute, emotional female vocal, 82 bpm, pristine production, warm acoustic reverb, radio hit' },
            { id: 'romantic_ballad', name: '២. បទមនោសញ្ចេតនា (Romantic Acoustic Ballad)', style: 'Sentimental acoustic ballad, warm grand piano, nylon acoustic guitar, ambient orchestral strings, heartfelt male vocals, 72 bpm, melancholic, intimate, slow tempo, soulful' },
            { id: 'khmer_romvong', name: '៣. ចង្វាក់ប្រជាប្រិយទំនើប (Romvong / Saravan)', style: 'Modern Khmer Romvong dance pop, tro, roneat, joyful melodic synthesizer, upbeat live drums, festive male and female choir, 118 bpm, happy celebration, khmer festival' },
            { id: 'edm_dance', name: '៤. EDM Festival & Club Dance (រាំញាក់ កន្ត្រាក់អារម្មណ៍)', style: 'Modern dance pop EDM, bright synth chords, punchy four-on-the-floor kick, euphoric festival drop, vocal chops, heavy bassline, 128 bpm, high energy party anthem' },
            { id: 'drift_phonk', name: '៥. Drift Phonk & Heavy 808 (Bass កក្រើក)', style: 'Aggressive drift phonk, distorted cowbells, heavy 808 sub-bass, rapid hi-hat rolls, dark atmospheric reverb, energetic street racing vibe, Memphis vocal samples, 140 bpm' },
            { id: 'rnb_soul', name: '៦. R&B / Soul សម័យថ្មី (ស្រទន់ រាត្រីកាល)', style: 'Modern R&B soul, lush Rhodes electric piano, smooth 808 bass, soulful vocal runs, sensual groove, 85 bpm, chill atmospheric reverb, late night vibing' },
            { id: 'acoustic_lofi', name: '៧. Acoustic / Lo-fi ស្ងប់ស្ងាត់ (លំហែចិត្ត)', style: 'Lo-fi acoustic chillhop, mellow fingerstyle acoustic guitar, vinyl crackle, gentle jazz drums, soft whispery vocal, 75 bpm, cozy relaxing study vibe, warm tape saturation' },
            { id: 'pop_rock', name: '៨. Pop Rock & Arena Anthem (ស្វាហាប់ កម្លាំងចិត្ត)', style: 'Energetic pop rock anthem, driving distorted electric guitar riffs, punchy drums, powerful melodic chorus, passionate male vocal, 130 bpm, stadium rock, uplifting' },
            { id: 'hiphop_trap', name: '៩. Khmer Hip-Hop & Rap Beat (ចង្វាក់ញាក់ទាន់សម័យ)', style: 'Modern Khmer Hip-Hop, melodic trap synth, deep sliding 808 bass, crisp percussion, rhythmic flow, catchy hook, urban street beat, 95 bpm' },
            { id: 'orchestral_epic', name: '១០. Orchestral Cinematic Epic (ចង្វាក់ភាពយន្ត អធិកអធម)', style: 'Cinematic orchestral film score, thunderous taiko percussion, sweeping dramatic strings, epic brass fanfare, heroic choir, emotional climax, 90 bpm, Hans Zimmer style' }
        ],
        themes: [
            {
                id: 'love_sweet',
                name: 'ក្ដីស្រឡាញ់ផ្អែមល្ហែម (Sweet Romance)',
                defaultTitle: 'ម្ចាស់បេះដូងអូន',
                lyricsKhmer: [
                    "[Intro - Soft Acoustic Guitar & Piano Melody]\n(អូ... ហូ... ជួបអូនគ្រាដំបូង...)\n",
                    "[Verse 1]\nរាល់ពេលឃើញស្នាមញញឹមថ្លៃ បេះដូងរំភើបឥតឧបមា\nកែវភ្នែកស្រទន់ដូចតារា បំភ្លឺចិន្តាឱ្យភ្លឺថ្លា\nដើរកាត់ខ្យល់ត្រជាក់រាត្រី មានរូបថ្លៃក្បែរប្រាណ\nក្ដីសុខសាមញ្ញតែមានន័យ គ្មានអ្វីផ្ទឹមបាន\n",
                    "[Pre-Chorus]\nទោះបីថ្ងៃស្អែកទៅជាយ៉ាងណា\nចិត្តមួយនេះសន្យា ស្រឡាញ់តែអូន\n",
                    "[Chorus]\nអូនជាដង្ហើម ជាក្ដីសុខក្នុងជីវិត\nស្រឡាញ់ស្មោះពិត គ្មានថ្ងៃប្រែប្រួលឡើយ\nកាន់ដៃបងឆ្លងកាត់រាល់ឧបសគ្គកន្លង\nមានតែរូបអូន ជាម្ចាស់បេះដូងបងរហូត\n",
                    "[Verse 2]\nពេលមានទុក្ខកង្វល់ក្នុងចិត្ត ស្នាមញញឹមអូនលួងលោម\nរាល់ពាក្យផ្អែមល្ហែមដូចទឹកឃ្មុំ ថ្នាក់ថ្នមចិត្តកាយ\nសូមអរគុណមេឃដែលប្រទានអូនមកឱ្យបង\nមិនឱ្យរបូតបាត់បង់ ស្នេហ៍ដ៏មានន័យ\n",
                    "[Bridge - Traditional Flute & Strings Solo]\n(ភ្លេងខ្លុយ និង ហ្គីតារំជួលចិត្ត...)\nទោះមេឃរលាយ ផ្កាយរលត់អស់ពីដួងចិត្ត\nក្ដីស្រឡាញ់ពិត នៅតែមានសម្រាប់អូន\n",
                    "[Chorus]\nអូនជាដង្ហើម ជាក្ដីសុខក្នុងជីវិត\nស្រឡាញ់ស្មោះពិត គ្មានថ្ងៃប្រែប្រួលឡើយ\nកាន់ដៃបងឆ្លងកាត់រាល់ឧបសគ្គកន្លង\nមានតែរូបអូន ជាម្ចាស់បេះដូងបងរហូត\n",
                    "[Outro - Fade Out with Gentle Piano]\nស្រឡាញ់អូន... ជារៀងរហូត...\n(Fade Out...)"
                ].join('\n')
            },
            {
                id: 'heartbreak_sad',
                name: 'ស្នេហាបែកបាក់ ទឹកភ្នែកក្រោមភ្លៀង (Sad Heartbreak)',
                defaultTitle: 'ទឹកភ្នែកក្រោមតំណក់ភ្លៀង',
                lyricsKhmer: [
                    "[Intro - Melancholic Piano & Rain Sound Effect]\n(តំណក់ទឹកភ្លៀង... ស្រក់កាត់បេះដូង...)\n",
                    "[Verse 1]\nភ្លៀងធ្លាក់ស្រក់កាត់បង្អួចចាស់ ដូចទឹកភ្នែកហូរមិនឈប់\nការចងចាំរឿងរ៉ាវគ្រប់យ៉ាង នៅតែដិតជាប់រាល់យប់\nធ្លាប់ដើរកាត់ភ្លៀងជាមួយគ្នា ឥឡូវនៅសល់តែបង\nពាក្យថាស្នេហ៍ដែលអូនធ្លាប់ផ្ដល់ រសាត់បាត់អស់ហើយថ្លៃ\n",
                    "[Pre-Chorus]\nតើបងធ្វើខុសអ្វី ទើបអូនចាកចេញគ្មានស្ដាយ?\nទុកឱ្យបេះដូងមួយនេះ រងាវខ្លោចផ្សា\n",
                    "[Chorus]\nទឹកភ្នែកហូរស្រក់កាត់ថ្ពាល់ លាយឡំនឹងទឹកភ្លៀង\nឈឺចាប់ឥតល្ហែ ពេលស្នេហ៍ត្រូវប្រេះឆា\nជូនពរឱ្យអូនបានសុខ ជាមួយអ្នកថ្មីថ្លៃថ្លា\nទុកការឈឺផ្សា ឱ្យបងជាអ្នករ៉ាប់រង\n",
                    "[Verse 2]\nអង្គុយមើលរូបថតចាស់ៗ ដែលយើងធ្លាប់សើចជាមួយគ្នា\nពេលនេះក្លាយជារឿងអតីត ដែលគ្មានថ្ងៃវិលត្រឡប់\nខំប្រាប់បេះដូងឱ្យបំភ្លេច តែចិត្តមិនព្រមស្ដាប់\nនៅតែនឹក នៅតែស្រឡាញ់ ទោះអូនក្បត់ចិត្ត\n",
                    "[Bridge - Crying Guitar Solo]\n(ហ្គីតាទួញសោក... យ៉ាងឈឺចាប់...)\nបើសិនពេលវេលាអាចថយក្រោយ...\nបងនឹងមិនជ្រើសរើសឱ្យយើងស្គាល់គ្នា...\n",
                    "[Chorus]\nទឹកភ្នែកហូរស្រក់កាត់ថ្ពាល់ លាយឡំនឹងទឹកភ្លៀង\nឈឺចាប់ឥតល្ហែ ពេលស្នេហ៍ត្រូវប្រេះឆា\nជូនពរឱ្យអូនបានសុខ ជាមួយអ្នកថ្មីថ្លៃថ្លា\nទុកការឈឺផ្សា ឱ្យបងជាអ្នករ៉ាប់រង\n",
                    "[Outro - Slow Piano]\nលាហើយស្នេហា... លាហើយមនុស្សដែលបងស្រឡាញ់...\n(Fade Out)"
                ].join('\n')
            },
            {
                id: 'homesick_mother',
                name: 'នឹកផ្ទះ នឹកម៉ែ ស្រុកកំណើត (Homesick & Mother)',
                defaultTitle: 'នឹកម៉ែស្រុកស្រែ',
                lyricsKhmer: [
                    "[Intro - Traditional Khmer Kloy Flute & Acoustic Guitar]\n(សំឡេងខ្លុយស្រុកស្រែ... នឹកដល់អ្នកម្ដាយ...)\n",
                    "[Verse 1]\nខ្យល់រំភើយបក់មកពីទិសខាងកើត នឹកស្រុកកំណើតធ្លាប់រស់នៅ\nនឹកក្លិនបាយក្ដៅម្ដាយដាំ នឹកផ្ទះស្លឹកចាស់ម្លប់ជ្រៃ\nកូនមកតស៊ូនៅទីក្រុង ឆ្ងាយស្រុកឆ្ងាយភូមិ\nរាល់រាត្រីសម្លឹងមើលផ្កាយ នឹកម៉ែឪរាល់វេលា\n",
                    "[Pre-Chorus]\nឮសូរសំឡេងម៉ែតាមទូរស័ព្ទ សួរកូនថាញ៉ាំបាយហើយឬនៅ?\nទឹកភ្នែកកូនហូរដោយមិនដឹងខ្លួន នឹកម៉ែណាស់\n",
                    "[Chorus]\nម៉ែអើយកូននឹកម៉ែណាស់ នឹកទាំងដំបូន្មាន\nកូនខំតស៊ូធ្វើការងារ ដើម្បីអនាគតថ្លៃថ្លា\nរង់ចាំកូនណាអ្នកម្ដាយ មិនយូរឡើយកូននឹងត្រឡប់\nយកជោគជ័យទៅជូនម៉ែ ជួបជុំគ្រួសារ\n",
                    "[Verse 2]\nឃើញដៃម៉ែគគ្រើមព្រោះធ្វើការ ទឹកភ្នែកហូរស្រក់ស្រណោះ\nម៉ែរងទុក្ខវេទនាដើម្បីកូន មិនដែលរអ៊ូពាក្យហត់នឿយ\nគុណម៉ែធំធេងដូចមហាសាគរ រកអ្វីប្រៀបផ្ទឹមគ្មាន\nកូនសូមសំពះបួងសួង សូមឱ្យម៉ែមានសុខភាពល្អ\n",
                    "[Bridge - Emotional Tro & Flute Harmony]\n(សំឡេងទ្រ និង ខ្លុយរំជួលចិត្ត... នឹកភូមិកំណើត...)\nកូននឹងវិលទៅរកផ្ទះយើងវិញ ម៉ែរង់ចាំកូនណា...\n",
                    "[Chorus]\nម៉ែអើយកូននឹកម៉ែណាស់ នឹកទាំងដំបូន្មាន\nកូនខំតស៊ូធ្វើការងារ ដើម្បីអនាគតថ្លៃថ្លា\nរង់ចាំកូនណាអ្នកម្ដាយ មិនយូរឡើយកូននឹងត្រឡប់\nយកជោគជ័យទៅជូនម៉ែ ជួបជុំគ្រួសារ\n",
                    "[Outro - Soft Flute Melody]\nកូនស្រឡាញ់ម៉ែ... ស្រឡាញ់រហូត...\n(Fade Out)"
                ].join('\n')
            },
            {
                id: 'motivational_rise',
                name: 'លើកទឹកចិត្ត កុំចុះចាញ់ (Motivational / Never Give Up)',
                defaultTitle: 'អ្នកចម្បាំងជីវិត',
                lyricsKhmer: [
                    "[Intro - Building Drum Beats & Electric Guitar]\n(បោះជំហានទៅមុខ... គ្មានអ្វីរារាំងយើងបាន...)\n",
                    "[Verse 1]\nទោះផ្លូវខាងមុខមានបន្លា ឧបសគ្គរាប់រយរាប់ពាន់\nដួលប៉ុន្មានដងត្រូវតែងើប មិនត្រូវចុះចាញ់ព្រហ្មលិខិត\nញើសហូរស្រក់ដើម្បីក្ដីស្រមៃ ខំប្រឹងតស៊ូឥតឈប់\nថ្ងៃស្អែកនឹងជាថ្ងៃរបស់យើង ជោគជ័យនឹងមកដល់\n",
                    "[Pre-Chorus]\nជឿជាក់លើខ្លួនឯង ជឿលើកម្លាំងចិត្ត\nគ្មានអ្វីដែលថាមិនអាចធ្វើបាន បើយើងមិនបោះបង់\n",
                    "[Chorus]\nក្រោកឈរឡើង! ហោះហើរទៅលើមេឃាក្រឡាស់\nបញ្ចេញពន្លឺក្នុងចិត្ត ឱ្យលោកដឹងថាយើងខ្លាំង\nទោះខ្យល់ព្យុះបក់បោក ក៏មិនរាថយ\nយើងជាអ្នកចម្បាំង ក្តោបក្តាប់ជ័យជម្នះក្នុងដៃ!\n",
                    "[Verse 2]\nការរិះគន់រាប់ពាន់សម្តី ក្លាយជាកម្លាំងរុញច្រាន\nឱ្យយើងកាន់តែរឹងមាំ មិនទន់ជ្រាយដូចពីមុន\nរាល់ដំណក់ញើសដែលបានស្រក់ នឹងក្លាយជាពេជ្រចាំងចែង\nស្មាមញញឹមនៃជ័យជម្នះ នឹងបំភ្លឺជីវិត\n",
                    "[Bridge - Powerful Rock Guitar Solo & Heavy Drums]\n(ហ្គីតាវាយយ៉ាងកក្រើក... បង្ហាញភាពក្លាហាន...)\nស្រែកឱ្យអស់ពីចិត្ត! នេះជាពេលវេលារបស់យើង!\n",
                    "[Chorus]\nក្រោកឈរឡើង! ហោះហើរទៅលើមេឃាក្រឡាស់\nបញ្ចេញពន្លឺក្នុងចិត្ត ឱ្យលោកដឹងថាយើងខ្លាំង\nទោះខ្យល់ព្យុះបក់បោក ក៏មិនរាថយ\nយើងជាអ្នកចម្បាំង ក្តោបក្តាប់ជ័យជម្នះក្នុងដៃ!\n",
                    "[Outro - Triumphant Ending]\nជ័យជម្នះជារបស់យើង! កុំចុះចាញ់!\n(Big Final Drum Hit)"
                ].join('\n')
            },
            {
                id: 'khmer_party_dance',
                name: 'រាំកម្សាន្តចូលឆ្នាំ សប្បាយរីករាយ (Khmer Party / New Year Dance)',
                defaultTitle: 'រាំកម្សាន្តចូលឆ្នាំថ្មី',
                lyricsKhmer: [
                    "[Intro - Lively Roneat, Tro & Modern Dance Beat]\n(អេវ៉ា... រាំលេងសប្បាយ... ចូលឆ្នាំថ្មីប្រពៃណីខ្មែរ!)\n",
                    "[Verse 1]\nសូរស័ព្ទស្គរដៃបន្លឺកងរំពង បងប្អូនជួបជុំភូមិផងរបងជាមួយ\nផ្កាឈូកផ្ការំដួលរីកស្គុសស្គាយ ស្រីស្រស់ប្រិមប្រិយញញឹមស្រស់ថ្លា\nតោះនាំគ្នារាំកម្សាន្ត ចង្វាក់រាំវង់សារ៉ាវ៉ាន់\nភ្លេចទុក្ខកង្វល់ឱ្យអស់ រីករាយគ្រប់គ្នា\n",
                    "[Pre-Chorus]\nតោះរាំ! តោះរាំ! កុំនៅឈរស្ងៀម\nតាក់ទែនទែនតាក់ រាំលេងសប្បាយ!\n",
                    "[Chorus]\nរាំទៅៗ កុំនៅអៀនខ្មាស\nចូលឆ្នាំថ្មីហើយ សប្បាយណាស់ណា\nជូនពរពុកម៉ែ បងប្អូនជិតឆ្ងាយ\nសុខសប្បាយ រកស៊ីមានបានគ្រប់គ្នា!\n",
                    "[Verse 2]\nយុវជនយុវតីស្លៀកពាក់ចម្រុះពណ៌ រាំបណ្ដាក់គ្នាជារង្វង់មូល\nលេងល្បែងប្រជាប្រិយចោលឈូង បោះអង្គញ់ និងទាញព្រ័ត្រ\nសើចសប្បាយក្អាកក្អាយ ពេញភូមិកំណើត\nមោទនភាពជាតិខ្មែរ ប្រពៃណីថ្លៃថ្លា\n",
                    "[Bridge - Festive Percussion & Cheering]\n(ហោរ... ជយោ! រាំកន្ត្រាក់អារម្មណ៍!)\n",
                    "[Chorus]\nរាំទៅៗ កុំនៅអៀនខ្មាស\nចូលឆ្នាំថ្មីហើយ សប្បាយណាស់ណា\nជូនពរពុកម៉ែ បងប្អូនជិតឆ្ងាយ\nសុខសប្បាយ រកស៊ីមានបានគ្រប់គ្នា!\n",
                    "[Outro - Fast Upbeat Finish]\nជយោចូលឆ្នាំថ្មី! សប្បាយៗ!\n(Drum Roll & Cymbal Crash)"
                ].join('\n')
            },
            {
                id: 'drift_racing',
                name: '៦. ចង្វាក់រថយន្តប្រណាំង រាត្រីកាល (Midnight Drift Racing)',
                defaultTitle: 'រាត្រីរថយន្តហោះហើរ (Tokyo Drift)',
                lyricsKhmer: [
                    "[Intro - Distorted Cowbells & Engine Revving]\n(សូរសំឡេងម៉ាស៊ីន... ផ្សែងកង់កកិតលើថ្នល់...)\n",
                    "[Verse 1]\nរាត្រីកណ្តាលអាធ្រាត្រ ភ្លើងនេអុងចាំងផ្លេកបន្ទោរ\nសំឡេងកង់កកិតថ្នល់ បត់បែនតាមគំនូសកោង\nគ្មានការភ័យខ្លាច គ្មានការរាថយ\nល្បឿនជាជីវិត ឆ្ពោះទៅកាន់ជើងមេឃ\n",
                    "[Chorus]\nDrift កាត់កណ្តាលរាត្រី! សំឡេងបាសកក្រើកដី!\nបេះដូងលោតញាប់ តាមចង្វាក់ Phonk ក្តៅគគុក\nយើងជាស្តេចផ្លូវល្បឿន គ្មានអ្នកណាបញ្ឈប់បាន!\n(Bass Drop - Heavy 808 Sub-Bass Rumble)\n",
                    "[Verse 2]\nក្រឡេកមើលកញ្ចក់ក្រោយ ឃើញតែផ្សែងកង់សក្បុស\nគូប្រកួតដេញតាម តែមិនទាន់ស្រមោលយើង\nនេះជាពិភពរបស់យើង ពិភពនៃល្បឿននិងកម្លាំង\nស្រែកឱ្យអស់សំឡេង កណ្តាលរាត្រីគ្មានព្រំដែន!\n",
                    "[Outro - Echoing Exhaust & Screeching Tires]\nល្បឿន... និងសេរីភាព... (Fade Out)"
                ].join('\n')
            },
            {
                id: 'rnb_night',
                name: '៧. កាហ្វេជូរចត់ និងរាត្រីឯកា (Midnight Coffee & Chill)',
                defaultTitle: 'កាហ្វេជូរចត់ និងរាត្រីស្ងប់ស្ងាត់',
                lyricsKhmer: [
                    "[Intro - Smooth Electric Rhodes Piano & Finger Snaps]\n(កាហ្វេមួយកែវ... កណ្តាលរាត្រីស្ងាត់...)\n",
                    "[Verse 1]\nអង្គុយក្បែរបង្អួច កែវកាហ្វេក្តៅឧណ្ហៗ\nសម្លឹងមើលតំណក់ភ្លៀង គិតដល់រឿងរ៉ាវកន្លង\nក្លិនឈ្ងុយនៃកាហ្វេ លាយឡំនឹងការចងចាំ\nមនុស្សធ្លាប់ក្បែរប្រាណ ពេលនេះនៅឯណា?\n",
                    "[Chorus]\nរសជាតិជូរចត់នៃកាហ្វេ ដូចជាបេះដូងឯកា\nផឹកដើម្បីបំភ្លេច តែរឹតតែចងចាំថ្លៃថ្លា\nរាត្រីស្ងាត់ជ្រងំ មានតែភ្លេង R&B លួងលោម\nរង់ចាំថ្ងៃថ្មី មកស្រោចស្រង់ដួងចិត្ត\n",
                    "[Verse 2]\nទូរស័ព្ទស្ងាត់ច្រៀប គ្មានសារផ្ញើមកដូចមុន\nតែមិនអីទេ បេះដូងរៀនរស់នៅម្នាក់ឯង\nរាល់បទពិសោធន៍ បង្រៀនឱ្យយើងរឹងមាំ\nញញឹមទទួលយកការពិត ដើរទៅមុខបន្ត\n",
                    "[Outro - Soft Saxophone & Fading Piano]\nរាត្រីដ៏ស្ងប់ស្ងាត់... Goodnight... (Fade Out)"
                ].join('\n')
            },
            {
                id: 'lofi_peace',
                name: '៨. ទេសភាពស្រុកស្រែ លំហែអារម្មណ៍ (Peaceful Countryside)',
                defaultTitle: 'ខ្យល់បក់រំភើយវាលស្រែ',
                lyricsKhmer: [
                    "[Intro - Acoustic Fingerstyle Guitar & Birds Chirping]\n(ខ្យល់បក់រំភើយ... ក្លិនស្រូវទុំក្រអូប...)\n",
                    "[Verse 1]\nវាលស្រែខៀវស្រងាត់ លាតសន្ធឹងដល់ជើងមេឃ\nសត្វចាបហើរច្រៀង លើមែកអំពិលទុំ\nសម្រស់ធម្មជាតិ ស្រស់ថ្លាឥតកន្លែងផ្ទឹម\nរំសាយទុក្ខកង្វល់ ចាកឆ្ងាយពីភាពអ៊ូអរ\n",
                    "[Chorus]\nស្រុកស្រែកំណើតអើយ ស្រស់ស្អាតម្ល៉េះទេ\nទឹកដីមាតុភូមិ ផ្តល់ក្តីសុខគ្រប់ពេលវេលា\nអង្គុយក្រោមម្លប់ជ្រៃ ស្រូបយកខ្យល់អាកាសបរិសុទ្ធ\nនេះហើយសេចក្តីសុខពិត ក្នុងជីវិតមនុស្សយើង\n",
                    "[Verse 2]\nពេលថ្ងៃរៀបលិច ពន្លឺពណ៌មាសចាំងលើទឹកស្ទឹង\nកូនក្របីដើរត្រឡប់ ចូលក្រោលក្បែរផ្ទះ\nផ្សែងភ្លើងដាំបាយ ហុយត្រសែតលើដំបូលស្លឹក\nភាពកក់ក្តៅគ្រួសារ គ្មានអ្វីអាចទិញបាន\n",
                    "[Outro - Gentle Kloy Flute & Vinyl Crackle]\nស្រុកកំណើតដ៏កក់ក្តៅ... (Fade Out)"
                ].join('\n')
            },
            {
                id: 'hiphop_street',
                name: '៩. ក្មេងផ្លូវលំ ឆ្ពោះទៅក្ដីស្រមៃ (Street Flow & Dream)',
                defaultTitle: 'ក្មេងផ្លូវលំឆ្ពោះទៅក្ដីស្រមៃ',
                lyricsKhmer: [
                    "[Intro - Heavy 808 Beat & Trap Hi-Hats]\n(Yo! Check this out... ចេញពីបាតដៃទទេ...)\n",
                    "[Verse 1]\nកើតនៅផ្លូវលំ គ្មានទ្រព្យសម្បត្តិស្តុកស្តម្ភ\nមានតែក្តីស្រមៃ និងការតស៊ូក្នុងទ្រូង\nគេមើលងាយសម្តី ថាយើងមិនអាចធ្វើបាន\nតែការឈឺចាប់ទាំងនោះ ក្លាយជាភ្លើងដុតកម្លាំងចិត្ត\n",
                    "[Chorus]\nយើងជាក្មេងផ្លូវលំ! ឆ្ពោះទៅកាន់កំពូលតារា!\nទោះលំបាកប៉ុនណា ក៏មិនដែលបោះបង់!\nឈរលើឆាកតន្ត្រី ស្រែកប្រាប់ពិភពលោកថា\nការប្រឹងប្រែងរបស់យើង មិនឥតប្រយោជន៍ឡើយ!\n",
                    "[Verse 2]\nរាល់យប់សរសេរចម្រៀង ក្រោមពន្លឺភ្លើងចង្កៀង\nចង្វាក់បេះដូងលោត ស្របតាមចង្វាក់ Hip-Hop\nមិនត្រូវការសំណាង ត្រូវការតែញើសនិងឈាម\nបោះជំហានទៅមុខ យកពានរង្វាន់ជីវិត!\n",
                    "[Outro - Scratching Turntable & Heavy Bass Finish]\nReal talk... Never back down! (Mic Drop)"
                ].join('\n')
            },
            {
                id: 'epic_angkor',
                name: '១០. មហានគរអង្គរដ៏រុងរឿង (Angkor Legend & Heritage)',
                defaultTitle: 'មហានគរអង្គរដ៏រុងរឿង',
                lyricsKhmer: [
                    "[Intro - Epic Taiko Drums, Kong Vong & Sweeping Orchestral Strings]\n(មហានគរខ្មែរ... អរិយធម៌រុងរឿងរាប់ពាន់ឆ្នាំ...)\n",
                    "[Verse 1]\nប្រាសាទបុរាណសន្លឹម ឈរយ៉ាងអង់អាចកណ្តាលព្រៃ\nថ្មឆ្លាក់រឿងរ៉ាវ ប្រវត្តិសាស្ត្រមហស្ចារ្យ\nដូនតាខ្មែរខ្លាំងពូកែ កសាងស្នាដៃបន្សល់ទុក\nមរតកដួងព្រលឹង ស្ថិតស្ថេររាប់ពាន់ឆ្នាំ\n",
                    "[Chorus]\nអង្គរវត្តអើយ! មោទនភាពជាតិនៃយើង!\nទង់ជាតិខ្មែរបក់រវិច លើកំពូលប្រាសាទមាស\nកូនខ្មែររួបរួមគ្នា ថែរក្សាការពារទឹកដី\nឱ្យកេរ្តិ៍ឈ្មោះខ្មែរ ល្បីល្បាញពេញសកលលោក!\n",
                    "[Verse 2]\nស្នាមញញឹមបាយ័ន បង្ហាញភាពស្ងប់និងមេត្តា\nកម្លាំងសាមគ្គី នាំមកនូវជ័យជម្នះ\nឈាមជ័រអ្នកចម្បាំង ហូរនៅក្នុងខ្លួនយើង\nប្តេជ្ញាអភិវឌ្ឍជាតិ ឱ្យរុងរឿងជានិរន្តរ៍\n",
                    "[Outro - Grand Triumphant Brass Fanfare & Choral Finale]\nជយោព្រះរាជាណាចក្រកម្ពុជា! រុងរឿងជារៀងរហូត!\n(Massive Orchestral Cymbal Crash)"
                ].join('\n')
            }
        ]
    };

    // =========================================================================
    // 7. TOAST NOTIFICATION HELPER
    // =========================================================================
    function showToast(message, type = 'success') {
        let toast = document.getElementById('suno-studio-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'suno-studio-toast';
            Object.assign(toast.style, {
                position: 'fixed',
                top: '20px',
                left: '50%',
                transform: 'translateX(-50%)',
                zIndex: '2000000',
                padding: '14px 28px',
                borderRadius: '30px',
                color: '#fff',
                fontSize: '14px',
                fontWeight: '600',
                fontFamily: 'system-ui, -apple-system, sans-serif',
                boxShadow: '0 8px 30px rgba(0,0,0,0.7)',
                transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)',
                display: 'flex',
                alignItems: 'center',
                gap: '10px',
                whiteSpace: 'pre-line',
                textAlign: 'center'
            });
            document.body.appendChild(toast);
        }

        if (type === 'success') {
            toast.style.background = 'linear-gradient(135deg, #10b981, #059669)';
        } else if (type === 'warn') {
            toast.style.background = 'linear-gradient(135deg, #f59e0b, #d97706)';
        } else {
            toast.style.background = 'linear-gradient(135deg, #ef4444, #dc2626)';
        }

        toast.innerText = message;
        toast.style.opacity = '1';
        toast.style.transform = 'translateX(-50%) translateY(0)';

        clearTimeout(toast._timer);
        toast._timer = setTimeout(() => {
            toast.style.opacity = '0';
            toast.style.transform = 'translateX(-50%) translateY(-20px)';
        }, 5000);
    }

        // =========================================================================
    // 8. HIGH RELIABILITY ELEMENT LOCATOR & FILLER (Suno React & Lexical)
    // =========================================================================
    function ensureCustomMode() {
        const buttons = Array.from(document.querySelectorAll('button, [role="tab"], [role="switch"]'));
        const customSwitch = buttons.find(b => {
            const txt = (b.textContent || '').trim().toLowerCase();
            const aria = (b.getAttribute('aria-label') || '').toLowerCase();
            return txt === 'custom' || txt.includes('custom') || aria.includes('custom') || txt.includes('advanced');
        });

        if (customSwitch) {
            const isChecked = customSwitch.getAttribute('aria-selected') === 'true' ||
                              customSwitch.getAttribute('aria-checked') === 'true' || 
                              customSwitch.getAttribute('data-state') === 'checked' ||
                              customSwitch.getAttribute('data-state') === 'on' ||
                              customSwitch.classList.contains('active');
            if (!isChecked) {
                customSwitch.click();
            }
        }
    }

    function ensureInstrumentalState(isInstrumental) {
        try {
            const candidates = Array.from(document.querySelectorAll('button, [role="switch"], input[type="checkbox"], label'));
            let instSwitch = null;

            for (const el of candidates) {
                if (el.id && el.id.startsWith('suno-')) continue;
                const aria = (el.getAttribute('aria-label') || '').toLowerCase();
                const text = (el.textContent || '').trim().toLowerCase();
                const title = (el.getAttribute('title') || '').toLowerCase();
                const name = (el.getAttribute('name') || '').toLowerCase();

                if (aria === 'instrumental' || aria.includes('instrumental') ||
                    text === 'instrumental' || text.startsWith('instrumental') ||
                    title.includes('instrumental') || name.includes('instrumental')) {
                    if (el.tagName === 'LABEL') {
                        const inputInside = el.querySelector('button, [role="switch"], input[type="checkbox"]');
                        if (inputInside) {
                            instSwitch = inputInside;
                            break;
                        }
                        const forId = el.getAttribute('for');
                        if (forId) {
                            const target = document.getElementById(forId);
                            if (target) {
                                instSwitch = target;
                                break;
                            }
                        }
                    }
                    instSwitch = el.closest('button, [role="switch"]') || el;
                    break;
                }
            }

            if (!instSwitch) {
                const allSwitches = Array.from(document.querySelectorAll('button[role="switch"], button[data-state], input[type="checkbox"]'));
                for (const sw of allSwitches) {
                    if (sw.id && sw.id.startsWith('suno-')) continue;
                    const parentText = (sw.closest('div, label, section')?.textContent || '').toLowerCase();
                    if (parentText.includes('instrumental') && !parentText.includes('custom')) {
                        instSwitch = sw;
                        break;
                    }
                }
            }

            if (instSwitch) {
                const isChecked = instSwitch.getAttribute('aria-checked') === 'true' ||
                                  instSwitch.getAttribute('data-state') === 'checked' ||
                                  instSwitch.getAttribute('data-state') === 'on' ||
                                  instSwitch.checked === true ||
                                  instSwitch.classList.contains('active') ||
                                  instSwitch.classList.contains('checked');

                if (isInstrumental && !isChecked) {
                    instSwitch.click();
                    console.log('[Suno Studio] Instrumental switch toggled ON');
                } else if (!isInstrumental && isChecked) {
                    instSwitch.click();
                    console.log('[Suno Studio] Instrumental switch toggled OFF');
                }
                return true;
            }
            return false;
        } catch (e) {
            console.warn('[Suno Studio] Error ensuring instrumental state:', e);
            return false;
        }
    }

    function getVocalProfile(vocalVal) {
        const val = (vocalVal || '').toLowerCase().trim();
        const hasFemale = /\bfemale\b/i.test(val) || val.includes('ស្រី');
        const hasMale = /\bmale\b/i.test(val) || val.includes('ប្រុស');
        const isDuet = val.includes('duet') || val.includes('ឆ្លើយឆ្លង') || (hasFemale && hasMale);
        if (isDuet) {
            return {
                id: 'duet',
                name: 'ឆ្លើយឆ្លង (Duet: Male & Female)',
                tag: '[Duet: Male and Female Vocals]',
                stylePrefix: '[Duet: Male and Female Vocals], dynamic Khmer duet, alternating male and female vocalists, sweet harmonized chorus, clear dual vocal dynamics',
                lyricTag: '[Duet: Male and Female Vocals]',
                isInstrumental: false,
                promptInstruction: 'CRITICAL VOCAL DIRECTIVE: The song MUST be a DUET between Male and Female singers. "style" MUST start with "[Duet: Male and Female Vocals], dynamic Khmer duet, alternating male and female vocalists". "lyrics" MUST begin with [Duet: Male and Female Vocals] and distinguish sections like [Verse 1 - Male Vocals], [Verse 2 - Female Vocals], and [Chorus - Duet Harmony].'
            };
        }
        if (val.includes('instrumental') || val.includes('no vocals') || val.includes('ភ្លេងសុទ្ធ')) {
            return {
                id: 'instrumental',
                name: 'ភ្លេងសុទ្ធ (Instrumental)',
                tag: '[Instrumental]',
                stylePrefix: '[Instrumental], pure acoustic melodic instruments, pristine orchestration, no vocals, melodic solo lead',
                lyricTag: '[Instrumental]\n(Pure acoustic melody - No vocals)',
                isInstrumental: true,
                promptInstruction: 'CRITICAL DIRECTIVE: Pure INSTRUMENTAL music with NO VOCALS. "style" MUST start with "[Instrumental], pure acoustic melodic instruments, no vocals". "lyrics" must only contain instrumental structural cues like [Instrumental], [Main Theme], NO singing lyrics.'
            };
        }
        if (hasMale) {
            return {
                id: 'male',
                name: 'ប្រុស (Male Vocals)',
                tag: '[Male Vocals]',
                stylePrefix: '[Male Vocals], warm emotional Khmer male vocals, deep smooth masculine singer, rich resonant tone, clear vocal clarity',
                lyricTag: '[Male Vocals]',
                isInstrumental: false,
                promptInstruction: 'CRITICAL VOCAL DIRECTIVE: The singer MUST be MALE. "style" MUST start with "[Male Vocals], warm emotional Khmer male vocals, deep smooth masculine singer". "lyrics" MUST begin with [Male Vocals] and mark sections like [Verse 1 - Male Vocals], [Chorus - Male Vocals].'
            };
        }
        return {
            id: 'female',
            name: 'ស្រី (Female Vocals)',
            tag: '[Female Vocals]',
            stylePrefix: '[Female Vocals], emotional sweet Khmer female vocals, clear feminine singer, high pitch melody, angelic resonance, crystalline vocals',
            lyricTag: '[Female Vocals]',
            isInstrumental: false,
            promptInstruction: 'CRITICAL VOCAL DIRECTIVE: The singer MUST be FEMALE. "style" MUST start with "[Female Vocals], emotional sweet Khmer female vocals, clear feminine singer". "lyrics" MUST begin with [Female Vocals] and mark sections like [Verse 1 - Female Vocals], [Chorus - Female Vocals].'
        };
    }

    function enforceVocalStylePrompt(rawStyle, vocalProf) {
        if (!vocalProf) vocalProf = getVocalProfile('female');
        if (!rawStyle) return vocalProf.stylePrefix;
        let s = rawStyle.trim();
        // Strip existing bracketed tags and old vocal descriptors
        s = s.replace(/\[(?:Female|Male|Duet|Instrumental)[^\]]*\]\s*,?\s*/gi, '');
        s = s.replace(/(?:emotional|heartfelt|deep|warm|clear|sweet|soulful)?\s*(?:female|male|duet|instrumental)\s*(?:vocal|vocals|harmony|singer)?\s*,?\s*/gi, '');
        s = s.replace(/\s*,\s*,+/g, ', ').trim();
        s = s.replace(/^,\s*/, '').replace(/,\s*$/, '');
        return `${vocalProf.stylePrefix}, ${s}`.trim();
    }

    function enforceVocalLyricsTags(rawLyrics, vocalProf) {
        if (!vocalProf) vocalProf = getVocalProfile('female');
        if (vocalProf.isInstrumental) {
            return `[Instrumental]\n(Pure acoustic melody - No vocals)\n\n[Intro - Acoustic Lead]\n(Melodic traditional kloy and acoustic guitar)\n\n[Main Theme]\n(Driving emotional melodic progression)\n\n[Melodic Solo]\n(Expressive instrument solo)\n\n[Outro - Fade Out]\n(Melody fades into silence)`;
        }
        let lyrics = (rawLyrics || '').trim();
        if (!lyrics) {
            return `${vocalProf.lyricTag}\n\n[Intro]\n\n[Verse 1]\n\n[Chorus]`;
        }

        // Remove any old root vocal headers
        lyrics = lyrics.replace(/^\[(?:Female|Male|Duet|Instrumental)[^\]]*\]\s*/gi, '').trim();

        if (vocalProf.id === 'female') {
            lyrics = lyrics.replace(/\[(?:Male|Duet)[^\]]*\]\s*/gi, '');
            lyrics = lyrics.replace(/\[Verse 1(?:\s*-[^\]]*)?\]/gi, '[Verse 1 - Female Vocals]');
            lyrics = lyrics.replace(/\[Verse 2(?:\s*-[^\]]*)?\]/gi, '[Verse 2 - Female Vocals]');
            lyrics = lyrics.replace(/\[Chorus(?:\s*-[^\]]*)?\]/gi, '[Chorus - Female Vocals]');
            lyrics = lyrics.replace(/\[Bridge(?:\s*-[^\]]*)?\]/gi, '[Bridge - Female Vocals]');
            lyrics = `${vocalProf.lyricTag}\n\n${lyrics}`;
        } else if (vocalProf.id === 'male') {
            lyrics = lyrics.replace(/\[(?:Female|Duet)[^\]]*\]\s*/gi, '');
            lyrics = lyrics.replace(/\[Verse 1(?:\s*-[^\]]*)?\]/gi, '[Verse 1 - Male Vocals]');
            lyrics = lyrics.replace(/\[Verse 2(?:\s*-[^\]]*)?\]/gi, '[Verse 2 - Male Vocals]');
            lyrics = lyrics.replace(/\[Chorus(?:\s*-[^\]]*)?\]/gi, '[Chorus - Male Vocals]');
            lyrics = lyrics.replace(/\[Bridge(?:\s*-[^\]]*)?\]/gi, '[Bridge - Male Vocals]');
            lyrics = `${vocalProf.lyricTag}\n\n${lyrics}`;
        } else if (vocalProf.id === 'duet') {
            lyrics = lyrics.replace(/\[(?:Female|Male)[^\]]*\]\s*/gi, '');
            lyrics = lyrics.replace(/\[Verse 1(?:\s*-[^\]]*)?\]/gi, '[Verse 1 - Male Vocals]');
            lyrics = lyrics.replace(/\[Verse 2(?:\s*-[^\]]*)?\]/gi, '[Verse 2 - Female Vocals]');
            lyrics = lyrics.replace(/\[Chorus(?:\s*-[^\]]*)?\]/gi, '[Chorus - Duet Harmony]');
            lyrics = lyrics.replace(/\[Bridge(?:\s*-[^\]]*)?\]/gi, '[Bridge - Alternating Vocals]');
            lyrics = `${vocalProf.lyricTag}\n\n${lyrics}`;
        }
        return lyrics;
    }

    function getSunoLyricsElement() {
        // EXACT match: Suno's Meta Lexical rich-text editor for lyrics
        return document.querySelector('div[aria-label="Lyrics editor"]')
            || document.querySelector('div[data-lexical-editor="true"]')
            || document.querySelector('.lyrics-editor-content')
            || document.querySelector('[role="textbox"][aria-label*="Lyrics" i]')
            || document.querySelector('div[aria-describedby*="lyrics"]')
            || Array.from(document.querySelectorAll('[contenteditable="true"]')).find(el => !el.id.startsWith('suno-'));
    }

    function getSunoStylesElement() {
        // EXACT match: Suno's Styles textarea
        return document.querySelector('textarea[aria-label="Styles"]')
            || document.querySelector('textarea[placeholder*="dangdut" i]')
            || document.querySelector('textarea[placeholder*="violin" i]')
            || document.querySelector('textarea[placeholder*="piano" i]')
            || document.querySelector('textarea[placeholder*="acoustic" i]')
            || document.querySelector('textarea[aria-label*="Style" i]')
            || Array.from(document.querySelectorAll('textarea')).find(ta => {
                if (ta.id.startsWith('suno-')) return false;
                const aria = (ta.getAttribute('aria-label') || '').toLowerCase();
                const ph = (ta.placeholder || '').toLowerCase();
                return aria.includes('style') || ph.includes('style') || ph.includes('genre') || ph.includes('bpm');
            });
    }

    function getSunoTitleElement() {
        // EXACT match: Suno's Song Title input
        return document.querySelector('input[placeholder="Song Title (Optional)"]')
            || document.querySelector('input[placeholder*="Title" i]')
            || document.querySelector('input[aria-label*="Title" i]')
            || Array.from(document.querySelectorAll('input')).find(inp => {
                if (inp.id.startsWith('suno-')) return false;
                const ph = (inp.placeholder || '').toLowerCase();
                const aria = (inp.getAttribute('aria-label') || '').toLowerCase();
                return ph.includes('title') || aria.includes('title');
            });
    }

    function highlightElement(el) {
        if (!el) return;
        try {
            const origBorder = el.style.border;
            const origBoxShadow = el.style.boxShadow;
            el.style.border = '2px solid #10b981';
            el.style.boxShadow = '0 0 16px rgba(16, 185, 129, 0.85)';
            setTimeout(() => {
                el.style.border = origBorder;
                el.style.boxShadow = origBoxShadow;
            }, 2500);
        } catch (e) { }
    }

    function cleanDuplicateLyrics(text) {
        if (!text || typeof text !== 'string') return '';
        let str = text.trim();

        // 1. Detect if root vocal tag (e.g. [Female Vocals], [Male Vocals], [Duet], [Instrumental]) appears more than once
        const rootMatches = [...str.matchAll(/\[(?:Female|Male|Duet|Instrumental)[^\]]*\]/gi)];
        if (rootMatches.length > 1) {
            const secondRoot = rootMatches[1];
            if (secondRoot.index > 50) {
                console.log('[Suno Studio] Deduplication: Trimming duplicate root song at index', secondRoot.index);
                str = str.substring(0, secondRoot.index).trim();
            }
        }

        // 2. Detect if [Intro ...] appears multiple times
        const introMatches = [...str.matchAll(/\[Intro[^\]]*\]/gi)];
        if (introMatches.length > 1 && introMatches[1].index > 50) {
            console.log('[Suno Studio] Deduplication: Trimming duplicate [Intro] at index', introMatches[1].index);
            str = str.substring(0, introMatches[1].index).trim();
        }

        // 3. Detect if [Verse 1 ...] appears multiple times
        const verse1Matches = [...str.matchAll(/\[Verse 1[^\]]*\]/gi)];
        if (verse1Matches.length > 1 && verse1Matches[1].index > 50) {
            console.log('[Suno Studio] Deduplication: Trimming duplicate [Verse 1] at index', verse1Matches[1].index);
            str = str.substring(0, verse1Matches[1].index).trim();
        }

        // 4. Detect identical repeating halves
        const len = str.length;
        if (len > 100) {
            const half = Math.floor(len / 2);
            for (let delta = -40; delta <= 40; delta++) {
                const splitPos = half + delta;
                if (splitPos > 30 && splitPos < len - 30) {
                    const part1 = str.substring(0, splitPos).trim();
                    const part2 = str.substring(splitPos).trim();
                    if (part1 === part2 || (part1.length > 80 && part2.startsWith(part1.substring(0, 80)))) {
                        console.log('[Suno Studio] Deduplication: Detected repeating song halves, keeping only first copy.');
                        str = part1;
                        break;
                    }
                }
            }
        }

        // 5. Detect if the first meaningful line of lyrics repeats later in the text
        const meaningfulLines = str.split('\n').map(l => l.trim()).filter(l => l.length > 12 && !/^\[/i.test(l));
        if (meaningfulLines.length > 0) {
            const firstMeaningfulLine = meaningfulLines[0];
            const secondPos = str.indexOf(firstMeaningfulLine, firstMeaningfulLine.length + 30);
            if (secondPos > 60) {
                let cutPos = secondPos;
                const prevBracket = str.lastIndexOf('[', secondPos);
                if (prevBracket !== -1 && secondPos - prevBracket < 80) {
                    cutPos = prevBracket;
                }
                console.log('[Suno Studio] Deduplication: First line repeats at index', cutPos);
                str = str.substring(0, cutPos).trim();
            }
        }

        return str;
    }

    function setLexicalValue(el, val) {
        if (!el) return false;
        try {
            val = cleanDuplicateLyrics(val);

            // 1. Thoroughly wipe all existing text & paragraph nodes
            el.focus();
            try {
                const sel = window.getSelection();
                const range = document.createRange();
                range.selectNodeContents(el);
                sel.removeAllRanges();
                sel.addRange(range);
            } catch (e) { }

            try {
                el.dispatchEvent(new InputEvent('beforeinput', {
                    bubbles: true,
                    cancelable: true,
                    inputType: 'deleteContentBackward'
                }));
            } catch (e) { }

            try {
                document.execCommand('selectAll', false, null);
                document.execCommand('delete', false, null);
            } catch (e) { }

            // Physically reset paragraphs so no old text can survive
            try {
                const paragraphs = el.querySelectorAll('p, div.lyrics-paragraph, div[class*="paragraph"]');
                if (paragraphs.length > 1) {
                    for (let i = 1; i < paragraphs.length; i++) paragraphs[i].remove();
                }
                if (paragraphs.length > 0) {
                    paragraphs[0].innerHTML = '<br>';
                } else {
                    el.innerHTML = '<p class="lyrics-paragraph"><br></p>';
                }
            } catch (e) { }

            if (!val || val.trim().length === 0) {
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                return true;
            }

            // 2. Select the clean empty container
            el.focus();
            const sel = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(el);
            sel.removeAllRanges();
            sel.addRange(range);

            // 3. Dispatch DataTransfer paste event (Meta Lexical's native multiline handler)
            let handledByPaste = false;
            try {
                const dt = new DataTransfer();
                dt.setData('text/plain', val);
                const pasteEvt = new ClipboardEvent('paste', {
                    bubbles: true,
                    cancelable: true,
                    clipboardData: dt
                });
                el.dispatchEvent(pasteEvt);
                // When Lexical handles paste, it calls preventDefault()
                if (pasteEvt.defaultPrevented) {
                    handledByPaste = true;
                }
            } catch (e) {
                console.warn('[Suno Studio] Paste dispatch error:', e);
            }

            // 4. Fallback ONLY if paste was completely unhandled (never defaultPrevented)
            // NEVER execute this if handledByPaste is true to prevent double insertion!
            if (!handledByPaste) {
                try {
                    range.selectNodeContents(el);
                    sel.removeAllRanges();
                    sel.addRange(range);
                    document.execCommand('insertText', false, val);
                } catch (e) { }
            }

            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));

            // 5. Post-check verification (80ms): ensure Lexical DOM has strictly 1 single song
            setTimeout(() => {
                try {
                    const current = (el.innerText || el.textContent || '').trim();
                    const cleaned = cleanDuplicateLyrics(current);
                    if (cleaned && cleaned.length < current.length) {
                        console.log('[Suno Studio] Post-check cleaned duplicate lyrics in editor.');
                        const paragraphs = el.querySelectorAll('p, div.lyrics-paragraph, div[class*="paragraph"]');
                        if (paragraphs.length > 1) {
                            for (let i = 1; i < paragraphs.length; i++) paragraphs[i].remove();
                        }
                        if (paragraphs.length > 0) paragraphs[0].innerHTML = '<br>';
                        
                        const dt2 = new DataTransfer();
                        dt2.setData('text/plain', cleaned);
                        el.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: dt2 }));
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                    }
                } catch (e) {}
            }, 80);

            highlightElement(el);
            return true;
        } catch (e) {
            console.error('[Suno Studio] Error setting Lexical lyrics:', e);
            return false;
        }
    }

    function setInputElementValue(el, val) {
        if (!el) return false;
        try {
            el.focus();

            const proto = Object.getPrototypeOf(el);
            const desc = Object.getOwnPropertyDescriptor(proto, 'value')
                || (el instanceof HTMLTextAreaElement ? Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value') : null)
                || (el instanceof HTMLInputElement ? Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value') : null);

            if (desc && desc.set) {
                desc.set.call(el, val);
            } else {
                el.value = val;
            }

            try {
                if (el.select) el.select();
                document.execCommand('selectAll', false, null);
                document.execCommand('insertText', false, val);
            } catch { }

            el.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
            el.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
            el.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
            el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
            el.dispatchEvent(new Event('blur', { bubbles: true }));

            highlightElement(el);
            return true;
        } catch (e) {
            console.error('[Suno Studio] Error setting input value:', e);
            return false;
        }
    }

    function setElementValue(el, val) {
        if (!el) return false;
        const isLexical = el.getAttribute('data-lexical-editor') === 'true' ||
                          el.getAttribute('contenteditable') === 'true' ||
                          el.getAttribute('aria-label') === 'Lyrics editor' ||
                          (el.tagName === 'DIV' && el.getAttribute('role') === 'textbox');
        if (isLexical) {
            return setLexicalValue(el, val);
        }
        return setInputElementValue(el, val);
    }

    function fillSingleField(field) {
        ensureCustomMode();
        if (field === 'lyrics') {
            const rawLyrics = document.getElementById('suno-lyrics-output')?.value || '';
            const lyrics = cleanDuplicateLyrics(rawLyrics);
            const el = getSunoLyricsElement();
            if (el && setElementValue(el, lyrics)) {
                showToast('✓ បានបញ្ចូលចំប្រអប់ 📝 Lyrics (Lyrics editor) ត្រឹមត្រូវ!', 'success');
                return true;
            } else {
                showToast('⚠️ រកមិនឃើញប្រអប់ Lyrics editor!', 'warn');
                return false;
            }
        } else if (field === 'style') {
            const style = document.getElementById('suno-style-output')?.value || '';
            const el = getSunoStylesElement();
            if (el && setElementValue(el, style)) {
                showToast('✓ បានបញ្ចូលចំប្រអប់ 🎼 Styles (Style of Music) ត្រឹមត្រូវ!', 'success');
                return true;
            } else {
                showToast('⚠️ រកមិនឃើញប្រអប់ Styles!', 'warn');
                return false;
            }
        } else if (field === 'title') {
            const title = document.getElementById('suno-title-output')?.value || '';
            const el = getSunoTitleElement();
            if (el && setElementValue(el, title)) {
                showToast('✓ បានបញ្ចូលចំប្រអប់ 🏷️ Song Title (Optional) ត្រឹមត្រូវ!', 'success');
                return true;
            } else {
                showToast('⚠️ រកមិនឃើញប្រអប់ Song Title (Optional)!', 'warn');
                return false;
            }
        }
        return false;
    }

    function mapAndFillSunoFields(lyrics, style, title, retryCount = 0) {
        // If not on create page, auto navigate to /create
        if (typeof window !== 'undefined' && window.location && !window.location.pathname.includes('/create')) {
            const createNav = Array.from(document.querySelectorAll('a, button')).find(el => {
                const href = el.getAttribute('href') || '';
                const txt = (el.textContent || '').trim().toLowerCase();
                return href.includes('/create') || txt === 'create' || txt.includes('create');
            });
            if (createNav) {
                createNav.click();
                setTimeout(() => {
                    mapAndFillSunoFields(lyrics, style, title, retryCount + 1);
                }, 1000);
                return;
            } else {
                window.location.href = 'https://suno.com/create';
                return;
            }
        }

        ensureCustomMode();

        // Enforce Suno's native Instrumental switch based on selected vocal profile
        const vocalEl = document.getElementById('suno-vocal-select');
        const vocalVal = vocalEl ? vocalEl.value : (localStorage.getItem('suno_vocal_choice') || 'female');
        const vocalProf = getVocalProfile(vocalVal);
        ensureInstrumentalState(vocalProf.isInstrumental);

        const lyricsEl = getSunoLyricsElement();
        const styleEl = getSunoStylesElement();
        const titleEl = getSunoTitleElement();

        // If elements are not yet mounted (e.g. still toggling Custom mode), retry after short delay
        if (((!vocalProf.isInstrumental && !lyricsEl) || !styleEl || !titleEl) && retryCount < 3) {
            setTimeout(() => {
                mapAndFillSunoFields(lyrics, style, title, retryCount + 1);
            }, 350);
            return;
        }

        console.log('[Suno Studio] Target elements:', {
            vocalProfile: vocalProf.name,
            isInstrumental: vocalProf.isInstrumental,
            lyricsEl: lyricsEl ? `${lyricsEl.tagName}[aria-label="${lyricsEl.getAttribute('aria-label')}"]` : null,
            styleEl: styleEl ? `${styleEl.tagName}[aria-label="${styleEl.getAttribute('aria-label')}"]` : null,
            titleEl: titleEl ? `${titleEl.tagName}[placeholder="${titleEl.getAttribute('placeholder')}"]` : null
        });

        let successLyrics = false;
        let successStyle = false;
        let successTitle = false;

        const singleLyrics = cleanDuplicateLyrics(lyrics || '');

        // Strictly fill each into its dedicated box (with deduplication check to prevent layered/duplicate text)
        if (!vocalProf.isInstrumental && lyricsEl && singleLyrics) {
            const existingLyrics = cleanDuplicateLyrics((lyricsEl.innerText || lyricsEl.textContent || '').trim());
            if (existingLyrics !== singleLyrics.trim()) {
                successLyrics = setElementValue(lyricsEl, singleLyrics);
            } else {
                console.log('[Suno Studio] Lyrics already up to date, skipping redundant insertion.');
                successLyrics = true;
            }
        } else if (vocalProf.isInstrumental) {
            successLyrics = true; // Instrumental mode does not require lyrics
        }
        if (styleEl && style) {
            const existingStyle = (styleEl.value || '').trim();
            if (existingStyle !== style.trim()) {
                successStyle = setElementValue(styleEl, style);
            } else {
                console.log('[Suno Studio] Styles already up to date, skipping redundant insertion.');
                successStyle = true;
            }
        }
        if (titleEl && title) {
            const existingTitle = (titleEl.value || '').trim();
            if (existingTitle !== title.trim()) {
                successTitle = setElementValue(titleEl, title);
            } else {
                console.log('[Suno Studio] Title already up to date, skipping redundant insertion.');
                successTitle = true;
            }
        }

        try { navigator.clipboard.writeText(singleLyrics); } catch { }

        const filledParts = [];
        if (successLyrics) filledParts.push('📝 Lyrics ➔ ប្រអប់ Lyrics');
        if (successStyle) filledParts.push('🎼 Styles ➔ ប្រអប់ Styles');
        if (successTitle) filledParts.push('🏷️ Title ➔ ប្រអប់ Song Title');

        if (filledParts.length > 0) {
            try {
                if (typeof applySavedSongDuration === 'function') {
                    applySavedSongDuration();
                }
            } catch (e) { }
            showToast(`✓ បានបញ្ចូលចំប្រអប់នីមួយៗត្រឹមត្រូវ ១០០%៖\n${filledParts.join('\n')}`, 'success');
            return true;
        } else {
            showToast('⚠️ រកមិនឃើញប្រអប់បញ្ចូលរបស់ Suno។ សូមប្រាកដថាបានបើកមុខងារ Custom / Advanced!', 'warn');
            return false;
        }
    }

    // =========================================================================
    // 8.4 AUTO-LOOP PRODUCER SUITE (6-STEP CYCLIC CREATOR & TODAY MONITOR)
    // =========================================================================

    const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

    // Dedicated Immediate Lyrics Clear (Meta Lexical Multi-Strategy Clear)
    function clearSunoLyricsOnly(isSilent = false) {
        console.log('[Suno Studio] Clearing Suno Lyrics editor immediately...');
        ensureCustomMode();
        let cleared = false;
        const lyricsEl = getSunoLyricsElement();
        if (lyricsEl) {
            try {
                lyricsEl.focus();
                
                // 1. Select all contents in Lexical container
                const sel = window.getSelection();
                const range = document.createRange();
                range.selectNodeContents(lyricsEl);
                sel.removeAllRanges();
                sel.addRange(range);

                // 2. Dispatch beforeinput deleteContentBackward
                try {
                    const delEvt = new InputEvent('beforeinput', {
                        bubbles: true,
                        cancelable: true,
                        inputType: 'deleteContentBackward'
                    });
                    lyricsEl.dispatchEvent(delEvt);
                } catch (e) {}

                // 3. ExecCommand delete
                try {
                    document.execCommand('selectAll', false, null);
                    document.execCommand('delete', false, null);
                } catch (e) {}

                // 4. Dispatch paste empty text
                try {
                    const dt = new DataTransfer();
                    dt.setData('text/plain', '');
                    const pasteEvt = new ClipboardEvent('paste', {
                        bubbles: true,
                        cancelable: true,
                        clipboardData: dt
                    });
                    lyricsEl.dispatchEvent(pasteEvt);
                } catch (e) {}

                // 5. Reset DOM paragraph structure for Lexical
                try {
                    const paragraphs = lyricsEl.querySelectorAll('p');
                    if (paragraphs.length > 1) {
                        for (let i = 1; i < paragraphs.length; i++) paragraphs[i].remove();
                    }
                    if (paragraphs.length > 0) {
                        paragraphs[0].innerHTML = '<br>';
                    } else {
                        lyricsEl.innerHTML = '<p class="editor-paragraph"><br></p>';
                    }
                } catch (e) {}

                // 6. Dispatch events
                lyricsEl.dispatchEvent(new Event('input', { bubbles: true }));
                lyricsEl.dispatchEvent(new Event('change', { bubbles: true }));
                lyricsEl.dispatchEvent(new KeyboardEvent('keydown', { key: 'Backspace', keyCode: 8, bubbles: true }));
                lyricsEl.dispatchEvent(new KeyboardEvent('keyup', { key: 'Backspace', keyCode: 8, bubbles: true }));
                lyricsEl.dispatchEvent(new Event('blur', { bubbles: true }));

                highlightElement(lyricsEl);
                cleared = true;
            } catch (e) {
                console.error('[Suno Studio] Error clearing Lexical lyrics:', e);
            }
        }

        // Clear Studio internal lyrics output
        const lOut = document.getElementById('suno-lyrics-output');
        if (lOut) {
            lOut.value = '';
            cleared = true;
        }

        if (!isSilent) {
            if (cleared) {
                showToast('🗑️ បានលុបសម្អាតប្រអប់ 📝 Lyrics (Lyrics editor) ភ្លាមៗរួចរាល់!', 'success');
            } else {
                showToast('⚠️ រកមិនឃើញប្រអប់ Lyrics editor ដើម្បីលុបសម្អាត!', 'warn');
            }
        }
        return cleared;
    }

    // Step 4: Clear all Suno inputs (Lyrics, Styles, Song Title)
    function clearAllSunoFields(isAutoLoop = false) {
        console.log('[Suno Studio] Clearing all Suno fields... (isAutoLoop:', isAutoLoop, ')');
        // 1. Native clear button if present (only when clicked manually to avoid modal dialog race conditions during loop)
        if (!isAutoLoop) {
            const nativeClearBtn = document.querySelector('button[aria-label="Clear all form inputs"]') ||
                                   Array.from(document.querySelectorAll('button')).find(b => (b.getAttribute('aria-label') || '').includes('Clear all'));
            if (nativeClearBtn) {
                try {
                    nativeClearBtn.click();
                    setTimeout(() => {
                        const confirmBtn = Array.from(document.querySelectorAll('button, [role="button"]')).find(b => {
                            const txt = (b.textContent || '').trim().toLowerCase();
                            return txt === 'confirm' || txt.includes('confirm');
                        });
                        if (confirmBtn) confirmBtn.click();
                    }, 120);
                } catch(e){}
            }
        }

        // 2. Clear Styles textarea
        const styleEl = getSunoStylesElement();
        if (styleEl) {
            setElementValue(styleEl, '');
        }

        // 3. Clear Title input
        const titleEl = getSunoTitleElement();
        if (titleEl) {
            setElementValue(titleEl, '');
        }

        // 4. Clear Lexical Lyrics editor immediately using specialized clearer
        clearSunoLyricsOnly(true);

        // 5. Clear Studio internal outputs
        const tOut = document.getElementById('suno-title-output');
        if (tOut) tOut.value = '';
        const sOut = document.getElementById('suno-style-output');
        if (sOut) sOut.value = '';
        const lOut = document.getElementById('suno-lyrics-output');
        if (lOut) lOut.value = '';

        if (!isAutoLoop) {
            showToast('🗑️ បានលុបសម្អាត Lyrics + Styles + Song Title រួចរាល់!', 'info');
        }
        return true;
    }

    // Suno AI Model Selector & Activator (v6-wild Pro, v6 Pro, v6-mini)
    async function switchSunoModel(targetModel = 'v6-wild') {
        try {
            console.log(`[Suno Studio] Attempting to switch Suno AI model to: ${targetModel}...`);

            // 1. Locate Suno's active model button
            const buttons = Array.from(document.querySelectorAll('button'));
            const modelBtn = buttons.find(b => {
                if (b.id && b.id.startsWith('suno-')) return false;
                const txt = (b.textContent || '').trim().toLowerCase();
                return (txt.includes('v6-mini') || txt.includes('v6-wild') || txt.includes('v6 pro') || (txt.startsWith('v6') && !txt.includes('create'))) &&
                       !txt.includes('composer') && !txt.includes('lyrics');
            }) || buttons.find(b => {
                if (b.id && b.id.startsWith('suno-')) return false;
                const aria = (b.getAttribute('aria-label') || '').toLowerCase();
                return aria.includes('model') || aria.includes('version');
            });

            if (!modelBtn) {
                console.warn('[Suno Studio] Suno Model selector button not found.');
                showToast('⚠️ រកមិនឃើញប៊ូតុង Model របស់ Suno (សូមប្រាកដថានៅលើទំព័រ /create)!', 'warn');
                return false;
            }

            const currentActive = (modelBtn.textContent || '').trim();
            console.log(`[Suno Studio] Found Suno model button. Current active: "${currentActive}"`);

            const badge = document.getElementById('suno-current-model-badge');
            if (badge) badge.innerText = currentActive;

            // If already on target
            if (currentActive.toLowerCase().includes(targetModel.toLowerCase().replace('-', ' '))) {
                showToast(`✓ Suno កំពុងប្រើប្រាស់ ${currentActive} រួចជាស្រេច!`, 'success');
                return true;
            }

            // 2. Click model dropdown button to open popover
            modelBtn.click();
            await new Promise(r => setTimeout(r, 450));

            // 3. Find target option in popover dialog
            const candidates = Array.from(document.querySelectorAll('[role="dialog"] button, [role="menuitem"], [role="option"], [data-radix-collection-item], [role="dialog"] div[role="button"], [role="dialog"] [tabindex="0"]'));
            
            const targetOption = candidates.find(el => {
                if (el.id && el.id.startsWith('suno-')) return false;
                const txt = (el.textContent || '').toLowerCase();
                if (targetModel.includes('wild')) {
                    return txt.includes('v6-wild') || (txt.includes('v6') && txt.includes('wild'));
                } else if (targetModel.includes('pro')) {
                    return (txt.includes('v6 pro') || (txt.includes('v6') && txt.includes('pro'))) && !txt.includes('wild');
                } else if (targetModel.includes('mini')) {
                    return txt.includes('v6-mini') || txt.includes('mini');
                }
                return txt.includes(targetModel.toLowerCase());
            });

            if (!targetOption) {
                console.warn('[Suno Studio] Target model option not found in popover.');
                document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
                showToast(`⚠️ រកមិនឃើញជម្រើស "${targetModel}" ក្នុងបញ្ជី Model របស់ Suno!`, 'warn');
                return false;
            }

            console.log('[Suno Studio] Clicking model option:', targetOption.textContent.trim());
            targetOption.click();
            await new Promise(r => setTimeout(r, 600));

            // 4. Check if Suno displayed the Subscription Upgrade Paywall modal
            const upgradeModal = Array.from(document.querySelectorAll('div, [role="dialog"]')).find(d => {
                if (d.id && d.id.startsWith('suno-')) return false;
                const txt = (d.textContent || '').toLowerCase();
                return txt.includes('unlock our best models') || (txt.includes('available with pro and premier') && txt.includes('subscribe'));
            });

            if (upgradeModal) {
                console.log('[Suno Studio] Upgrade modal detected. Current account requires Pro/Premier subscription.');
                // Dismiss modal
                const closeBtn = upgradeModal.querySelector('button[aria-label*="close" i], button[aria-label*="Close" i], button svg');
                if (closeBtn) closeBtn.closest('button')?.click();
                document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));

                showToast('⚠️ គណនីរបស់អ្នកជាគណនី Free! Suno តម្រូវឱ្យមានគម្រោង Pro ឬ Premier ($8/ខែ) ដើម្បីប្រើ v6-wild Pro។ Suno បានរក្សាទុក v6-mini!', 'warn');
                if (badge) badge.innerText = 'v6-mini';
                return false;
            }

            const newActive = (modelBtn.textContent || '').trim();
            if (badge) badge.innerText = newActive;
            localStorage.setItem('suno_active_model', newActive);
            showToast(`✓ បានបើកដំណើរការ Suno ${newActive} ដោយជោគជ័យ!`, 'success');
            return true;
        } catch (err) {
            console.error('[Suno Studio] Error in switchSunoModel:', err);
            showToast('⚠️ បញ្ហាក្នុងការប្តូរ Model Suno៖ ' + err.message, 'error');
            return false;
        }
    }

    function updateSunoModelBadge() {
        try {
            const buttons = Array.from(document.querySelectorAll('button'));
            const modelBtn = buttons.find(b => {
                if (b.id && b.id.startsWith('suno-')) return false;
                const txt = (b.textContent || '').trim().toLowerCase();
                return (txt.includes('v6-mini') || txt.includes('v6-wild') || txt.includes('v6 pro') || (txt.startsWith('v6') && !txt.includes('create'))) &&
                       !txt.includes('composer') && !txt.includes('lyrics');
            });
            if (modelBtn) {
                const badge = document.getElementById('suno-current-model-badge');
                if (badge) badge.innerText = (modelBtn.textContent || '').trim();
            }
        } catch (e) { }
    }

    // =========================================================================
    // 5.5 SUNO SONG DURATION CONTROLLER (កំណត់នាទីចម្រៀង)
    // =========================================================================
    function parseDurationToSeconds(val) {
        if (!val || val === 'auto' || val === 'Auto' || val === 0) return 'auto';
        if (typeof val === 'number') return Math.max(10, Math.min(360, Math.round(val)));
        const s = String(val).trim().toLowerCase();
        if (s === 'auto') return 'auto';

        const mmssMatch = s.match(/^(\d+):(\d{1,2})$/);
        if (mmssMatch) {
            const m = parseInt(mmssMatch[1], 10);
            const sec = parseInt(mmssMatch[2], 10);
            return Math.max(10, Math.min(360, m * 60 + sec));
        }

        const minMatch = s.match(/^(\d+(?:\.\d+)?)\s*(?:m|min|នាទី)?$/i);
        if (minMatch) {
            const num = parseFloat(minMatch[1]);
            if (num <= 6) {
                return Math.max(10, Math.min(360, Math.round(num * 60)));
            }
            return Math.max(10, Math.min(360, Math.round(num)));
        }

        return 180;
    }

    function formatSecondsToDurationString(seconds) {
        if (seconds === 'auto' || !seconds) return 'Auto';
        const mm = Math.floor(seconds / 60);
        const ss = String(seconds % 60).padStart(2, '0');
        return `${mm}:${ss}`;
    }

    async function setSunoSongDuration(targetVal = 240) {
        const sec = parseDurationToSeconds(targetVal);

        if (sec === 'auto') {
            return resetSunoSongDurationToAuto();
        }

        try {
            // 1. Ensure "Advanced" / "More Options" is expanded in Suno
            const moreOptionsBtn = Array.from(document.querySelectorAll('button, div[role="button"]')).find(b => {
                const txt = (b.textContent || '').trim().toLowerCase();
                return txt.includes('more options') || txt.includes('advanced');
            });
            if (moreOptionsBtn && moreOptionsBtn.getAttribute('aria-expanded') === 'false') {
                moreOptionsBtn.click();
                await sleep(150);
            }

            // 2. Ensure Duration is switched to Custom mode
            let slider = document.querySelector('div[role="slider"][aria-label="Duration"]');
            if (!slider) {
                const customBtn = Array.from(document.querySelectorAll('button')).find(
                    b => b.textContent?.trim() === 'Custom' && b.closest('div')?.textContent?.includes('Duration')
                );
                if (customBtn) {
                    customBtn.click();
                    await sleep(150);
                }
            }

            const timeStr = formatSecondsToDurationString(sec);

            // 3. Locate Duration time input
            const timeInput = document.querySelector('input[inputmode="decimal"][aria-label="Duration"]')
                || document.querySelector('div[role="slider"][aria-label="Duration"] ~ input[type="text"]')
                || document.querySelector('input[aria-label="Duration"]');

            if (timeInput) {
                timeInput.focus();
                const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
                if (nativeSetter) {
                    nativeSetter.call(timeInput, timeStr);
                } else {
                    timeInput.value = timeStr;
                }
                timeInput.dispatchEvent(new Event('input', { bubbles: true }));
                timeInput.dispatchEvent(new Event('change', { bubbles: true }));
                timeInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
                timeInput.dispatchEvent(new Event('blur', { bubbles: true }));
            }

            localStorage.setItem('suno_song_duration_pref', String(sec));
            updateSunoDurationUI(sec);
            showToast(`⏱️ បានកំណត់នាទីចម្រៀងត្រឹម ${timeStr} នាទី (${sec} វិនាទី) ជោគជ័យ!`, 'success');
            return true;
        } catch (err) {
            console.error('[Suno Studio] Error setting song duration:', err);
            showToast('⚠️ បញ្ហាក្នុងការកំណត់នាទីចម្រៀង៖ ' + err.message, 'error');
            return false;
        }
    }

    function resetSunoSongDurationToAuto() {
        try {
            const resetIcon = document.querySelector('div.css-1c1smtn svg.cursor-pointer, svg[class*="cursor-pointer"], button[aria-label="Reset duration"]');
            if (resetIcon) {
                resetIcon.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
            } else {
                const autoBtn = Array.from(document.querySelectorAll('button')).find(
                    b => b.textContent?.trim() === 'Auto' && b.closest('div')?.textContent?.includes('Duration')
                );
                if (autoBtn) autoBtn.click();
            }

            localStorage.setItem('suno_song_duration_pref', 'auto');
            updateSunoDurationUI('auto');
            showToast('⚡ បានប្តូរនាទីចម្រៀងមកជា Auto ស្វ័យប្រវត្តិតាម Suno វិញ!', 'info');
            return true;
        } catch (err) {
            console.warn('[Suno Studio] Error resetting duration to auto:', err);
            return false;
        }
    }

    function getSunoCurrentDuration() {
        const slider = document.querySelector('div[role="slider"][aria-label="Duration"]');
        if (slider) {
            const val = slider.getAttribute('aria-valuenow');
            if (val) return formatSecondsToDurationString(parseInt(val, 10));
        }
        const timeInput = document.querySelector('input[inputmode="decimal"][aria-label="Duration"]');
        if (timeInput && timeInput.value) return timeInput.value;

        const autoBtn = Array.from(document.querySelectorAll('button')).find(
            b => b.textContent?.trim() === 'Auto' && b.closest('div')?.textContent?.includes('Duration')
        );
        if (autoBtn && autoBtn.getAttribute('aria-selected') === 'true') return 'Auto';

        const saved = localStorage.getItem('suno_song_duration_pref');
        if (saved && saved !== 'auto') return formatSecondsToDurationString(parseInt(saved, 10));
        return 'Auto';
    }

    function updateSunoDurationUI(currentSec) {
        const dur = (currentSec !== undefined)
            ? (currentSec === 'auto' ? 'Auto' : formatSecondsToDurationString(currentSec))
            : getSunoCurrentDuration();

        const badgeText = dur === 'Auto' ? '⚡ Auto' : `⏱️ ${dur}`;

        const badges = [
            document.getElementById('suno-current-duration-badge'),
            document.getElementById('suno-drawer-duration-badge')
        ];
        badges.forEach(b => {
            if (b) {
                b.innerText = badgeText;
                b.style.color = dur === 'Auto' ? '#a5b4fc' : '#f472b6';
                b.style.borderColor = dur === 'Auto' ? 'rgba(165,180,252,0.3)' : 'rgba(244,114,182,0.4)';
            }
        });

        const slider = document.getElementById('suno-dur-slider');
        const display = document.getElementById('suno-dur-display');
        if (slider && display && typeof currentSec === 'number') {
            slider.value = currentSec;
            display.innerText = formatSecondsToDurationString(currentSec);
        }
    }

    function applySavedSongDuration() {
        const saved = localStorage.getItem('suno_song_duration_pref');
        if (saved && saved !== 'auto') {
            const sec = parseInt(saved, 10);
            if (!isNaN(sec) && sec >= 10 && sec <= 360) {
                setSunoSongDuration(sec);
            }
        }
    }

    // Step 5: Scan & Analyze Suno's Create button and Cooldown/Limits
    function analyzeSunoCreateButton() {
        const createBtn = document.querySelector('button[aria-label="Create song"]') ||
                          Array.from(document.querySelectorAll('button')).find(b => {
                              const aria = (b.getAttribute('aria-label') || '').toLowerCase();
                              const txt = (b.textContent || '').trim().toLowerCase();
                              return (aria.includes('create song') || txt.startsWith('create')) && !b.id.startsWith('suno-');
                          });

        if (!createBtn) {
            return {
                found: false,
                canCreate: false,
                isRateLimited: false,
                isOutOfCredits: false,
                isFormEmpty: false,
                reason: 'រកមិនឃើញប៊ូតុង Create (សូមចូលទៅកាន់ទំព័រ /create)',
                cooldownMinutes: 0,
                cooldownSeconds: 0,
                credits: null
            };
        }

        const isDisabled = createBtn.disabled ||
                           createBtn.hasAttribute('disabled') ||
                           createBtn.getAttribute('aria-disabled') === 'true' ||
                           createBtn.getAttribute('data-disabled') === 'true' ||
                           createBtn.classList.contains('disabled');

        const btnText = (createBtn.textContent || '').trim();

        // Check DOM text for cooldown / rate limits / countdown
        const bodyText = document.body.innerText || '';
        let cooldownMinutes = 0;
        let cooldownSeconds = 0;

        const limitMatch = bodyText.match(/(?:wait|try again in|cooldown|limit reached|resets in)\s*(\d+)?\s*(minute|min|hour|hr|second|sec)/i);
        const timeMatch = bodyText.match(/(\d{1,2}):(\d{2})\s*(?:remaining|left|until)/i);

        if (limitMatch) {
            const val = parseInt(limitMatch[1] || '1', 10);
            const unit = limitMatch[2].toLowerCase();
            if (unit.startsWith('h')) cooldownMinutes = val * 60;
            else if (unit.startsWith('m')) cooldownMinutes = val;
            else if (unit.startsWith('s')) cooldownSeconds = val;
        } else if (timeMatch) {
            cooldownMinutes = parseInt(timeMatch[1], 10);
            cooldownSeconds = parseInt(timeMatch[2], 10);
        }

        let credits = null;
        const credMatch = bodyText.match(/\b(\d+)\s*(?:credits?|tokens?)\b/i);
        if (credMatch) {
            credits = parseInt(credMatch[1], 10);
        }

        const isRateLimited = (cooldownMinutes > 0 || cooldownSeconds > 0);
        const isOutOfCredits = (credits === 0);
        const isFormEmpty = isDisabled && !isRateLimited && !isOutOfCredits;

        const reason = isRateLimited 
            ? `ដល់កំណត់! ត្រូវរង់ចាំ ${cooldownMinutes}m ${cooldownSeconds}s ទៀត` 
            : (isOutOfCredits ? 'អស់ Credit សម្រាប់បង្កើតហើយ' : (isFormEmpty ? 'ប៊ូតុង Create កំពុងរង់ចាំទិន្នន័យ (Empty Form)' : '🟢 ប៊ូតុង Create រួចរាល់'));

        return {
            found: true,
            button: createBtn,
            canCreate: !isDisabled,
            isRateLimited: isRateLimited,
            isOutOfCredits: isOutOfCredits,
            isFormEmpty: isFormEmpty,
            btnText: btnText,
            credits: credits,
            cooldownMinutes: cooldownMinutes,
            cooldownSeconds: cooldownSeconds,
            reason: reason
        };
    }

    // Step 6: Scan & Analyze Suno's Today Feed (Max 4 concurrent songs)
    function analyzeSunoTodayFeed() {
        let pendingCount = 0;
        const generatingTitles = [];

        // 1. Inspect knownClips from network interceptor
        if (typeof knownClips !== 'undefined' && knownClips.size > 0) {
            knownClips.forEach(clip => {
                if (clip.status === 'submitted' || clip.status === 'queued' || clip.status === 'streaming' || clip.status === 'pending') {
                    pendingCount++;
                    if (clip.title) generatingTitles.push(clip.title);
                }
            });
        }

        // 2. Inspect DOM loading spinners in song rows
        const loadingIcons = Array.from(document.querySelectorAll('.animate-spin, .animate-pulse, [role="progressbar"], svg.animate-spin'));
        
        // 3. Inspect library cards that show text "generating" or "queued"
        const libraryCards = Array.from(document.querySelectorAll('[role="group"], [data-testid*="clip"]'));
        let domPending = 0;
        libraryCards.forEach(card => {
            const txt = (card.textContent || '').toLowerCase();
            const hasSpinner = card.querySelector('.animate-spin, .animate-pulse, [role="progressbar"]');
            if (hasSpinner || txt.includes('generating') || txt.includes('queued') || txt.includes('streaming')) {
                domPending++;
            }
        });

        const activeCount = Math.max(pendingCount, domPending, Math.min(loadingIcons.length, 4));
        const maxConcurrent = 4; // Suno limit is 4 concurrent songs (2 jobs of 2)

        return {
            activeCount: Math.min(activeCount, maxConcurrent),
            maxConcurrent: maxConcurrent,
            canQueueMore: activeCount < maxConcurrent,
            isBusy: activeCount >= maxConcurrent,
            generatingTitles: generatingTitles
        };
    }

    // Step 1: Generate Fresh Title
    async function generateFreshTitleOnly() {
        console.log('[Suno Studio] Step 1: Generating fresh Title...');
        const topicEl = document.getElementById('suno-custom-topic');
        const customTopic = topicEl ? topicEl.value.trim() : '';
        const apiKey = localStorage.getItem('gemini_api_key') || '';
        const modelChoice = localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';
        const langConfig = getSongLanguageConfig();

        let titles = [];
        if (apiKey && modelChoice !== 'smart_engine') {
            try {
                titles = await callGeminiApiForTitles(apiKey, modelChoice, customTopic, null, `Modern ${langConfig.label} Pop, Acoustic Melody`, '');
            } catch (e) {
                console.warn('[Auto-Loop] Gemini Title error, fallback to smart:', e);
            }
        }
        if (!titles || titles.length === 0) {
            if (typeof generateSmartGeminiTitles === 'function') {
                titles = generateSmartGeminiTitles(customTopic, null, `Modern ${langConfig.label} Music`, '');
            }
        }

        // Pick the first title that has never been used before
        let chosen = '';
        if (Array.isArray(titles)) {
            for (const t of titles) {
                if (typeof isTitleDuplicate === 'function' && !isTitleDuplicate(t)) {
                    chosen = t;
                    break;
                }
            }
        }
        if (!chosen && Array.isArray(titles) && titles.length > 0) {
            chosen = titles[0];
        }
        if (!chosen) {
            chosen = typeof generateSingleUniqueKhmerTitle === 'function' 
                ? generateSingleUniqueKhmerTitle(customTopic, 'មនោសញ្ចេតនា', `Modern ${langConfig.label} Pop`) 
                : (langConfig.code === 'en' ? 'Shadows in the Rain' : 'ស្រមោលស្នេហ៍កណ្តាលរាត្រី');
        }

        // Register to persistent history to guarantee zero repetition
        if (typeof recordUsedTitle === 'function') {
            recordUsedTitle(chosen);
        }

        const titleInput = document.getElementById('suno-title-output');
        if (titleInput) titleInput.value = chosen;
        if (typeof renderGeminiTitleChips === 'function') {
            try { renderGeminiTitleChips(titles, chosen); } catch(e) {}
        }

        const sunoTitleEl = getSunoTitleElement();
        if (sunoTitleEl) {
            setElementValue(sunoTitleEl, chosen);
        }
        return chosen;
    }

    const generateSmartKhmerTitles = generateSmartGeminiTitles;

    // Step 2: Full Song Composition (Title + Lyrics + Style) - Scoped globally in studio
    async function generateSong() {
        try {
            console.log('[Suno Studio] Step 2: Generating full song...');
            const themeEl = document.getElementById('suno-theme-select');
            const genreEl = document.getElementById('suno-genre-select');
            const vocalEl = document.getElementById('suno-vocal-select');
            const tempoEl = document.getElementById('suno-tempo-select');
            const topicEl = document.getElementById('suno-custom-topic');

            const themeId = themeEl ? themeEl.value : 'love_sweet';
            const genreId = genreEl ? genreEl.value : 'khmer_modern_pop';
            const vocalType = vocalEl ? vocalEl.value : (localStorage.getItem('suno_vocal_choice') || 'female');
            const vocalProf = getVocalProfile(vocalType);
            const tempo = tempoEl ? tempoEl.value : 'moderate tempo 88 bpm';
            const customTopic = topicEl ? topicEl.value.trim() : '';

            const selectedTheme = songData.themes.find(t => t.id === themeId) || songData.themes[0];
            const selectedGenre = songData.genres.find(g => g.id === genreId) || songData.genres[0];

            const genBtn = document.getElementById('suno-generate-btn');
            const genBtnTop = document.getElementById('suno-generate-btn-top');
            const dockGenBtn = document.getElementById('suno-dock-btn-gen');
            const inlineGenBtn = document.getElementById('suno-inline-gen');
            const loopComposeBtn = document.getElementById('suno-loop-btn-compose');
            const apiKey = localStorage.getItem('gemini_api_key') || '';

            const setButtonsLoading = (loading) => {
                [genBtn, genBtnTop, dockGenBtn, inlineGenBtn, loopComposeBtn].forEach(b => {
                    if (!b) return;
                    b.disabled = loading;
                    b.style.opacity = loading ? '0.7' : '1';
                });
                if (genBtn) genBtn.innerHTML = loading ? `<span>⏳</span> <span>កំពុងតែងនិពន្ធចម្រៀងថ្មី...</span>` : `<span>✨</span> <span>បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីលបទភ្លេង ឡើងវិញ</span>`;
                if (genBtnTop) genBtnTop.innerHTML = loading ? `<span>⏳</span> <span>កំពុងតែងនិពន្ធចម្រៀងថ្មី...</span>` : `<span style="font-size:16px;">✨</span> <span>បង្កើត ចំណងជើងចម្រៀង ទំនុកច្រៀង ស្ទីលបទភ្លេង</span>`;
                if (dockGenBtn) dockGenBtn.innerHTML = loading ? `<span>⏳</span> <span>កំពុងនិពន្ធ...</span>` : `<span style="font-size:14px;">✨</span> <span>បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីលបទភ្លេង</span>`;
                if (inlineGenBtn) inlineGenBtn.innerHTML = loading ? `<span>⏳</span> <span>កំពុងនិពន្ធ...</span>` : `<span>✨</span> <span>បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីលបទភ្លេង</span>`;
            };

            setButtonsLoading(true);

            let newSong = null;
            let usedApi = false;

            const modelChoice = localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';
            const modelShort = typeof getGeminiModelName === 'function' ? getGeminiModelName(modelChoice).split('(')[0].trim() : 'Gemini AI';

            if (apiKey && modelChoice !== 'smart_engine') {
                try {
                    showToast(`✨ ${modelShort} កំពុងនិពន្ធទំនុកច្រៀង (${vocalProf.name}) ភ្លេង និងចំណងជើងថ្មី...`, 'info');
                    newSong = await composeFullSongWithGemini(customTopic, selectedTheme, selectedGenre, vocalProf, tempo, apiKey, modelChoice);
                    usedApi = true;
                } catch (e) {
                    console.warn(`[${modelShort} Song Composer] Error:`, e);
                    showToast(`⚠️ ${modelShort} រវល់ ឬគ្មានអ៊ីនធឺណិត កំពុងប្រើប្រាស់ Smart AI Composer...`, 'warn');
                    newSong = composeDynamicSmartSong(customTopic, selectedTheme, selectedGenre, vocalProf, tempo);
                }
            } else {
                newSong = composeDynamicSmartSong(customTopic, selectedTheme, selectedGenre, vocalProf, tempo);
            }

            setButtonsLoading(false);

            if (!newSong) {
                newSong = composeDynamicSmartSong(customTopic, selectedTheme, selectedGenre, vocalProf, tempo);
            }

            if (newSong) {
                // Dual-layer Vocal Enforcement for Suno AI
                newSong.style = enforceVocalStylePrompt(newSong.style, vocalProf);
                newSong.lyrics = cleanDuplicateLyrics(enforceVocalLyricsTags(newSong.lyrics, vocalProf));

                // Ensure newSong.title is not a duplicate from previous loops
                if (typeof isTitleDuplicate === 'function' && isTitleDuplicate(newSong.title)) {
                    const freshTitle = typeof generateSingleUniqueKhmerTitle === 'function' 
                        ? generateSingleUniqueKhmerTitle(customTopic, selectedTheme?.name, selectedGenre?.name)
                        : `${newSong.title} (Mix #${Math.floor(10 + Math.random() * 90)})`;
                    console.log('[Suno Studio] Song title was duplicate, replaced with:', freshTitle);
                    newSong.title = freshTitle;
                }
                if (typeof recordUsedTitle === 'function') {
                    recordUsedTitle(newSong.title);
                }

                // 1. Title
                const titleInput = document.getElementById('suno-title-output');
                if (titleInput) {
                    titleInput.value = newSong.title || 'Suno_Song';
                    titleInput.style.borderColor = '#8b5cf6';
                    setTimeout(() => { if (titleInput) titleInput.style.borderColor = '#4a3e6a'; }, 1000);
                }
                const allTitles = [newSong.title, ...(newSong.alternativeTitles || [])].slice(0, 5);
                renderGeminiTitleChips(allTitles, newSong.title);

                // 2. Lyrics
                const lyricsBox = document.getElementById('suno-lyrics-output');
                if (lyricsBox) {
                    lyricsBox.value = newSong.lyrics || '';
                    lyricsBox.style.borderColor = '#10b981';
                    setTimeout(() => { if (lyricsBox) lyricsBox.style.borderColor = '#2d2d38'; }, 1000);
                }

                // 3. Style
                const styleBox = document.getElementById('suno-style-output');
                if (styleBox) {
                    styleBox.value = newSong.style || '';
                    styleBox.style.borderColor = '#3b82f6';
                    setTimeout(() => { if (styleBox) styleBox.style.borderColor = '#2d2d38'; }, 1000);
                }

                // 4. Automatically Auto-Fill directly into Suno's Create form!
                try {
                    mapAndFillSunoFields(newSong.lyrics, newSong.style, newSong.title);
                } catch (e) {
                    console.warn('[Suno Studio] Auto-fill into Suno form catch:', e);
                }

                showToast(usedApi ? `✨ ${modelShort} បាននិពន្ធបទចម្រៀងថ្មីស្រឡាង (Title + Lyrics + Style) និងបញ្ចូលក្នុង Suno រួចរាល់!` : '✨ Smart AI Engine បាននិពន្ធបទចម្រៀងថ្មីស្រឡាង (Title + Lyrics + Style) និងបញ្ចូលក្នុង Suno រួចរាល់!', 'success');
                return newSong;
            }
        } catch (err) {
            console.error('[Suno Studio] Error in generateSong:', err);
            showToast('⚠️ បញ្ហាក្នុងការបង្កើតបទចម្រៀង៖ ' + err.message, 'error');
            return null;
        }
    }

    // Auto-Loop Controller Object
    window.sunoAutoLoop = {
        isRunning: false,
        isPaused: false,
        loopCount: 0,
        currentStep: 0,
        statusText: 'ត្រៀមរួចរាល់',
        cooldownRemaining: 0,
        timerId: null,

        async start() {
            if (this.isRunning && !this.isPaused) return;
            this.isRunning = true;
            this.isPaused = false;
            try {
                if (window.chrome && window.chrome.webview) {
                    window.chrome.webview.postMessage(JSON.stringify({ action: 'auto_loop_status', active: true }));
                }
            } catch (e) { }
            showToast('🚀 បានចាប់ផ្តើមដំណើរការ Auto-Loop និពន្ធ និងបង្កើតចម្រៀងវិលជុំស្វ័យប្រវត្តិ!', 'success');
            updateAutoLoopUI();
            this.runCycle();
        },

        pause() {
            this.isPaused = true;
            this.statusText = '⏸️ បានផ្អាកបណ្តោះអាសន្ន';
            try {
                if (window.chrome && window.chrome.webview) {
                    window.chrome.webview.postMessage(JSON.stringify({ action: 'auto_loop_status', active: false }));
                }
            } catch (e) { }
            showToast('⏸️ បានផ្អាកដំណើរការ Auto-Loop', 'warn');
            updateAutoLoopUI();
        },

        resume() {
            if (!this.isRunning) return this.start();
            this.isPaused = false;
            this.statusText = '▶️ កំពុងបន្តដំណើរការ...';
            try {
                if (window.chrome && window.chrome.webview) {
                    window.chrome.webview.postMessage(JSON.stringify({ action: 'auto_loop_status', active: true }));
                }
            } catch (e) { }
            showToast('▶️ បានបន្តដំណើរការ Auto-Loop', 'info');
            updateAutoLoopUI();
            this.runCycle();
        },

        stop() {
            this.isRunning = false;
            this.isPaused = false;
            if (this.timerId) clearTimeout(this.timerId);
            this.currentStep = 0;
            this.statusText = '⏹️ បានបញ្ឈប់';
            try {
                if (window.chrome && window.chrome.webview) {
                    window.chrome.webview.postMessage(JSON.stringify({ action: 'auto_loop_status', active: false }));
                }
            } catch (e) { }
            showToast('⏹️ បានបញ្ឈប់ Auto-Loop រួចរាល់!', 'info');
            updateAutoLoopUI();
        },

        async runCycle() {
            if (!this.isRunning || this.isPaused) return;

            try {
                // Ensure on /create page
                if (!window.location.pathname.includes('/create')) {
                    this.statusText = '🔄 កំពុងប្តូរទៅកាន់ទំព័រ /create...';
                    updateAutoLoopUI();
                    window.location.href = 'https://suno.com/create';
                    this.scheduleNext(3000);
                    return;
                }

                // ជំហានទី ៥: ស្កេន វិភាគមើលថា Suno ផ្ទាំង Today បង្កើតចម្រៀងរួចរាល់ឫនៅ ព្រោះ Suno Create ចម្រៀងម្តងបានតែ៤បទ
                this.setStep(5, '⏳ ស្កេនពិនិត្យផ្ទាំង Today (អតិបរមា ៤ បទក្នុងម្តង)...');
                const todayFeed = analyzeSunoTodayFeed();
                if (todayFeed.isBusy) {
                    this.statusText = `⏳ ផ្ទាំង Today កំពុងបង្កើតពេញ (${todayFeed.activeCount}/4 បទ)... កំពុងរង់ចាំបញ្ចប់`;
                    updateAutoLoopUI();
                    this.scheduleNext(8000);
                    return;
                }

                // ជំហានទី ៤: ស្កេន វិភាគមើលប៊ូតុង Create របស់ Suno ដល់កំណត់ឫនៅ ហើយថាប៉ុន្មាននាទីទៀតបង្កើតចម្រៀងបានទៀង
                this.setStep(4, '🔍 ស្កេន វិភាគមើលប៊ូតុង Create & Cooldown (កំណត់របស់ Suno)...');
                const preAnalysis = analyzeSunoCreateButton();
                if (preAnalysis.isRateLimited) {
                    const totalSec = (preAnalysis.cooldownMinutes * 60) + preAnalysis.cooldownSeconds;
                    this.cooldownRemaining = totalSec;
                    this.statusText = `⏳ ដល់កំណត់! កំពុងរង់ចាំ ${preAnalysis.cooldownMinutes} នាទីទៀត...`;
                    updateAutoLoopUI();
                    showToast(`⚠️ Suno ដល់កំណត់! ប្រព័ន្ធនឹងរង់ចាំ ${preAnalysis.cooldownMinutes} នាទី ហើយបន្តស្វ័យប្រវត្តិ។`, 'warn');
                    this.scheduleNext(Math.max(5000, Math.min(totalSec * 1000, 60000)));
                    return;
                }

                if (preAnalysis.isOutOfCredits) {
                    this.statusText = '🛑 អស់ Credits របស់ Suno ហើយ! បានបញ្ឈប់ស្វ័យប្រវត្តិ។';
                    showToast('🛑 Suno អស់ Credits ហើយ! Auto-Loop ត្រូវបានផ្អាក។', 'warn');
                    this.stop();
                    return;
                }

                // ជំហានទី ១: ✨ បង្កើត Title
                this.setStep(1, '✨ បង្កើត Title ថ្មីស្រឡាង (Generate Title)...');
                const freshTitle = await generateFreshTitleOnly();
                await sleep(800);

                // ជំហានទី ២: បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីលបទភ្លេង ឡើងវិញ
                this.setStep(2, '🎵 បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីលបទភ្លេង ឡើងវិញ...');
                await generateSong();
                await sleep(1000);

                // បញ្ចូល Title + Style + Lyrics ចូលចំប្រអប់ Suno
                const curTitle = document.getElementById('suno-title-output')?.value || freshTitle || '';
                const curStyle = document.getElementById('suno-style-output')?.value || '';
                const curLyrics = document.getElementById('suno-lyrics-output')?.value || '';
                mapAndFillSunoFields(curLyrics, curStyle, curTitle);
                await sleep(1500);

                // ជំហានទី ៤ (ចុច Create): ស្កេន វិភាគមើលប៊ូតុង Create និងចុចបង្កើតបទចម្រៀង
                this.setStep(4, '🔍 ស្កេនពិនិត្យប៊ូតុង Create និងចុចបង្កើតបទចម្រៀង...');
                ensureCustomMode();
                await sleep(500);

                const finalCreate = analyzeSunoCreateButton();
                let createClicked = false;
                if (finalCreate.button && !finalCreate.button.disabled && finalCreate.button.getAttribute('aria-disabled') !== 'true') {
                    console.log('[Auto-Loop] Clicking Suno Create button!');
                    finalCreate.button.click();
                    createClicked = true;
                } else {
                    await sleep(600);
                    const retryCreate = analyzeSunoCreateButton();
                    if (retryCreate.button) {
                        retryCreate.button.click();
                        createClicked = true;
                    }
                }

                if (createClicked) {
                    this.loopCount++;
                    this.statusText = `🎉 បានចុច Create ជុំទី ${this.loopCount} រួចរាល់! កំពុងដំណើរការ...`;
                    showToast(`🎉 បានចុច Create ជុំទី ${this.loopCount} ជោគជ័យ!`, 'success');
                    updateAutoLoopUI();

                    // ជំហានទី ៥: ស្កេន Today Feed កំពុងទទួលបទចម្រៀងថ្មី
                    this.setStep(5, '⏳ ស្កេន Today Feed កំពុងទទួលបទចម្រៀងថ្មី...');
                    await sleep(5000); // Wait 5s for Suno to register creation in backend

                    // ជំហានទី ៣: លុប Lyrics + Styles + Song Title (Optional) ចេញ (សម្អាតប្រអប់ត្រៀមជុំបន្ទាប់)
                    this.setStep(3, '🗑️ លុបសម្អាតប្រអប់ (Optional) ត្រៀមសម្រាប់ជុំបន្ទាប់...');
                    clearAllSunoFields(true);
                    await sleep(1000);

                    // Wait remaining cooldown interval before starting next song
                    this.scheduleNext(8000);
                } else {
                    this.statusText = '⚠️ មិនអាចចុច Create បានទេ៖ ' + finalCreate.reason;
                    updateAutoLoopUI();
                    this.scheduleNext(5000);
                }

            } catch (e) {
                console.error('[Auto-Loop] Error in cycle:', e);
                this.statusText = '⚠️ មានបញ្ហា៖ ' + e.message;
                updateAutoLoopUI();
                this.scheduleNext(6000);
            }
        },

        setStep(num, desc) {
            this.currentStep = num;
            this.statusText = `[ជំហានទី ${num}] ${desc}`;
            updateAutoLoopUI();
        },

        scheduleNext(ms) {
            if (!this.isRunning || this.isPaused) return;
            this.timerId = setTimeout(() => {
                this.runCycle();
            }, ms);
        }
    };

    // =========================================================================
    // 8.5 AUTO BATCH SELECTION & SMART PLAYLIST ENGINE (10, 14, 18 TRACKS)
    // =========================================================================
    let currentlySelectedSongCount = 0;

    function getSunoDeviceId() {
        if (window.__sunoDeviceId) return window.__sunoDeviceId;
        try {
            for (let i = 0; i < localStorage.length; i++) {
                const key = localStorage.key(i);
                if (/device[-_]?id/i.test(key)) {
                    const val = localStorage.getItem(key);
                    if (val && typeof val === 'string' && val.length >= 16) {
                        window.__sunoDeviceId = val.replace(/^["']|["']$/g, '');
                        return window.__sunoDeviceId;
                    }
                }
            }
        } catch (e) {}
        try {
            const m = document.cookie.match(/device[-_]?id=([a-f0-9\-]+)/i);
            if (m) {
                window.__sunoDeviceId = m[1];
                return window.__sunoDeviceId;
            }
        } catch (e) {}
        try {
            const stored = localStorage.getItem('suno_client_device_id');
            if (stored) {
                window.__sunoDeviceId = stored;
            } else {
                const newId = (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : '3e36703f-dc07-4b17-9c74-d092d5c8d5bc';
                localStorage.setItem('suno_client_device_id', newId);
                window.__sunoDeviceId = newId;
            }
        } catch (e) {
            window.__sunoDeviceId = '3e36703f-dc07-4b17-9c74-d092d5c8d5bc';
        }
        return window.__sunoDeviceId;
    }

    function isSongCheckboxChecked(cb) {
        if (!cb) return false;
        if (typeof cb.checked === 'boolean' && cb.tagName === 'INPUT') return cb.checked;
        const ariaChecked = cb.getAttribute('aria-checked');
        if (ariaChecked === 'true') return true;
        if (cb.hasAttribute('data-checked')) return true;
        if (cb.querySelector && cb.querySelector('.hxc-checkbox-indicator, [data-checked], .hxc-checkbox-checked-glyph')) return true;
        return false;
    }

    function getSongFeedScrollContainer() {
        const firstBtn = document.querySelector('.multi-select-button, [role="checkbox"][aria-label^="Select "]');
        if (firstBtn) {
            let p = firstBtn.parentElement;
            while (p && p !== document.body) {
                const style = window.getComputedStyle(p);
                const overflowY = style.overflowY || style.overflow;
                if ((overflowY === 'auto' || overflowY === 'scroll') && p.scrollHeight > p.clientHeight) {
                    return p;
                }
                p = p.parentElement;
            }
        }
        return document.querySelector('div[class*="e1pdu1gn"], [role="feed"]')?.parentElement || window;
    }

    function getFeedSongCheckboxes() {
        // Query Suno's custom <span role="checkbox"> elements and fallback inputs
        const selectors = [
            '[role="checkbox"][aria-label^="Select "]',
            '.multi-select-button [role="checkbox"]',
            '.multi-select-button span.hxc-checkbox',
            'span.hxc-checkbox[role="checkbox"]',
            'div[data-testid*="clip"] [role="checkbox"]',
            'div[class*="SongCard"] [role="checkbox"]',
            'div.clip-row [role="checkbox"]',
            'input[type="checkbox"]'
        ];
        const candidates = document.querySelectorAll(selectors.join(', '));
        const seen = new Set();
        const results = [];

        for (const el of candidates) {
            // Exclude our own UI elements (panel, drawer, modals)
            if (el.closest('#suno-auto-loop-panel, #suno-control-drawer, #suno-settings-modal, [id^="suno-"]')) continue;
            if (seen.has(el)) continue;
            seen.add(el);

            const aria = (el.getAttribute('aria-label') || '').toLowerCase();
            const isSelectAria = aria.startsWith('select ');
            const inSongCard = !!el.closest('.multi-select-button, div.clip-row, [data-testid*="clip"], div[class*="SongCard"], tr, li');

            if (isSelectAria || inSongCard || el.classList.contains('hxc-checkbox')) {
                results.push(el);
            }
        }
        return results;
    }

    function getFeedSongLinks() {
        return Array.from(document.querySelectorAll('a[href*="/song/"]'));
    }

    function getFeedClipIds(targetCount = 18) {
        const clipSet = new Set();
        document.querySelectorAll('a[href*="/song/"]').forEach(a => {
            const m = (a.getAttribute('href') || '').match(/\/song\/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/i);
            if (m) clipSet.add(m[1]);
        });
        document.querySelectorAll('[data-clip-id], [data-id]').forEach(el => {
            const id = el.getAttribute('data-clip-id') || el.getAttribute('data-id');
            if (id && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id)) clipSet.add(id);
        });
        if (clipSet.size < targetCount && Array.isArray(window.__sunoClipsCache)) {
            window.__sunoClipsCache.forEach(c => {
                if (c && c.id && clipSet.size < targetCount) clipSet.add(c.id);
            });
        }
        return Array.from(clipSet).slice(0, targetCount);
    }

    function getCheckedSongClipIds(targetCount = 18) {
        const clipSet = new Set();
        const checkboxes = getFeedSongCheckboxes();
        for (const cb of checkboxes) {
            if (isSongCheckboxChecked(cb)) {
                // Find song row / card container
                const card = cb.closest('.multi-select-button')?.parentElement?.parentElement
                    || cb.closest('div.clip-row, [role="group"], [data-testid*="clip"], tr, li')
                    || cb.parentElement;
                if (card) {
                    const songLink = card.querySelector('a[href*="/song/"]');
                    if (songLink) {
                        const m = (songLink.getAttribute('href') || '').match(/\/song\/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/i);
                        if (m) clipSet.add(m[1]);
                    }
                    const dataId = card.getAttribute('data-clip-id') || card.getAttribute('data-id');
                    if (dataId && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(dataId)) {
                        clipSet.add(dataId);
                    }
                }
            }
            if (clipSet.size >= targetCount) break;
        }

        // Fallback to getFeedClipIds if needed
        if (clipSet.size < targetCount) {
            getFeedClipIds(targetCount).forEach(id => clipSet.add(id));
        }

        return Array.from(clipSet).slice(0, targetCount);
    }

    async function selectBatchSongs(targetCount = 10) {
        targetCount = parseInt(targetCount, 10) || 10;
        showToast(`⏳ កំពុងស្កេន និងធិកជ្រើសរើសចម្រៀងឱ្យគ្រប់ចំនួន ${targetCount} បទ...`, 'info');

        const feedContainer = getSongFeedScrollContainer();

        // 1. Reset scroll to top so we reliably select from newest song rows
        if (feedContainer && feedContainer.scrollTo) {
            try { feedContainer.scrollTo({ top: 0, behavior: 'instant' }); } catch (e) {}
        } else if (window.scrollTo) {
            try { window.scrollTo({ top: 0, behavior: 'instant' }); } catch (e) {}
        }
        await sleep(200);

        const checkedSet = new Set();
        let scrollAttempts = 0;
        const maxScrolls = 35;

        // 2. Progressively scroll and check boxes until we reach the FULL targetCount
        while (checkedSet.size < targetCount && scrollAttempts < maxScrolls) {
            const checkboxes = getFeedSongCheckboxes();

            for (let i = 0; i < checkboxes.length; i++) {
                if (checkedSet.size >= targetCount) break;

                const cb = checkboxes[i];

                // Identifier for this song
                const card = cb.closest('.multi-select-button')?.parentElement?.parentElement
                    || cb.closest('div.clip-row, [role="group"], [data-testid*="clip"], tr, li')
                    || cb.parentElement;
                const link = card?.querySelector('a[href*="/song/"]');
                const m = (link?.getAttribute('href') || '').match(/\/song\/([a-f0-9-]{36})/i);
                const clipId = m ? m[1] : (card?.getAttribute('data-clip-id') || cb.getAttribute('aria-label') || `idx_${i}`);

                // Make the multi-select container persistently visible on the song card
                const multiBtn = cb.closest('.multi-select-button');
                if (multiBtn) {
                    multiBtn.style.opacity = '1';
                    multiBtn.style.visibility = 'visible';
                }

                if (!isSongCheckboxChecked(cb)) {
                    // Scroll into view if needed
                    try { cb.scrollIntoView({ behavior: 'instant', block: 'nearest' }); } catch (e) {}
                    cb.click();
                    await sleep(60);
                }

                if (isSongCheckboxChecked(cb)) {
                    checkedSet.add(clipId);
                }
            }

            if (checkedSet.size >= targetCount) break;

            // Scroll down feed container to load virtualized rows
            if (feedContainer && feedContainer.scrollBy) {
                feedContainer.scrollBy({ top: 400, behavior: 'smooth' });
            } else {
                window.scrollBy({ top: 400, behavior: 'smooth' });
            }
            await sleep(220);
            scrollAttempts++;
        }

        // 3. Scroll back to top smoothly so the user sees the checked songs
        if (feedContainer && feedContainer.scrollTo) {
            try { feedContainer.scrollTo({ top: 0, behavior: 'smooth' }); } catch (e) {}
            await sleep(200);
        }

        const finalCount = checkedSet.size;
        currentlySelectedSongCount = finalCount;
        updatePlaylistSelectionUI(finalCount);

        if (finalCount >= targetCount) {
            showToast(`✅ បានធិកជ្រើសរើសគ្រប់ចំនួន ${finalCount}/${targetCount} បទរួចរាល់!`, 'success');
        } else {
            showToast(`ℹ️ បានធិកជ្រើសរើស ${finalCount}/${targetCount} បទ (បទក្នុង Feed មានតែប៉ុណ្ណេះ)!`, 'info');
        }

        return finalCount;
    }

    function deselectAllSongs() {
        const checkboxes = getFeedSongCheckboxes();
        let count = 0;
        checkboxes.forEach(cb => {
            if (isSongCheckboxChecked(cb)) {
                cb.click();
                count++;
            }
            const multiBtn = cb.closest('.multi-select-button');
            if (multiBtn) {
                multiBtn.style.opacity = '';
                multiBtn.style.visibility = '';
            }
        });
        currentlySelectedSongCount = 0;
        updatePlaylistSelectionUI(0);
        showToast(`🔄 បានដោះធិកចម្រៀងទាំងអស់ (${count} បទ) រួចរាល់!`, 'info');
    }

    function getProceduralPlaylistName(count = 14) {
        count = parseInt(count, 10) || 14;
        const today = new Date();
        const year = today.getFullYear();
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const month = months[today.getMonth()];

        let usedNames = [];
        try {
            usedNames = JSON.parse(localStorage.getItem('suno_used_playlist_names') || '[]');
        } catch (e) {}

        let nextVol = 1;
        try {
            const matches = usedNames.map(n => n.match(/Vol\.?\s*0?(\d+)/i)).filter(Boolean).map(m => parseInt(m[1], 10));
            if (matches.length > 0) nextVol = Math.max(...matches) + 1;
        } catch (e) {}
        const volStr = String(nextVol).padStart(2, '0');

        const templates = [
            `ស្នេហាក្នុងរាត្រីភ្នំពេញ (Phnom Penh Night Hits) [${count} Tracks]`,
            `បណ្តុំចម្រៀង Drift Phonk & Bass ${year} (Vol. ${volStr}) [${count} Tracks]`,
            `អនុស្សាវរីយ៍ជ្រោះស្នេហ៍ (Acoustic Romance ${year}) [${count} Tracks]`,
            `Suno Khmer Masterpiece · កម្រងចម្រៀងកំពូលស្នាដៃ [${count} Tracks]`,
            `ចង្វាក់រាំញាក់កន្ត្រាក់អារម្មណ៍ (EDM Club Festival) [${count} Tracks]`,
            `KH-Hits Master Collection (Vol. ${volStr}) [${count} Tracks]`,
            `មន្តស្នេហ៍តន្ត្រីសម័យថ្មី ${year} (Khmer Wave) [${count} Tracks]`,
            `បំភ្លេចមិនបាន (Unforgettable Melodies ${year}) [${count} Tracks]`,
            `រាត្រីស្រវឹងស្នេហ៍ (Late Night Chill R&B) [${count} Tracks]`,
            `មរតកសំនៀងថ្មី ${year} · Suno Pro Edition [${count} Tracks]`,
            `បទចម្រៀងកំដរអារម្មណ៍ (Deep Soul & Coffee Vibes) [${count} Tracks]`,
            `សំឡេងរាត្រីកម្ពុជា (Cambodian Midnight Beats) [${count} Tracks]`,
            `ស្នេហ៍វ័យជំទង់ (Romantic Pop Melodies) [${count} Tracks]`,
            `បណ្តុំចម្រៀងពេញនិយមប្រចាំខែ ${month} ${year} [${count} Tracks]`,
            `បទភ្លេងកន្ត្រាក់បេះដូង (High Energy Phonk & Synth) [${count} Tracks]`,
            `ភ្លេងមនោសញ្ចេតនាស្នេហ៍ជ្រាលជ្រៅ (Deep Emotional Acoustic) [${count} Tracks]`,
            `សំនៀងពិរោះរណ្តំ (Khmer Golden Soul ${year}) [${count} Tracks]`,
            `ដំណើរឆ្លងកាត់រាត្រី (Night Cruise Phonk) [${count} Tracks]`,
            `បទចម្រៀងស្នេហ៍ផ្អែមល្ហែម (Sweet Romance Hits) [${count} Tracks]`,
            `ចង្វាក់ក្លឹបកម្សាន្តរាត្រី (Urban Electro Dance) [${count} Tracks]`
        ];

        const available = templates.filter(t => !usedNames.includes(t));
        const chosen = available.length > 0 ? available[Math.floor(Math.random() * available.length)] : templates[Math.floor(Math.random() * templates.length)];

        try {
            usedNames.push(chosen);
            if (usedNames.length > 60) usedNames.shift();
            localStorage.setItem('suno_used_playlist_names', JSON.stringify(usedNames));
        } catch (e) {}

        return chosen;
    }

    async function callGeminiApiForPlaylistName(apiKey, model, count) {
        const targetModel = model || localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';
        if (targetModel === 'smart_engine') return null;

        const promptText = `You are an elite music curator creating playlist titles for Suno AI music collections.
Generate 1 unique, catchy, viral, and authentic Khmer & bilingual playlist title for a batch of ${count} songs.
Style guidelines:
- Poetic or energetic Khmer phrase combined with an English subtitle and track count.
- Format: "ចំណងជើងជាភាសាខ្មែរ (English Subtitle) [${count} Tracks]"
- Examples: "ស្នេហាក្នុងរាត្រីភ្នំពេញ (Phnom Penh Night Beats) [${count} Tracks]" or "មន្តស្នេហ៍តន្ត្រីសម័យថ្មី 2026 (Khmer New Wave) [${count} Tracks]"
Return ONLY the single title string with no quotes or extra text.`;

        const url = `https://generativelanguage.googleapis.com/v1beta/models/${targetModel}:generateContent?key=${apiKey}`;
        const res = await fetch(url, {
            method: 'POST',
            signal: AbortSignal.timeout ? AbortSignal.timeout(5000) : undefined,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                contents: [{ parts: [{ text: promptText }] }],
                generationConfig: {
                    temperature: 0.9,
                    maxOutputTokens: 60
                }
            })
        });
        if (!res.ok) return null;
        const data = await res.json();
        const raw = data?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (raw && typeof raw === 'string') {
            const clean = raw.trim().replace(/^["'`]|["'`]$/g, '').trim();
            if (clean.length > 4) return clean;
        }
        return null;
    }

    async function generateSmartPlaylistName(count = 14) {
        count = parseInt(count, 10) || 14;
        const apiKey = localStorage.getItem('gemini_api_key') || '';
        const modelChoice = localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';

        if (apiKey && modelChoice !== 'smart_engine') {
            try {
                const geminiName = await callGeminiApiForPlaylistName(apiKey, modelChoice, count);
                if (geminiName) return geminiName;
            } catch (e) {
                console.warn('[Smart Playlist Generator] Gemini call failed, using procedural fallback:', e);
            }
        }
        return getProceduralPlaylistName(count);
    }

    function updatePlaylistSelectionUI(count, plName) {
        const badges = [
            document.getElementById('suno-playlist-selected-badge'),
            document.getElementById('suno-drawer-playlist-badge')
        ];
        badges.forEach(b => {
            if (b) {
                b.textContent = count > 0 ? `បានធិក ${count} បទ` : 'បានធិក 0 បទ';
                b.style.background = count > 0 ? 'rgba(16,185,129,0.2)' : 'rgba(255,255,255,0.06)';
                b.style.color = count > 0 ? '#10b981' : '#94a3b8';
            }
        });

        const inputs = [
            document.getElementById('suno-playlist-name-input'),
            document.getElementById('suno-drawer-playlist-input')
        ];
        if (plName) {
            inputs.forEach(inp => { if (inp) inp.value = plName; });
        }

        const actionBtns = [
            document.getElementById('suno-btn-auto-add-playlist'),
            document.getElementById('suno-drawer-btn-auto-add')
        ];
        actionBtns.forEach(btn => {
            if (btn) {
                const target = count > 0 ? count : 14;
                btn.innerHTML = `<span>🚀</span><span>Add ចូល Playlist តែម្តង (${target} បទ)</span>`;
            }
        });
    }

    async function createAndAddToPlaylist(playlistName, targetCount = 14) {
        targetCount = parseInt(targetCount, 10) || 14;
        if (!playlistName || !playlistName.trim()) {
            playlistName = await generateSmartPlaylistName(targetCount);
        }
        playlistName = playlistName.trim();

        showToast(`🚀 កំពុងដំណើរការ Add to Playlist "${playlistName}" (${targetCount} បទ)...`, 'info');

        // 1. Ensure targetCount songs are checked in the feed first ("នៅពេលជ្រើសរើសគ្រប់ចំនួន... ចាំ Add")
        showToast(`⏳ កំពុងធិកជ្រើសរើសឱ្យគ្រប់ចំនួន ${targetCount} បទជាមុនសិន...`, 'info');
        const checkedCount = await selectBatchSongs(targetCount);
        await sleep(350);

        if (checkedCount < targetCount) {
            showToast(`⚠️ ធិកបានត្រឹម ${checkedCount}/${targetCount} បទ (មិនគ្រប់ចំនួន ${targetCount} បទទេ តែបន្ត Add ទាំងអស់)...`, 'warn');
        } else {
            showToast(`✅ បានជ្រើសរើសគ្រប់ចំនួន ${checkedCount} បទហើយ! កំពុង Add ចូល Playlist "${playlistName}" តែម្តង...`, 'info');
        }

        // Auto-deduplicate sibling tracks among the checked songs if enabled
        if (localStorage.getItem('suno_auto_dedup_titles') !== 'false') {
            try {
                await renameDuplicateSiblingClips({ checkedOnly: true });
                await sleep(300);
            } catch (e) {
                console.warn('[Playlist Engine] Auto-dedup sibling check error:', e);
            }
        }

        // 2. Extract unique Clip UUIDs from the checked songs
        const clipIds = getCheckedSongClipIds(checkedCount);
        const deviceId = getSunoDeviceId();

        let apiSuccess = false;

        // PIPELINE 1: Direct Session API Call with device-id header (Single-Shot Batch API)
        if (clipIds.length > 0) {
            try {
                const apiHeaders = {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json'
                };
                if (deviceId) apiHeaders['device-id'] = deviceId;

                const createRes = await fetch('/a/api/playlist/create/', {
                    method: 'POST',
                    headers: apiHeaders,
                    body: JSON.stringify({
                        name: playlistName,
                        description: `Auto Playlist created by Suno Studio (${clipIds.length} tracks)`
                    })
                });

                if (createRes.ok) {
                    const plData = await createRes.json();
                    if (plData && plData.id) {
                        const updateRes = await fetch('/a/api/playlist/update_clips/', {
                            method: 'POST',
                            headers: apiHeaders,
                            body: JSON.stringify({
                                playlist_id: plData.id,
                                clip_ids: clipIds
                            })
                        });

                        if (updateRes.ok || updateRes.status === 204) {
                            apiSuccess = true;
                            // Trigger Suno client library/sidebar cache refresh
                            fetch('/a/api/playlist/me?page=1&show_trashed=false&show_sharelist=false', {
                                headers: deviceId ? { 'device-id': deviceId } : {}
                            }).catch(() => {});

                            showToast(`🎉 ជោគជ័យ ១០០%! បានជ្រើសរើសគ្រប់ចំនួន ${clipIds.length} បទ និង Add ចូល Playlist "${playlistName}" តែម្តងរួចរាល់! 🚀`, 'success');
                            updatePlaylistSelectionUI(clipIds.length, playlistName);
                            return true;
                        }
                    }
                }
            } catch (err) {
                console.warn('[Playlist Engine] Direct API call error, falling back to DOM flow:', err);
            }
        }

        // PIPELINE 2: Single-Shot Batch DOM Automation Fallback ("តែម្តងរួចរាល់")
        if (!apiSuccess) {
            showToast('🔄 កំពុងប្រើប្រាស់ Batch DOM Automation ដើម្បី Add ចូល Playlist តែម្តង...', 'info');

            // Find any checked song row in the feed to open the batch context menu
            const checkboxes = getFeedSongCheckboxes();
            let targetCard = null;
            for (const cb of checkboxes) {
                if (isSongCheckboxChecked(cb)) {
                    targetCard = cb.closest('div.clip-row, [role="group"], [data-testid*="clip"], tr, li')
                        || cb.closest('.multi-select-button')?.parentElement?.parentElement;
                    if (targetCard) break;
                }
            }

            if (!targetCard) {
                targetCard = document.querySelector('div.clip-row, [role="group"]');
            }

            const moreBtn = targetCard?.querySelector('button[aria-label="More options"], button.context-menu-button');
            if (moreBtn) {
                moreBtn.click();
                await sleep(350);

                const menuItems = Array.from(document.querySelectorAll('[role="menuitem"], button, div[role="button"]'));
                const addPlaylistBtn = menuItems.find(el => /Add to playlist/i.test(el.innerText || ''));
                if (addPlaylistBtn) {
                    addPlaylistBtn.click();
                    await sleep(450);

                    const dialog = document.querySelector('[role="dialog"]');
                    if (dialog) {
                        const playlistInput = dialog.querySelector('input[placeholder="Playlist name"], input[type="text"]');
                        if (playlistInput) {
                            playlistInput.focus();
                            const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
                            if (nativeSetter) nativeSetter.call(playlistInput, playlistName);
                            else playlistInput.value = playlistName;

                            if (playlistInput._valueTracker) playlistInput._valueTracker.setValue('');
                            playlistInput.dispatchEvent(new Event('input', { bubbles: true }));
                            playlistInput.dispatchEvent(new Event('change', { bubbles: true }));
                            try {
                                document.execCommand('selectAll', false, null);
                                document.execCommand('insertText', false, playlistName);
                            } catch (e) {}
                            playlistInput.dispatchEvent(new Event('input', { bubbles: true }));
                            await sleep(300);

                            const createBtn = Array.from(dialog.querySelectorAll('button')).find(b => /Create playlist/i.test(b.innerText || ''));
                            if (createBtn) {
                                createBtn.disabled = false;
                                createBtn.removeAttribute('disabled');
                                createBtn.click();
                                await sleep(600);
                                showToast(`🎉 ជោគជ័យ ១០០%! បានជ្រើសរើសគ្រប់ចំនួន ${checkedCount} បទ និង Add ចូល Playlist "${playlistName}" តែម្តងរួចរាល់! 🚀`, 'success');
                                updatePlaylistSelectionUI(checkedCount, playlistName);
                                return true;
                            }
                        }
                    }
                }
            }

            showToast('⚠️ មិនអាចបើកផ្ទាំង Add to playlist ក្នុង Suno បានឡើយ!', 'error');
            return false;
        }

        return false;
    }

    // Expose on window
    window.selectBatchSongs = selectBatchSongs;
    window.deselectAllSongs = deselectAllSongs;
    window.isSongCheckboxChecked = isSongCheckboxChecked;
    window.getFeedSongCheckboxes = getFeedSongCheckboxes;
    window.getCheckedSongClipIds = getCheckedSongClipIds;
    window.getCheckedSongsList = getCheckedSongsList;
    window.generateSmartPlaylistName = generateSmartPlaylistName;
    window.createAndAddToPlaylist = createAndAddToPlaylist;

    // =========================================================================
    // 8.6 AI SIBLING TITLE COHESION & AUTO-DEDUPLICATION ENGINE
    // =========================================================================
    const activeRenamingSet = new Set();

    async function callGeminiForSisterTitle(apiKey, model, originalTitle, style, lyrics) {
        const targetModel = model || localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';
        if (targetModel === 'smart_engine') return null;

        let vocalTag = '';
        const vocalMatch = originalTitle.match(/\((បទស្រី|បទប្រុស|បទឆ្លើយឆ្លង|Female|Male|Duet)\)/i);
        if (vocalMatch) {
            vocalTag = ` ${vocalMatch[0]}`;
        }
        const cleanTitle = originalTitle.replace(/\s*\((បទស្រី|បទប្រុស|បទឆ្លើយឆ្លង|Female|Male|Duet)\)/gi, '').trim();

        const promptText = `You are an elite Cambodian music producer and hit songwriter.
Suno AI generates 2 variation tracks per prompt with the EXACT SAME title: "${originalTitle}".
We are keeping Track 1 as "${originalTitle}".
Generate a single brand-new, unique, and creative companion/sister title for Track 2 that is deeply COHESIVE, HARMONIOUS, and THEMATICALLY LINKED with "${cleanTitle}" ("ន័យអោយស៊ីនិងចំណងជើងចាស់").

Context:
- Original Track 1 Title: "${cleanTitle}"
${style ? `- Musical Style: "${style}"` : ''}
${lyrics ? `- Lyrics Excerpt: "${lyrics.slice(0, 200)}"` : ''}

Rules:
1. The new title MUST carry the exact same emotion, mood, and poetic theme as "${cleanTitle}". It can be an alternate poetic phrasing, a companion perspective, or a thematic version (e.g. "ស្រមោលស្នេហ៍ក្នុងរាត្រី" -> "ដានស្នេហ៍ក្រោមពន្លឺចន្ទ" or "ស្រមោលស្នេហ៍ [Acoustic Soul]").
2. Write in authentic Khmer (may include an English subtitle in parentheses or brackets if stylish).
3. Do NOT just copy "${cleanTitle}" directly. It must be a distinct sister title.
${vocalTag ? `4. Append the vocal tag "${vocalTag.trim()}" at the end.` : ''}
5. Return ONLY the title string, nothing else. No quotes, no markdown, no explanation.`;

        const url = `https://generativelanguage.googleapis.com/v1beta/models/${targetModel}:generateContent?key=${apiKey}`;
        const res = await fetch(url, {
            method: 'POST',
            signal: AbortSignal.timeout ? AbortSignal.timeout(6000) : undefined,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                contents: [{ parts: [{ text: promptText }] }],
                generationConfig: {
                    temperature: 0.85,
                    maxOutputTokens: 60
                }
            })
        });

        if (!res.ok) return null;
        const data = await res.json();
        const raw = data?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (raw && typeof raw === 'string') {
            let clean = raw.trim().replace(/^["'`]|["'`]$/g, '').trim();
            if (clean.length > 2 && clean !== originalTitle) {
                return clean;
            }
        }
        return null;
    }

    function generateProceduralSisterTitle(originalTitle) {
        if (!originalTitle) return 'Suno Song (Variation II)';

        let vocalTag = '';
        const vocalMatch = originalTitle.match(/\((បទស្រី|បទប្រុស|បទឆ្លើយឆ្លង|Female|Male|Duet)\)/i);
        if (vocalMatch) {
            vocalTag = ` ${vocalMatch[0]}`;
        }
        const cleanTitle = originalTitle.replace(/\s*\((បទស្រី|បទប្រុស|បទឆ្លើយឆ្លង|Female|Male|Duet)\)/gi, '').trim();

        const variations = [
            `${cleanTitle} (Part II · បទភ្លេងថ្មី)`,
            `${cleanTitle} [Soul Melodic Mix]`,
            `${cleanTitle} (Deep Acoustic Vibe)`,
            `អនុស្សាវរីយ៍${cleanTitle}`,
            `${cleanTitle} [Midnight Edition]`,
            `រលកអនុស្សាវរីយ៍ ${cleanTitle}`,
            `${cleanTitle} (Harmonic Variation)`,
            `ដំណើរឆ្លងកាត់${cleanTitle}`,
            `${cleanTitle} [Extended Beats]`,
            `${cleanTitle} (Special Version)`
        ];

        const chosen = variations[Math.floor(Math.random() * variations.length)];
        return `${chosen}${vocalTag}`;
    }

    async function generateCohesiveSisterTitle(originalTitle, style = '', lyrics = '') {
        if (!originalTitle) return 'Suno Song (Variation II)';

        const apiKey = localStorage.getItem('gemini_api_key') || '';
        const modelChoice = localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';

        if (apiKey && modelChoice !== 'smart_engine') {
            try {
                const aiTitle = await callGeminiForSisterTitle(apiKey, modelChoice, originalTitle, style, lyrics);
                if (aiTitle) return aiTitle;
            } catch (e) {
                console.warn('[Sister Title] Gemini error, fallback to procedural:', e);
            }
        }

        return generateProceduralSisterTitle(originalTitle);
    }

    async function renameSunoClip(clipId, newTitle) {
        if (!clipId || !newTitle || !newTitle.trim()) return false;
        newTitle = newTitle.trim();

        const deviceId = getSunoDeviceId();
        const url = `/a/api/gen/${clipId}/set_metadata/`;

        try {
            const res = await fetch(url, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    ...(deviceId ? { 'device-id': deviceId } : {})
                },
                body: JSON.stringify({
                    title: newTitle,
                    allow_remix: true,
                    allow_comments: true,
                    allow_remix_downloads: true
                })
            });

            if (res.ok) {
                console.log(`[Suno Studio] Successfully renamed clip ${clipId} to: "${newTitle}"`);

                if (typeof clipDatabase !== 'undefined' && clipDatabase.has(clipId)) {
                    const entry = clipDatabase.get(clipId);
                    entry.title = newTitle;
                    clipDatabase.set(clipId, entry);
                }

                try {
                    const links = Array.from(document.querySelectorAll(`a[href*="${clipId}"]`));
                    links.forEach(link => {
                        const row = link.closest('div.clip-row, [role="group"], tr, li') || link.parentElement;
                        const heading = row ? row.querySelector('h1, h2, h3, h4') : null;
                        if (heading) heading.innerText = newTitle;
                        link.innerText = newTitle;
                        const cb = row ? row.querySelector('[role="checkbox"]') : null;
                        if (cb) cb.setAttribute('aria-label', `Select ${newTitle}`);
                    });
                } catch (e) {}

                if (typeof updateRecentSongsUI === 'function') updateRecentSongsUI();
                return true;
            } else {
                console.warn(`[Suno Studio] renameSunoClip returned status ${res.status}`);
            }
        } catch (err) {
            console.error('[Suno Studio] Error renaming clip:', err);
        }
        return false;
    }

    function getCheckedSongsList() {
        const list = [];
        const seen = new Set();
        const checkboxes = getFeedSongCheckboxes();

        for (const cb of checkboxes) {
            if (!isSongCheckboxChecked(cb)) continue;

            const card = cb.closest('div.clip-row, [role="group"], [data-testid*="clip"], tr, li')
                || cb.closest('.multi-select-button')?.parentElement?.parentElement
                || cb.parentElement;

            let title = (cb.getAttribute('aria-label') || '').replace(/^Select\s+/i, '').trim();
            if (!title && card) {
                const h = card.querySelector('h1, h2, h3, h4, [class*="title"], a[href*="/song/"]');
                if (h) title = (h.innerText || '').trim().split('\n')[0].trim();
            }

            let clipId = null;
            if (card) {
                const link = card.querySelector('a[href*="/song/"]');
                const m = (link?.getAttribute('href') || '').match(/\/song\/([a-f0-9-]{36})/i);
                if (m) clipId = m[1];
                if (!clipId) {
                    const dataId = card.getAttribute('data-clip-id') || card.getAttribute('data-id');
                    if (dataId && /^[a-f0-9-]{36}$/i.test(dataId)) clipId = dataId;
                }
            }

            if (clipId && !seen.has(clipId)) {
                seen.add(clipId);
                list.push({
                    id: clipId,
                    title: title,
                    card: card,
                    checkbox: cb
                });
            }
        }
        return list;
    }

    function getFeedSongsList() {
        const list = [];
        const seen = new Set();
        const links = Array.from(document.querySelectorAll('a[href*="/song/"]'));

        links.forEach(a => {
            if (a.closest('#suno-auto-loop-panel, #suno-control-drawer, [id^="suno-"]')) return;
            const href = a.getAttribute('href') || '';
            const m = href.match(/\/song\/([a-f0-9\-]{36})/i);
            if (!m) return;
            const clipId = m[1];
            if (seen.has(clipId)) return;
            seen.add(clipId);

            const row = a.closest('div.clip-row, [role="group"], tr, li') || a.parentElement;
            const heading = row ? row.querySelector('h1, h2, h3, h4, [class*="title"]') : null;
            let title = (heading ? heading.innerText : a.innerText || '').trim().split('\n')[0].trim();
            if (clipId && title) {
                list.push({ id: clipId, title: title, row: row });
            }
        });

        return list;
    }

    async function renameDuplicateSiblingClips(options = {}) {
        let checkedSongs = getCheckedSongsList();
        let isFromChecked = false;
        let songs = [];

        // Priority 1: Target specifically the TICKED/CHECKED songs if any are selected!
        if (checkedSongs.length > 0) {
            songs = checkedSongs;
            isFromChecked = true;
            showToast(`🔍 កំពុងស្កេនរកបទភ្លោះក្នុងចំណោមចម្រៀងដែលបានធិក (${songs.length} បទ)...`, 'info');
        } else {
            songs = getFeedSongsList();
            showToast(`🔍 កំពុងស្កេនរកបទភ្លោះក្នុង Feed (${songs.length} បទ)...`, 'info');
        }

        if (songs.length === 0) {
            showToast('⚠️ មិនអាចស្វែងរកបទចម្រៀងបានឡើយ!', 'warn');
            return 0;
        }

        // Group by title to detect duplicate pairs/triplets
        const titleGroups = new Map();
        songs.forEach(s => {
            const cleanTitle = (s.title || '').trim();
            if (!cleanTitle) return;
            if (!titleGroups.has(cleanTitle)) {
                titleGroups.set(cleanTitle, []);
            }
            titleGroups.get(cleanTitle).push(s);
        });

        // Filter groups with duplicate titles (2 or more identical names)
        const duplicateGroups = Array.from(titleGroups.entries()).filter(([title, group]) => group.length >= 2);

        if (duplicateGroups.length === 0) {
            const contextMsg = isFromChecked ? `ក្នុងចំណោមចម្រៀងដែលបានធិកទាំង ${songs.length} បទ` : 'ក្នុង Feed';
            showToast(`✅ ${contextMsg} គ្មានឈ្មោះជាន់គ្នាឡើយ! (គ្រប់បទសុទ្ធតែមានឈ្មោះប្លែកពីគ្នាស្រេច)`, 'success');
            return 0;
        }

        const scopeLabel = isFromChecked ? 'ក្នុងចំណោមចម្រៀងដែលបានធិក' : 'ក្នុង Feed';
        showToast(`🎯 រកឃើញបទភ្លោះចំនួន ${duplicateGroups.length} គូ ${scopeLabel}! កំពុងឱ្យ AI ប្តូរឈ្មោះបទទី ២ ចេញ...`, 'info');

        let renamedCount = 0;
        let processedClipIds = new Set();
        try {
            processedClipIds = new Set(JSON.parse(localStorage.getItem('suno_renamed_duplicate_clips') || '[]'));
        } catch (e) {}

        for (const [dupTitle, group] of duplicateGroups) {
            // Keep Track 1 (group[0]) with the original title!
            // Rename Track 2..N: "ប្តូរឈ្មោះ១ចេញ"
            for (let i = 1; i < group.length; i++) {
                const targetClip = group[i];

                showToast(`🪄 AI កំពុងបង្កើតចំណងជើងថ្មីស៊ីសង្វាក់សម្រាប់បទទី ២ នៃ "${dupTitle}"...`, 'info');
                const newSisterTitle = await generateCohesiveSisterTitle(dupTitle);
                if (!newSisterTitle || newSisterTitle === dupTitle) continue;

                showToast(`🪄 AI កំពុងប្តូរឈ្មោះបទទី ២៖\n"${dupTitle}"\n➡️ "${newSisterTitle}"`, 'info');

                const ok = await renameSunoClip(targetClip.id, newSisterTitle);
                if (ok) {
                    renamedCount++;
                    processedClipIds.add(targetClip.id);

                    // Update UI in real-time
                    if (targetClip.card) {
                        const h = targetClip.card.querySelector('h1, h2, h3, h4, a[href*="/song/"]');
                        if (h) h.innerText = newSisterTitle;
                    }
                    if (targetClip.checkbox) {
                        targetClip.checkbox.setAttribute('aria-label', `Select ${newSisterTitle}`);
                    }
                    targetClip.title = newSisterTitle;
                    await sleep(400);
                }
            }
        }

        try {
            localStorage.setItem('suno_renamed_duplicate_clips', JSON.stringify(Array.from(processedClipIds).slice(-100)));
        } catch (e) {}

        if (renamedCount > 0) {
            showToast(`🎉 ជោគជ័យ! បានប្តូរឈ្មោះបទទី ២ ចំនួន ${renamedCount} បទ ${scopeLabel} ដោយ AI ស៊ីសង្វាក់ជាមួយចំណងជើងចាស់ ១០០%! 🚀`, 'success');
        } else {
            showToast('ℹ️ គ្រប់បទភ្លោះទាំងអស់ត្រូវបានកែសម្រួលរួចរាល់ហើយ។', 'info');
        }

        return renamedCount;
    }

    let isDedupScanning = false;
    async function autoCheckAndDedupSiblingClips() {
        if (isDedupScanning) return;
        const autoDedupEnabled = localStorage.getItem('suno_auto_dedup_titles') !== 'false';
        if (!autoDedupEnabled) return;

        const songs = getFeedSongsList().slice(0, 6);
        if (songs.length < 2) return;

        let renamedSet = new Set();
        try {
            renamedSet = new Set(JSON.parse(localStorage.getItem('suno_renamed_duplicate_clips') || '[]'));
        } catch (e) {}

        for (let i = 0; i < songs.length - 1; i++) {
            const s1 = songs[i];
            const s2 = songs[i + 1];
            if (s1.title && s1.title === s2.title && s1.id !== s2.id && !renamedSet.has(s2.id) && !activeRenamingSet.has(s2.id)) {
                isDedupScanning = true;
                activeRenamingSet.add(s2.id);
                try {
                    showToast(`🪄 AI បានរកឃើញបទភ្លោះថ្មីៗ៖ "${s1.title}"! កំពុងបង្កើតឈ្មោះថ្មីស៊ីសង្វាក់...`, 'info');
                    const sisterTitle = await generateCohesiveSisterTitle(s1.title);
                    if (sisterTitle && sisterTitle !== s1.title) {
                        const ok = await renameSunoClip(s2.id, sisterTitle);
                        if (ok) {
                            renamedSet.add(s2.id);
                            localStorage.setItem('suno_renamed_duplicate_clips', JSON.stringify(Array.from(renamedSet).slice(-100)));
                            showToast(`✨ AI បានប្តូរឈ្មោះបទទី២៖\n"${s1.title}"\n➡️ "${sisterTitle}" ជោគជ័យ!`, 'success');
                        }
                    }
                } catch (err) {
                    console.warn('[Auto-Dedup] Error in autoCheckAndDedupSiblingClips:', err);
                } finally {
                    isDedupScanning = false;
                }
                break;
            }
        }
    }

    window.renameDuplicateSiblingClips = renameDuplicateSiblingClips;
    window.renameSunoClip = renameSunoClip;
    window.generateCohesiveSisterTitle = generateCohesiveSisterTitle;

    function openPlaylistDownloaderApp(url) {
        const targetUrl = url || 'https://suno.com/playlist/059caa04-8eb7-4cbc-884d-66198d5f286f';
        if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage(JSON.stringify({
                action: 'open_playlist_downloader',
                url: targetUrl
            }));
            showToast('📦 កំពុងបើកកម្មវិធី Suno Playlist Downloader...', 'success');
        } else {
            showToast('📦 កំពុងដំណើរការទាញយក Playlist...', 'info');
        }
    }
    window.openPlaylistDownloaderApp = openPlaylistDownloaderApp;

    // Floating Playlist ZIP Downloader Button on suno.com/playlist/*
    function checkAndInjectPlaylistFab() {
        if (!window.location.pathname.includes('/playlist/')) {
            const existing = document.getElementById('suno-playlist-floating-dl-btn');
            if (existing) existing.remove();
            return;
        }
        if (document.getElementById('suno-playlist-floating-dl-btn')) return;

        const fab = document.createElement('div');
        fab.id = 'suno-playlist-floating-dl-btn';
        fab.style.position = 'fixed';
        fab.style.bottom = '24px';
        fab.style.right = '24px';
        fab.style.zIndex = '999998';
        fab.innerHTML = `
            <button style="display:flex; align-items:center; gap:8px; background:linear-gradient(135deg, #ff5b38, #ff8a65); color:#ffffff; font-size:13px; font-weight:800; padding:12px 20px; border:none; border-radius:30px; cursor:pointer; box-shadow:0 6px 22px rgba(255,91,56,0.5); transition:all 0.25s ease;">
                <span style="font-size:18px;">📦</span>
                <span>ទាញយក PLAYLIST ជា FILE ZIP</span>
            </button>
        `;
        const btn = fab.querySelector('button');
        if (btn) {
            btn.addEventListener('mouseenter', () => {
                btn.style.transform = 'translateY(-2px) scale(1.03)';
                btn.style.boxShadow = '0 8px 26px rgba(255,91,56,0.75)';
            });
            btn.addEventListener('mouseleave', () => {
                btn.style.transform = 'translateY(0) scale(1)';
                btn.style.boxShadow = '0 6px 22px rgba(255,91,56,0.5)';
            });
            btn.addEventListener('click', () => {
                openPlaylistDownloaderApp(window.location.href);
            });
        }
        document.body.appendChild(fab);
    }
    setInterval(checkAndInjectPlaylistFab, 1500);
    window.addEventListener('popstate', checkAndInjectPlaylistFab);

    function createAutoLoopPanel() {
        if (document.getElementById('suno-auto-loop-panel')) return;

        const panel = document.createElement('div');
        panel.id = 'suno-auto-loop-panel';
        Object.assign(panel.style, {
            position: 'fixed',
            bottom: '135px',
            right: '24px',
            width: '460px',
            maxHeight: '85vh',
            overflowY: 'auto',
            zIndex: '999999',
            background: 'rgba(15, 15, 23, 0.95)',
            backdropFilter: 'blur(24px)',
            webkitBackdropFilter: 'blur(24px)',
            border: '1px solid rgba(139, 92, 246, 0.35)',
            borderRadius: '20px',
            boxShadow: '0 20px 50px rgba(0, 0, 0, 0.8), 0 0 20px rgba(139, 92, 246, 0.25)',
            padding: '18px 20px',
            color: '#f8fafc',
            fontFamily: 'system-ui, -apple-system, sans-serif',
            display: 'none',
            flexDirection: 'column',
            gap: '14px',
            transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)'
        });

        panel.innerHTML = `
            <!-- Header -->
            <div style="display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid rgba(255,255,255,0.1); padding-bottom:10px;">
                <div style="display:flex; align-items:center; gap:10px;">
                    <div style="width:36px; height:36px; border-radius:10px; background:linear-gradient(135deg, #8b5cf6, #ec4899); display:flex; align-items:center; justify-content:center; font-size:18px; box-shadow:0 4px 12px rgba(139,92,246,0.4);">
                        🔁
                    </div>
                    <div>
                        <div style="font-size:15px; font-weight:800; color:#ffffff; letter-spacing:0.3px;">Suno Auto-Loop Producer</div>
                        <div style="font-size:11px; color:#a78bfa;">ប្រព័ន្ធបង្កើតចម្រៀងវិលជុំស្វ័យប្រវត្តិតាមលក្ខខណ្ឌ</div>
                    </div>
                </div>
                <button id="suno-loop-close-btn" style="background:rgba(255,255,255,0.08); border:none; border-radius:8px; width:28px; height:28px; color:#94a3b8; font-size:14px; cursor:pointer; display:flex; align-items:center; justify-content:center;">✕</button>
            </div>

            <!-- Current Step & Live Status Banner -->
            <div style="background:rgba(26, 20, 42, 0.8); border:1px solid rgba(139,92,246,0.3); border-radius:12px; padding:12px 14px;">
                <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:6px;">
                    <span style="font-size:11px; font-weight:700; color:#c4b5fd; text-transform:uppercase; letter-spacing:0.5px;">ស្ថានភាពបច្ចុប្បន្ន (Live Status)</span>
                    <span id="suno-loop-badge-live" style="font-size:10px; font-weight:800; padding:2px 8px; border-radius:10px; background:rgba(239,68,68,0.2); color:#fca5a5; border:1px solid rgba(239,68,68,0.35);">STOPPED</span>
                </div>
                <div id="suno-loop-status-text" style="font-size:13px; font-weight:700; color:#ffffff; line-height:1.4;">🟢 ត្រៀមរួចរាល់សម្រាប់ដំណើរការ</div>
            </div>

            <!-- 5-Step Visual Workflow Pipeline -->
            <div style="display:flex; flex-direction:column; gap:6px; background:rgba(255,255,255,0.03); border-radius:12px; padding:10px 12px; border:1px solid rgba(255,255,255,0.06);">
                <div style="font-size:11px; font-weight:700; color:#94a3b8; margin-bottom:2px;">លំហូរការងារវិលជុំទាំង ៥ ជំហាន (5-Step Auto-Loop Pipeline)</div>
                <div id="suno-step-item-1" style="display:flex; align-items:center; gap:8px; font-size:12px; padding:5px 8px; border-radius:8px; color:#cbd5e1; transition:all 0.2s;">
                    <span style="font-size:14px;">1️⃣</span>
                    <span style="font-weight:600;">✨ បង្កើត Title</span>
                </div>
                <div id="suno-step-item-2" style="display:flex; align-items:center; gap:8px; font-size:12px; padding:5px 8px; border-radius:8px; color:#cbd5e1; transition:all 0.2s;">
                    <span style="font-size:14px;">2️⃣</span>
                    <span style="font-weight:600;">🎵 បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីលបទភ្លេង ឡើងវិញ</span>
                </div>
                <div id="suno-step-item-3" style="display:flex; align-items:center; gap:8px; font-size:12px; padding:5px 8px; border-radius:8px; color:#cbd5e1; transition:all 0.2s;">
                    <span style="font-size:14px;">3️⃣</span>
                    <span style="font-weight:600;">🗑️ លុប Lyrics + Styles + Song Title (Optional) ចេញ</span>
                </div>
                <div id="suno-step-item-4" style="display:flex; align-items:center; gap:8px; font-size:12px; padding:5px 8px; border-radius:8px; color:#cbd5e1; transition:all 0.2s;">
                    <span style="font-size:14px;">4️⃣</span>
                    <span style="font-weight:600;">🔍 ស្កេន វិភាគមើលប៊ូតុង Create (ដល់កំណត់/នាទីរង់ចាំ)</span>
                </div>
                <div id="suno-step-item-5" style="display:flex; align-items:center; gap:8px; font-size:12px; padding:5px 8px; border-radius:8px; color:#cbd5e1; transition:all 0.2s;">
                    <span style="font-size:14px;">5️⃣</span>
                    <span style="font-weight:600;">⏳ ស្កេន វិភាគមើលផ្ទាំង Today (អតិបរមា ៤ បទក្នុងម្តង)</span>
                </div>
            </div>

            <!-- Metrics Grid -->
            <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px;">
                <div style="background:rgba(255,255,255,0.04); border-radius:10px; padding:8px 10px; border:1px solid rgba(255,255,255,0.08);">
                    <div style="font-size:10px; color:#94a3b8;">ជុំដែលបានបង្កើត (Loops)</div>
                    <div id="suno-metric-loops" style="font-size:16px; font-weight:800; color:#38bdf8; margin-top:2px;">0 ជុំ</div>
                </div>
                <div style="background:rgba(255,255,255,0.04); border-radius:10px; padding:8px 10px; border:1px solid rgba(255,255,255,0.08);">
                    <div style="font-size:10px; color:#94a3b8;">កំពុងបង្កើតក្នុង Today</div>
                    <div id="suno-metric-today" style="font-size:16px; font-weight:800; color:#fbbf24; margin-top:2px;">0 / 4 បទ</div>
                </div>
                <div style="background:rgba(255,255,255,0.04); border-radius:10px; padding:8px 10px; border:1px solid rgba(255,255,255,0.08);">
                    <div style="font-size:10px; color:#94a3b8;">ស្ថានភាពប៊ូតុង Create</div>
                    <div id="suno-metric-create" style="font-size:13px; font-weight:700; color:#34d399; margin-top:4px;">🟢 រួចរាល់</div>
                </div>
                <div style="background:rgba(255,255,255,0.04); border-radius:10px; padding:8px 10px; border:1px solid rgba(255,255,255,0.08);">
                    <div style="font-size:10px; color:#94a3b8;">រង់ចាំ Cooldown</div>
                    <div id="suno-metric-cooldown" style="font-size:14px; font-weight:800; color:#e2e8f0; margin-top:4px;">—</div>
                </div>
            </div>

            <!-- Action Controls -->
            <div style="display:flex; flex-direction:column; gap:8px;">
                <div style="display:flex; gap:8px;">
                    <button id="suno-loop-btn-start" style="flex:2; background:linear-gradient(135deg, #8b5cf6, #7c3aed); border:none; border-radius:12px; color:#ffffff; font-size:13px; font-weight:800; padding:10px 14px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:8px; box-shadow:0 4px 14px rgba(139,92,246,0.4);">
                        <span>▶️</span>
                        <span>ចាប់ផ្តើមវិលជុំស្វ័យប្រវត្តិ</span>
                    </button>
                    <button id="suno-loop-btn-pause" style="flex:1; background:rgba(245,158,11,0.15); border:1px solid rgba(245,158,11,0.4); border-radius:12px; color:#fbbf24; font-size:12px; font-weight:700; padding:10px; cursor:pointer; display:none; align-items:center; justify-content:center; gap:5px;">
                        <span>⏸️</span>
                        <span>ផ្អាក</span>
                    </button>
                    <button id="suno-loop-btn-stop" style="flex:1; background:rgba(239,68,68,0.15); border:1px solid rgba(239,68,68,0.4); border-radius:12px; color:#fca5a5; font-size:12px; font-weight:700; padding:10px; cursor:pointer; display:none; align-items:center; justify-content:center; gap:5px;">
                        <span>⏹️</span>
                        <span>បញ្ឈប់</span>
                    </button>
                </div>

                <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px;">
                    <button id="suno-loop-btn-gen-title" style="background:rgba(139,92,246,0.12); border:1px solid rgba(139,92,246,0.3); border-radius:8px; color:#c4b5fd; font-size:11px; font-weight:600; padding:8px 6px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;">
                        <span>✨</span>
                        <span>Title (ជំហានទី ១)</span>
                    </button>
                    <button id="suno-loop-btn-compose" style="background:rgba(16,185,129,0.12); border:1px solid rgba(16,185,129,0.3); border-radius:8px; color:#6ee7b7; font-size:11px; font-weight:600; padding:8px 6px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;">
                        <span>🎵</span>
                        <span>និពន្ធចម្រៀង (ជំហានទី ២)</span>
                    </button>
                </div>
                <div style="display:grid; grid-template-columns:1.2fr 1fr; gap:6px; margin-top:4px;">
                    <button id="suno-loop-btn-clear-lyrics" style="background:rgba(239,68,68,0.15); border:1px solid rgba(239,68,68,0.4); border-radius:8px; color:#fca5a5; font-size:11px; font-weight:700; padding:8px 6px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;">
                        <span>🗑️</span>
                        <span>លុប Lyrics ភ្លាមៗ (Step 3)</span>
                    </button>
                    <button id="suno-loop-btn-clear" style="background:rgba(239,68,68,0.08); border:1px solid rgba(239,68,68,0.25); border-radius:8px; color:#fca5a5; font-size:11px; font-weight:600; padding:8px 6px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;">
                        <span>🧹</span>
                        <span>លុបសម្អាតទាំងអស់</span>
                    </button>
                </div>

                <!-- Suno Model Switcher Row -->
                <div style="background:rgba(255,255,255,0.03); border:1px solid #2d2d38; border-radius:10px; padding:7px 9px; margin-top:6px;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:5px;">
                        <span style="font-size:10px; color:#a1a1aa; text-transform:uppercase; font-weight:700; letter-spacing:0.5px;">🤖 ម៉ូឌែល SUNO AI:</span>
                        <span id="suno-current-model-badge" style="font-size:10px; background:#2d2d38; color:#ec4899; padding:2px 6px; border-radius:4px; font-weight:700;">v6-mini</span>
                    </div>
                    <div style="display:grid; grid-template-columns:1.2fr 1fr 1fr; gap:4px;">
                        <button id="suno-btn-model-v6wild" style="background:linear-gradient(135deg, rgba(236,72,153,0.18), rgba(168,85,247,0.18)); border:1px solid rgba(236,72,153,0.45); border-radius:6px; color:#f472b6; font-size:10px; font-weight:700; padding:6px 2px; cursor:pointer;" title="Suno v6-wild Pro (Experimental ideas)">
                            ⚡ v6-wild Pro
                        </button>
                        <button id="suno-btn-model-v6pro" style="background:rgba(59,130,246,0.12); border:1px solid rgba(59,130,246,0.35); border-radius:6px; color:#93c5fd; font-size:10px; font-weight:700; padding:6px 2px; cursor:pointer;" title="Suno v6 Pro (Best model)">
                            ✨ v6 Pro
                        </button>
                        <button id="suno-btn-model-v6mini" style="background:rgba(16,185,129,0.12); border:1px solid rgba(16,185,129,0.35); border-radius:6px; color:#6ee7b7; font-size:10px; font-weight:700; padding:6px 2px; cursor:pointer;" title="Suno v6-mini (Free default)">
                            🌱 v6-mini
                        </button>
                    </div>
                </div>

                <!-- 🌐 Song Language Selection (កំណត់ភាសានិពន្ធចម្រៀង គ្រប់ភាសាទាំងអស់) -->
                <div style="background:rgba(255,255,255,0.03); border:1px solid #2d2d38; border-radius:10px; padding:7px 9px; margin-top:6px;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:5px;">
                        <span style="font-size:10px; color:#ffedd5; font-weight:700; letter-spacing:0.3px;">🌐 ភាសានិពន្ធចម្រៀង (ALL LANGUAGES):</span>
                        <span id="suno-loop-current-lang-badge" style="font-size:10px; background:#2d2d38; color:#f97316; padding:1px 6px; border-radius:4px; font-weight:700;">${getSongLanguageConfig().name.split('(')[0].trim()}</span>
                    </div>
                    <div style="display:flex; gap:4px;">
                        <select id="suno-loop-language-select" style="flex:1; padding:5px 8px; background:#141520; border:1px solid #3d2d48; border-radius:6px; color:#ffffff; font-size:11px; outline:none;">
                            ${renderLanguageOptions(localStorage.getItem('suno_song_language') || 'km')}
                        </select>
                        <input id="suno-loop-custom-lang-input" type="text" placeholder="វាយភាសា... (ឧ. Arabic)" style="display:${localStorage.getItem('suno_song_language') === 'custom' ? 'block' : 'none'}; flex:1; padding:5px 8px; background:#141520; border:1px solid #f97316; border-radius:6px; color:#ffffff; font-size:11px; outline:none;" value="${localStorage.getItem('suno_custom_language_name') || ''}" />
                    </div>
                </div>

                <!-- ⏱️ Song Duration Controller Card (កំណត់នាទី ចម្រៀង) -->
                <div id="suno-duration-card-loop" style="background:rgba(20, 24, 38, 0.85); border:1px solid rgba(56, 189, 248, 0.35); border-radius:12px; padding:10px 12px; margin-top:8px; display:flex; flex-direction:column; gap:7px;">
                    <div style="display:flex; justify-content:space-between; align-items:center;">
                        <div style="display:flex; align-items:center; gap:6px;">
                            <span style="font-size:13px;">⏱️</span>
                            <span style="font-size:11px; font-weight:800; color:#bae6fd; letter-spacing:0.3px;">កំណត់នាទីចម្រៀង (SONG DURATION):</span>
                        </div>
                        <span id="suno-current-duration-badge" style="font-size:10px; font-weight:800; padding:2px 8px; border-radius:10px; background:rgba(255,255,255,0.06); color:#a5b4fc; border:1px solid rgba(165,180,252,0.3);">⚡ Auto</span>
                    </div>

                    <!-- Duration Presets (Auto, 2m, 3m, 4m, 5m, 6m) -->
                    <div style="display:grid; grid-template-columns:repeat(6, 1fr); gap:4px;">
                        <button id="suno-btn-dur-auto" style="background:rgba(148,163,184,0.15); border:1px solid rgba(148,163,184,0.35); border-radius:6px; color:#cbd5e1; font-size:10px; font-weight:700; padding:5px 0; cursor:pointer;" title="កំណត់ស្វ័យប្រវត្តិតាម Suno (Auto default)">
                            Auto
                        </button>
                        <button id="suno-btn-dur-2m" style="background:rgba(56,189,248,0.12); border:1px solid rgba(56,189,248,0.35); border-radius:6px; color:#7dd3fc; font-size:10px; font-weight:700; padding:5px 0; cursor:pointer;" title="កំណត់រយៈពេល ២ នាទី (2:00)">
                            2:00
                        </button>
                        <button id="suno-btn-dur-3m" style="background:rgba(59,130,246,0.15); border:1px solid rgba(59,130,246,0.4); border-radius:6px; color:#93c5fd; font-size:10px; font-weight:700; padding:5px 0; cursor:pointer;" title="កំណត់រយៈពេល ៣ នាទី (3:00)">
                            3:00
                        </button>
                        <button id="suno-btn-dur-4m" style="background:linear-gradient(135deg, rgba(236,72,153,0.2), rgba(168,85,247,0.2)); border:1px solid rgba(236,72,153,0.45); border-radius:6px; color:#f472b6; font-size:10px; font-weight:800; padding:5px 0; cursor:pointer;" title="កំណត់រយៈពេល ៤ នាទី (4:00 - Standard)">
                            4:00
                        </button>
                        <button id="suno-btn-dur-5m" style="background:rgba(168,85,247,0.15); border:1px solid rgba(168,85,247,0.4); border-radius:6px; color:#d8b4fe; font-size:10px; font-weight:700; padding:5px 0; cursor:pointer;" title="កំណត់រយៈពេល ៥ នាទី (5:00)">
                            5:00
                        </button>
                        <button id="suno-btn-dur-6m" style="background:rgba(239,68,68,0.12); border:1px solid rgba(239,68,68,0.35); border-radius:6px; color:#fca5a5; font-size:10px; font-weight:700; padding:5px 0; cursor:pointer;" title="កំណត់រយៈពេល ៦ នាទី (6:00 - Max)">
                            6:00
                        </button>
                    </div>

                    <!-- Slider & Manual Entry -->
                    <div style="display:flex; align-items:center; gap:8px; margin-top:2px;">
                        <input id="suno-dur-slider" type="range" min="10" max="360" step="5" value="240" style="flex:1; accent-color:#38bdf8; cursor:pointer; height:4px;" title="អូសកំណត់នាទី (១០ វិនាទី ដល់ ៦ នាទី)">
                        <span id="suno-dur-display" style="font-size:11px; font-weight:800; color:#38bdf8; min-width:32px; text-align:right;">4:00</span>
                        <button id="suno-btn-dur-apply" style="background:rgba(56,189,248,0.2); border:1px solid rgba(56,189,248,0.5); border-radius:6px; color:#e0f2fe; font-size:10px; font-weight:700; padding:4px 8px; cursor:pointer;" title="អនុវត្តរយៈពេលចម្រៀងចូល Suno ផ្ទាល់">
                            កំណត់
                        </button>
                    </div>
                </div>

                <!-- Auto Batch Selection & Playlist Creator Card (10, 14, 18 Tracks) -->
                <div id="suno-playlist-card-loop" style="background:rgba(26, 20, 42, 0.85); border:1px solid rgba(168, 85, 247, 0.35); border-radius:12px; padding:12px 14px; margin-top:8px; display:flex; flex-direction:column; gap:8px;">
                    <div style="display:flex; justify-content:space-between; align-items:center;">
                        <div style="display:flex; align-items:center; gap:6px;">
                            <span style="font-size:14px;">📁</span>
                            <span style="font-size:12px; font-weight:800; color:#e9d5ff; letter-spacing:0.3px;">ជ្រើសរើសចម្រៀង & បង្កើត PLAYLIST</span>
                        </div>
                        <span id="suno-playlist-selected-badge" style="font-size:10px; font-weight:800; padding:2px 8px; border-radius:10px; background:rgba(255,255,255,0.06); color:#94a3b8; border:1px solid rgba(255,255,255,0.1);">បានធិក 0 បទ</span>
                    </div>

                    <!-- Batch Presets (10, 14, 18, Clear) -->
                    <div style="display:grid; grid-template-columns:1fr 1.1fr 1fr 1fr; gap:5px;">
                        <button id="suno-btn-select-10" style="background:rgba(139,92,246,0.15); border:1px solid rgba(139,92,246,0.4); border-radius:8px; color:#c4b5fd; font-size:11px; font-weight:700; padding:7px 2px; cursor:pointer;" title="ធិកជ្រើសរើសចម្រៀង 10 បទ">
                            ☑️ 10 បទ
                        </button>
                        <button id="suno-btn-select-14" style="background:linear-gradient(135deg, rgba(168,85,247,0.25), rgba(236,72,153,0.25)); border:1px solid rgba(168,85,247,0.5); border-radius:8px; color:#f472b6; font-size:11px; font-weight:800; padding:7px 2px; cursor:pointer; box-shadow:0 2px 6px rgba(168,85,247,0.2);" title="ធិកជ្រើសរើសចម្រៀង 14 បទ (ស្តង់ដារ Playlist)">
                            ⭐ 14 បទ
                        </button>
                        <button id="suno-btn-select-18" style="background:rgba(59,130,246,0.15); border:1px solid rgba(59,130,246,0.4); border-radius:8px; color:#93c5fd; font-size:11px; font-weight:700; padding:7px 2px; cursor:pointer;" title="ធិកជ្រើសរើសចម្រៀង 18 បទ">
                            ☑️ 18 បទ
                        </button>
                        <button id="suno-btn-deselect-all" style="background:rgba(239,68,68,0.1); border:1px solid rgba(239,68,68,0.3); border-radius:8px; color:#fca5a5; font-size:10px; font-weight:600; padding:7px 2px; cursor:pointer;" title="ដោះការធិកទាំងអស់">
                            🔄 ដោះធិក
                        </button>
                    </div>

                    <!-- Playlist Name Input Row -->
                    <div style="display:flex; gap:6px;">
                        <input id="suno-playlist-name-input" type="text" placeholder="ឈ្មោះ Playlist (ឧ. Khmer Hits 2026)..." style="flex:1; background:rgba(15,15,23,0.8); border:1px solid rgba(168,85,247,0.3); border-radius:8px; padding:7px 10px; font-size:11px; color:#ffffff; outline:none;" />
                        <button id="suno-btn-playlist-smart-name" style="background:rgba(139,92,246,0.2); border:1px solid rgba(139,92,246,0.4); border-radius:8px; color:#c4b5fd; font-size:11px; font-weight:700; padding:0 8px; cursor:pointer;" title="បង្កើតឈ្មោះឆ្លាតវៃថ្មី">
                            ✨ ឈ្មោះថ្មី
                        </button>
                    </div>

                    <!-- Action Button: Create & Add -->
                    <button id="suno-btn-auto-add-playlist" style="background:linear-gradient(135deg, #10b981, #059669); border:none; border-radius:10px; color:#ffffff; font-size:12px; font-weight:800; padding:9px 12px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:6px; box-shadow:0 3px 10px rgba(16,185,129,0.35);">
                        <span>🚀</span>
                        <span>បង្កើត Playlist ថ្មី & Add ស្វ័យប្រវត្តិ</span>
                    </button>

                    <!-- Sibling Pair Cohesive Rename Card (100% Automated by AI) -->
                    <div style="background:rgba(15, 23, 42, 0.7); border:1px solid rgba(56, 189, 248, 0.3); border-radius:10px; padding:9px 10px; margin-top:6px; display:flex; flex-direction:column; gap:6px;">
                        <div style="display:flex; justify-content:space-between; align-items:center;">
                            <div style="display:flex; align-items:center; gap:5px;">
                                <span style="font-size:13px;">🪄</span>
                                <span style="font-size:11px; font-weight:800; color:#38bdf8;">ប្តូរឈ្មោះបទភ្លោះ ដោយ AI</span>
                            </div>
                            <label style="display:flex; align-items:center; gap:5px; cursor:pointer; font-size:10px; color:#93c5fd;">
                                <span>ស្វ័យប្រវត្តិ</span>
                                <input type="checkbox" id="suno-auto-dedup-chk" ${localStorage.getItem('suno_auto_dedup_titles') !== 'false' ? 'checked' : ''} style="accent-color:#38bdf8; cursor:pointer;" />
                            </label>
                        </div>
                        <div style="font-size:10px; color:#94a3b8; line-height:1.35;">
                            ពេលបង្កើតចេញ ២ បទឈ្មោះដូចគ្នា AI នឹងចាប់យកបទទី ២ មកកែឈ្មោះថ្មីអោយស៊ីសង្វាក់ជាមួយបទទី ១។
                        </div>
                        <button id="suno-btn-dedup-now" style="background:linear-gradient(135deg, rgba(14,165,233,0.25), rgba(59,130,246,0.25)); border:1px solid rgba(56,189,248,0.45); border-radius:8px; color:#7dd3fc; font-size:11px; font-weight:700; padding:6px 10px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;" title="ស្កេន និងប្តូរឈ្មោះបទភ្លោះក្នុង Feed ឥឡូវនេះ">
                            <span>🪄</span>
                            <span>ប្តូរឈ្មោះបទភ្លោះក្នុង Feed ឥឡូវនេះ</span>
                        </button>
                    </div>

                    <!-- 📦 Playlist Zip Downloader Card (កម្មវិធីទាញយកចម្រៀង File Zip ពី Playlist) -->
                    <div id="suno-playlist-zip-card" style="background:rgba(23, 26, 40, 0.95); border:1px solid rgba(255, 110, 80, 0.55); border-radius:10px; padding:12px; margin-top:8px; display:flex; flex-direction:column; gap:8px; box-shadow:0 4px 15px rgba(0,0,0,0.35);">
                        <div style="display:flex; justify-content:space-between; align-items:center;">
                            <div style="display:flex; align-items:center; gap:6px;">
                                <span style="font-size:16px;">📦</span>
                                <span style="font-size:12px; font-weight:800; color:#ff7a59; letter-spacing:0.3px;">ទាញយក PLAYLIST ជា FILE ZIP</span>
                            </div>
                            <span style="font-size:9.5px; font-weight:800; padding:3px 7px; border-radius:6px; background:rgba(255,110,80,0.18); color:#ff9f87; border:1px solid rgba(255,110,80,0.35);">MP3 320k HQ</span>
                        </div>
                        <div style="font-size:10.5px; color:#cbd5e1; line-height:1.4;">
                            ទាញយកចម្រៀងទាំងមូលពី Suno Playlist ដោះកូដជា MP3 (320kbps) រួមទាំង Cover & Lyrics វេចខ្ចប់ជា ZIP។
                        </div>
                        <div style="display:flex; gap:8px; align-items:center;">
                            <button id="suno-btn-launch-pl-downloader" style="flex:1; background:linear-gradient(135deg, #ff5b38, #ff8a65); border:none; border-radius:8px; color:#ffffff; font-size:12px; font-weight:800; padding:10px 14px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:6px; box-shadow:0 4px 14px rgba(255,91,56,0.4); transition:all 0.2s ease;">
                                <span style="font-size:14px;">📦</span>
                                <span>បើកកម្មវិធី Playlist Downloader</span>
                            </button>
                            <button id="suno-btn-quick-dl-target-pl" style="background:rgba(255,255,255,0.08); border:1px solid rgba(255,255,255,0.22); border-radius:8px; color:#ffffff; font-size:11px; font-weight:800; padding:10px 12px; cursor:pointer; display:flex; align-items:center; gap:4px; transition:all 0.2s ease;" title="ទាញយក Playlist Target (10 Tracks) ជា File ZIP">
                                <span>⚡</span>
                                <span>ទាញយក ZIP</span>
                            </button>
                        </div>
                    </div>

                    <!-- 🖥️ Desktop System Tray & Startup Settings Card -->
                    <div id="suno-desktop-settings-card" style="background:rgba(20, 20, 32, 0.9); border:1px solid rgba(139, 92, 246, 0.35); border-radius:10px; padding:10px 12px; margin-top:8px; display:flex; flex-direction:column; gap:7px;">
                        <div style="display:flex; justify-content:space-between; align-items:center;">
                            <div style="display:flex; align-items:center; gap:6px;">
                                <span style="font-size:14px;">🖥️</span>
                                <span style="font-size:11px; font-weight:800; color:#c4b5fd; letter-spacing:0.3px;">ការកំណត់ DESKTOP APP:</span>
                            </div>
                            <span style="font-size:9.5px; font-weight:800; padding:2px 6px; border-radius:6px; background:rgba(139,92,246,0.18); color:#ddd6fe; border:1px solid rgba(139,92,246,0.35);">ELECTRON</span>
                        </div>
                        <div style="display:flex; flex-direction:column; gap:6px; font-size:11px;">
                            <label style="display:flex; align-items:center; justify-content:space-between; cursor:pointer; color:#e2e8f0;">
                                <span style="display:flex; align-items:center; gap:6px;">
                                    <span>🌟</span>
                                    <span>ពេលបិទពី Taskbar ឱ្យបន្តដំណើរការ (Close to Tray)</span>
                                </span>
                                <input type="checkbox" id="suno-chk-close-tray" checked style="accent-color:#8b5cf6; width:15px; height:15px; cursor:pointer;" />
                            </label>
                            <label style="display:flex; align-items:center; justify-content:space-between; cursor:pointer; color:#e2e8f0;">
                                <span style="display:flex; align-items:center; gap:6px;">
                                    <span>🚀</span>
                                    <span>ដំណើរការស្វ័យប្រវត្តពេលបើកកុំព្យូទ័រ (Run on Startup)</span>
                                </span>
                                <input type="checkbox" id="suno-chk-run-startup" checked style="accent-color:#10b981; width:15px; height:15px; cursor:pointer;" />
                            </label>
                        </div>
                    </div>
                </div>
            </div>
        `;

        document.body.appendChild(panel);

        // Events
        document.getElementById('suno-auto-dedup-chk')?.addEventListener('change', (e) => {
            const en = e.target.checked;
            localStorage.setItem('suno_auto_dedup_titles', en ? 'true' : 'false');
            showToast(en ? '✨ បានបើកមុខងារប្តូរឈ្មោះបទភ្លោះស្វ័យប្រវត្តិដោយ AI' : '🔇 បានបិទមុខងារប្តូរឈ្មោះបទភ្លោះស្វ័យប្រវត្តិ', en ? 'success' : 'warn');
        });

        document.getElementById('suno-btn-dedup-now')?.addEventListener('click', async () => {
            await renameDuplicateSiblingClips();
        });

        document.getElementById('suno-btn-launch-pl-downloader')?.addEventListener('click', () => {
            openPlaylistDownloaderApp();
        });

        document.getElementById('suno-btn-quick-dl-target-pl')?.addEventListener('click', () => {
            openPlaylistDownloaderApp('https://suno.com/playlist/059caa04-8eb7-4cbc-884d-66198d5f286f');
        });

        // Desktop Settings Events (Close to Tray & Run on Startup)
        const closeTrayChk = document.getElementById('suno-chk-close-tray');
        const runStartupChk = document.getElementById('suno-chk-run-startup');

        if (window.sunoDesktop) {
            window.sunoDesktop.getSettings().then(cfg => {
                if (closeTrayChk && cfg) closeTrayChk.checked = cfg.closeToTray;
                if (runStartupChk && cfg) runStartupChk.checked = cfg.runOnStartup;
            }).catch(() => {});
        }

        closeTrayChk?.addEventListener('change', (e) => {
            const val = e.target.checked;
            if (window.sunoDesktop) {
                window.sunoDesktop.toggleCloseToTray();
            } else if (window.chrome?.webview?.postMessage) {
                window.chrome.webview.postMessage(JSON.stringify({ action: 'set_desktop_settings', closeToTray: val }));
            }
            showToast(val ? '🌟 បានបើកមុខងារបិទទៅ System Tray (កម្មវិធីនៅដំណើរការ)' : '⚠️ បានបិទមុខងារ System Tray (ចុច X នឹងបិទកម្មវិធីទាំងស្រុង)', val ? 'success' : 'warn');
        });

        runStartupChk?.addEventListener('change', (e) => {
            const val = e.target.checked;
            if (window.sunoDesktop) {
                window.sunoDesktop.toggleRunOnStartup();
            } else if (window.chrome?.webview?.postMessage) {
                window.chrome.webview.postMessage(JSON.stringify({ action: 'set_desktop_settings', runOnStartup: val }));
            }
            showToast(val ? '🚀 បានបើកមុខងារ Run On Startup (ដំណើរការស្វ័យប្រវត្តពេលបើកម៉ាស៊ីន)' : '🔇 បានបិទមុខងារ Run On Startup', val ? 'success' : 'warn');
        });

        // Events
        document.getElementById('suno-loop-close-btn')?.addEventListener('click', () => {
            panel.style.display = 'none';
        });

        document.getElementById('suno-loop-btn-start')?.addEventListener('click', () => {
            window.sunoAutoLoop.start();
        });

        document.getElementById('suno-loop-btn-pause')?.addEventListener('click', () => {
            if (window.sunoAutoLoop.isPaused) {
                window.sunoAutoLoop.resume();
            } else {
                window.sunoAutoLoop.pause();
            }
        });

        document.getElementById('suno-loop-btn-stop')?.addEventListener('click', () => {
            window.sunoAutoLoop.stop();
        });

        document.getElementById('suno-loop-btn-clear-lyrics')?.addEventListener('click', () => {
            clearSunoLyricsOnly(false);
        });

        document.getElementById('suno-loop-btn-clear')?.addEventListener('click', () => {
            clearAllSunoFields(false);
        });

        document.getElementById('suno-loop-btn-gen-title')?.addEventListener('click', async () => {
            await generateFreshTitleOnly();
            showToast('✨ បានបង្កើត និងបញ្ចូល Title ថ្មីជោគជ័យ!', 'success');
        });

        document.getElementById('suno-loop-btn-compose')?.addEventListener('click', async () => {
            await generateSong();
            showToast('🎵 បាននិពន្ធ និងបញ្ចូលបទចម្រៀងឡើងវិញជោគជ័យ!', 'success');
        });

        document.getElementById('suno-btn-model-v6wild')?.addEventListener('click', () => switchSunoModel('v6-wild'));
        document.getElementById('suno-btn-model-v6pro')?.addEventListener('click', () => switchSunoModel('v6-pro'));
        document.getElementById('suno-btn-model-v6mini')?.addEventListener('click', () => switchSunoModel('v6-mini'));
        updateSunoModelBadge();

        // Language Select in Auto-Loop Panel
        const loopLangSel = document.getElementById('suno-loop-language-select');
        const loopCustomInp = document.getElementById('suno-loop-custom-lang-input');
        loopLangSel?.addEventListener('change', (e) => {
            const code = e.target.value;
            const customVal = loopCustomInp ? loopCustomInp.value.trim() : '';
            setSongLanguage(code, customVal, true);
        });
        loopCustomInp?.addEventListener('input', (e) => {
            setSongLanguage('custom', e.target.value.trim(), true);
        });

        // Duration Controls (Auto, 2m, 3m, 4m, 5m, 6m, Slider)
        document.getElementById('suno-btn-dur-auto')?.addEventListener('click', () => {
            resetSunoSongDurationToAuto();
            updateSunoDurationUI('auto');
            showToast('⚡ បានប្តូរទៅជារយៈពេល Auto (Default របស់ Suno)', 'info');
        });
        document.getElementById('suno-btn-dur-2m')?.addEventListener('click', async () => {
            await setSunoSongDuration(120);
            updateSunoDurationUI(120);
            showToast('⏱️ បានកំណត់រយៈពេល ២ នាទី (2:00 / 120s)', 'success');
        });
        document.getElementById('suno-btn-dur-3m')?.addEventListener('click', async () => {
            await setSunoSongDuration(180);
            updateSunoDurationUI(180);
            showToast('⏱️ បានកំណត់រយៈពេល ៣ នាទី (3:00 / 180s)', 'success');
        });
        document.getElementById('suno-btn-dur-4m')?.addEventListener('click', async () => {
            await setSunoSongDuration(240);
            updateSunoDurationUI(240);
            showToast('⏱️ បានកំណត់រយៈពេល ៤ នាទី (4:00 / 240s)', 'success');
        });
        document.getElementById('suno-btn-dur-5m')?.addEventListener('click', async () => {
            await setSunoSongDuration(300);
            updateSunoDurationUI(300);
            showToast('⏱️ បានកំណត់រយៈពេល ៥ នាទី (5:00 / 300s)', 'success');
        });
        document.getElementById('suno-btn-dur-6m')?.addEventListener('click', async () => {
            await setSunoSongDuration(360);
            updateSunoDurationUI(360);
            showToast('⏱️ បានកំណត់រយៈពេល ៦ នាទី (6:00 / 360s)', 'success');
        });

        const durSlider = document.getElementById('suno-dur-slider');
        const durDisplay = document.getElementById('suno-dur-display');
        durSlider?.addEventListener('input', (e) => {
            const val = parseInt(e.target.value, 10);
            if (durDisplay) durDisplay.innerText = formatSecondsToDurationString(val);
        });
        document.getElementById('suno-btn-dur-apply')?.addEventListener('click', async () => {
            const val = durSlider ? parseInt(durSlider.value, 10) : 240;
            await setSunoSongDuration(val);
            updateSunoDurationUI(val);
            showToast(`⏱️ បានកំណត់រយៈពេល ${formatSecondsToDurationString(val)} (${val}s)`, 'success');
        });
        updateSunoDurationUI();

        // Batch Playlist Events
        let currentBatchTarget = 14;

        document.getElementById('suno-btn-select-10')?.addEventListener('click', async () => {
            currentBatchTarget = 10;
            const input = document.getElementById('suno-playlist-name-input');
            const newName = await generateSmartPlaylistName(10);
            if (input) input.value = newName;
            updatePlaylistSelectionUI(10, newName);
            await selectBatchSongs(10);
        });

        document.getElementById('suno-btn-select-14')?.addEventListener('click', async () => {
            currentBatchTarget = 14;
            const input = document.getElementById('suno-playlist-name-input');
            const newName = await generateSmartPlaylistName(14);
            if (input) input.value = newName;
            updatePlaylistSelectionUI(14, newName);
            await selectBatchSongs(14);
        });

        document.getElementById('suno-btn-select-18')?.addEventListener('click', async () => {
            currentBatchTarget = 18;
            const input = document.getElementById('suno-playlist-name-input');
            const newName = await generateSmartPlaylistName(18);
            if (input) input.value = newName;
            updatePlaylistSelectionUI(18, newName);
            await selectBatchSongs(18);
        });

        document.getElementById('suno-btn-deselect-all')?.addEventListener('click', () => {
            deselectAllSongs();
        });

        document.getElementById('suno-btn-playlist-smart-name')?.addEventListener('click', async () => {
            const input = document.getElementById('suno-playlist-name-input');
            const newName = await generateSmartPlaylistName(currentBatchTarget);
            if (input) input.value = newName;
            updatePlaylistSelectionUI(currentlySelectedSongCount, newName);
            showToast(`✨ ឈ្មោះ Playlist ថ្មី៖ ${newName}`, 'info');
        });

        document.getElementById('suno-btn-auto-add-playlist')?.addEventListener('click', async () => {
            const input = document.getElementById('suno-playlist-name-input');
            let plName = (input && input.value) ? input.value.trim() : '';
            if (!plName) {
                plName = await generateSmartPlaylistName(currentBatchTarget);
                if (input) input.value = plName;
            }
            await createAndAddToPlaylist(plName, currentBatchTarget);
        });
    }

    function toggleAutoLoopPanel() {
        createAutoLoopPanel();
        const panel = document.getElementById('suno-auto-loop-panel');
        if (panel) {
            const isVisible = panel.style.display === 'flex';
            panel.style.display = isVisible ? 'none' : 'flex';
            updateAutoLoopUI();
        }
    }

    function updateAutoLoopUI() {
        const p = window.sunoAutoLoop;
        if (!p) return;

        const badge = document.getElementById('suno-loop-badge-live');
        const dockBadge = document.getElementById('suno-dock-loop-status');
        const statusText = document.getElementById('suno-loop-status-text');
        const metricLoops = document.getElementById('suno-metric-loops');
        const metricToday = document.getElementById('suno-metric-today');
        const metricCreate = document.getElementById('suno-metric-create');
        const metricCooldown = document.getElementById('suno-metric-cooldown');
        const startBtn = document.getElementById('suno-loop-btn-start');
        const pauseBtn = document.getElementById('suno-loop-btn-pause');
        const stopBtn = document.getElementById('suno-loop-btn-stop');

        if (statusText) statusText.textContent = p.statusText;
        if (metricLoops) metricLoops.textContent = `${p.loopCount} ជុំ`;

        const todayAnalysis = analyzeSunoTodayFeed();
        if (metricToday) metricToday.textContent = `${todayAnalysis.activeCount} / 4 បទ`;

        const createAnalysis = analyzeSunoCreateButton();
        if (metricCreate) {
            if (createAnalysis.isRateLimited) {
                metricCreate.textContent = '⏳ ដល់កំណត់ (Cooldown)';
                metricCreate.style.color = '#fbbf24';
            } else if (createAnalysis.isOutOfCredits) {
                metricCreate.textContent = '🛑 អស់ Credit';
                metricCreate.style.color = '#f87171';
            } else if (createAnalysis.canCreate) {
                metricCreate.textContent = '🟢 រួចរាល់ (Enabled)';
                metricCreate.style.color = '#34d399';
            } else {
                metricCreate.textContent = '🟡 ត្រៀមបង្កើត (Empty Form)';
                metricCreate.style.color = '#93c5fd';
            }
        }

        if (metricCooldown) {
            if (createAnalysis.cooldownMinutes > 0 || createAnalysis.cooldownSeconds > 0) {
                metricCooldown.textContent = `${createAnalysis.cooldownMinutes}m ${createAnalysis.cooldownSeconds}s`;
                metricCooldown.style.color = '#fbbf24';
            } else {
                metricCooldown.textContent = '—';
                metricCooldown.style.color = '#e2e8f0';
            }
        }

        // Highlight active step (1 to 5)
        for (let i = 1; i <= 5; i++) {
            const item = document.getElementById(`suno-step-item-${i}`);
            if (item) {
                if (p.isRunning && p.currentStep === i) {
                    item.style.background = 'rgba(139, 92, 246, 0.35)';
                    item.style.border = '1px solid #a78bfa';
                    item.style.color = '#ffffff';
                    item.style.boxShadow = '0 0 10px rgba(139, 92, 246, 0.3)';
                    item.style.fontWeight = '700';
                } else {
                    item.style.background = 'transparent';
                    item.style.border = '1px solid transparent';
                    item.style.color = '#cbd5e1';
                    item.style.boxShadow = 'none';
                    item.style.fontWeight = '600';
                }
            }
        }

        if (p.isRunning) {
            if (p.isPaused) {
                if (badge) {
                    badge.textContent = 'PAUSED';
                    badge.style.background = 'rgba(245,158,11,0.2)';
                    badge.style.color = '#fbbf24';
                    badge.style.border = '1px solid rgba(245,158,11,0.4)';
                }
                if (dockBadge) {
                    dockBadge.textContent = 'PAUSED';
                    dockBadge.style.background = 'rgba(245,158,11,0.2)';
                    dockBadge.style.color = '#fbbf24';
                }
                if (pauseBtn) {
                    pauseBtn.innerHTML = '<span>▶️</span> <span>បន្ត</span>';
                }
            } else {
                if (badge) {
                    badge.textContent = 'RUNNING';
                    badge.style.background = 'rgba(16,185,129,0.2)';
                    badge.style.color = '#34d399';
                    badge.style.border = '1px solid rgba(16,185,129,0.4)';
                }
                if (dockBadge) {
                    dockBadge.textContent = 'AUTO ON';
                    dockBadge.style.background = 'rgba(139,92,246,0.3)';
                    dockBadge.style.color = '#c4b5fd';
                }
                if (pauseBtn) {
                    pauseBtn.innerHTML = '<span>⏸️</span> <span>ផ្អាក</span>';
                }
            }
            if (startBtn) startBtn.style.display = 'none';
            if (pauseBtn) pauseBtn.style.display = 'flex';
            if (stopBtn) stopBtn.style.display = 'flex';
        } else {
            if (badge) {
                badge.textContent = 'STOPPED';
                badge.style.background = 'rgba(239,68,68,0.2)';
                badge.style.color = '#fca5a5';
                badge.style.border = '1px solid rgba(239,68,68,0.35)';
            }
            if (dockBadge) {
                dockBadge.textContent = 'OFF';
                dockBadge.style.background = 'rgba(255,255,255,0.08)';
                dockBadge.style.color = '#cbd5e1';
            }
            if (startBtn) startBtn.style.display = 'flex';
            if (pauseBtn) pauseBtn.style.display = 'none';
            if (stopBtn) stopBtn.style.display = 'none';
        }
    }

    // =========================================================================
    // 8.5 GEMINI 3.1 AI SONG TITLE GENERATION SUITE
    // =========================================================================
    window.sunoSetTitle = function(title) {
        if (!title) return false;
        const inp = document.getElementById('suno-title-output');
        if (inp) inp.value = title;
        const el = getSunoTitleElement();
        if (el) {
            setElementValue(el, title);
            showToast(`✓ បានបញ្ចូលចំណងជើង "${title}" ទៅក្នុង Suno!`, 'success');
            return true;
        }
        return false;
    };

    // =========================================================================
    // UNIQUE TITLE ENGINE & DEDUPLICATION HISTORY (ធានាថាមិនជាន់គ្នារហូត)
    // =========================================================================
    function getUsedTitlesHistory() {
        try {
            const raw = localStorage.getItem('suno_used_titles_history');
            if (raw) {
                const list = JSON.parse(raw);
                if (Array.isArray(list)) return list;
            }
        } catch (e) { }
        return [];
    }

    function recordUsedTitle(title) {
        if (!title || typeof title !== 'string') return;
        const clean = title.trim();
        if (!clean || clean.length < 2) return;
        try {
            let history = getUsedTitlesHistory();
            history = history.filter(t => t.toLowerCase() !== clean.toLowerCase());
            history.push(clean);
            if (history.length > 300) history.shift();
            localStorage.setItem('suno_used_titles_history', JSON.stringify(history));
            console.log('[Suno Studio] Recorded used title to history (total: ' + history.length + '):', clean);
        } catch (e) { }
    }

    function isTitleDuplicate(candidateTitle) {
        if (!candidateTitle) return true;
        const norm = candidateTitle.trim().toLowerCase();
        const history = getUsedTitlesHistory().map(t => t.trim().toLowerCase());
        if (history.includes(norm)) return true;

        // Check DOM library and Today feed clips
        const domElements = Array.from(document.querySelectorAll('[data-testid*="clip"] h3, [role="group"] h3, .suno-title-chip, .suno-track-title'));
        for (const el of domElements) {
            const txt = (el.textContent || '').trim().toLowerCase();
            if (txt === norm) return true;
        }
        return false;
    }

    // Procedural Khmer title generator with thousands of unique combinations
    function generateSingleUniqueKhmerTitle(baseTopic, themeVibe, styleVibe) {
        const prefixes = [
            'ស្រមោល', 'រាត្រី', 'អនុស្សាវរីយ៍', 'ចង្វាក់', 'ដំណក់', 'សំឡេង', 'រលក', 'ក្លិន',
            'បេះដូង', 'ក្តីសង្ឃឹម', 'វេលា', 'ផ្កាយ', 'ជំនោរ', 'រដូវ', 'ពន្លឺ', 'ទឹកភ្នែក',
            'ស្នាមញញឹម', 'សុបិន', 'ចម្រៀង', 'ដួងចិត្ត', 'ដានជើង', 'ខ្យល់បក់', 'ចម្លើយ', 'សន្យា',
            'មន្តស្នេហ៍', 'ក្តីស្រមៃ', 'រឿងរ៉ាវ', 'ផ្ការីក', 'ចំណង', 'និទាន', 'រស្មី', 'មរតក'
        ];

        const themes = [
            'ស្នេហ៍ស្មោះ', 'នឹកមនុស្សម្នាក់', 'កោះរ៉ុង', 'ភ្នំពេញរាត្រី', 'សៀមរាបអង្គរ', 'កាហ្វេរាត្រី',
            'មាត់សមុទ្រ', 'ខ្យល់ត្រជាក់', 'ចាកចេញឆ្ងាយ', 'ការចងចាំ', 'ផ្ការំដួល', 'ស្នេហ៍កណ្តាលភ្លៀង',
            'ព្រះចន្ទពេញវង់', 'ពន្លឺថ្ងៃថ្មី', 'បេះដូងឯកា', 'ផ្លូវឆ្ងាយ', 'ស្រុកកំណើត', 'ម្លប់ជ្រៃចាស់',
            'ស្នេហ៍គ្រាដំបូង', 'មនុស្សក្នុងសុបិន', 'ស្នេហ៍ចម្ងាយ', 'រឿងរ៉ាវអតីត', 'ជួបគ្នាម្តងទៀត',
            'ក្តីសុខសាមញ្ញ', 'រំជួលចិត្ត', 'ថ្ងៃរះថ្មី', 'ស្នេហ៍ក្នុងចិត្ត', 'ស្ទឹងសង្កែ', 'បន្ទាយស្រី',
            'វាលស្រែខៀវ', 'ក្លិនផ្កាម្លិះ', 'កែវភ្នែកស្រទន់', 'រាត្រីគ្មានអូន', 'ស្នេហ៍អមតៈ'
        ];

        const suffixes = [
            '(Acoustic Melody)', '(Midnight Mix)', '(Heartbeat Ballad)', '(Emotional Version)',
            '(Drift Phonk Vibe)', '[Lo-Fi Dream]', '(Deep Emotion)', '[Classic Khmer Pop]',
            '(Lost in Thought)', '[Soulful R&B]', '(Endless Love)', '[Pristine Studio Mix]',
            '(Whisper of Night)', '[Romantic Chill]', '(Sunset Acoustic)', '(Sweet Serenade)',
            '[High-Energy Phonk]', '(Memory Lane)', '[Late Night Groove]', '(Golden Hour Mix)',
            '(Piano & Cello)', '[Acoustic Live]', '(Sweet Romance)', '[Echo of Love]', '(Eternal Bloom)'
        ];

        const cleanTopic = (baseTopic || '').trim().replace(/^(បទ|ចម្រៀង|បទចម្រៀង)[\s៖:]*/, '');

        for (let attempt = 0; attempt < 80; attempt++) {
            let candidate = '';
            const p = prefixes[Math.floor(Math.random() * prefixes.length)];
            const t = themes[Math.floor(Math.random() * themes.length)];
            const s = suffixes[Math.floor(Math.random() * suffixes.length)];

            if (cleanTopic && attempt < 30) {
                const patterns = [
                    `${cleanTopic} ${s}`,
                    `${p}${cleanTopic} ${s}`,
                    `${cleanTopic} (${p}ស្នេហ៍)`,
                    `រឿងរ៉ាវ "${cleanTopic}" ${s}`,
                    `${cleanTopic} - ${t}`
                ];
                candidate = patterns[Math.floor(Math.random() * patterns.length)];
            } else {
                const patterns = [
                    `${p}${t} ${s}`,
                    `${p}នៃ${t}`,
                    `${t}កណ្តាលរាត្រី ${s}`,
                    `${p}ស្នេហ៍ ${t} ${s}`,
                    `${t} (បទចម្រៀងសម្រាប់អូន)`
                ];
                candidate = patterns[Math.floor(Math.random() * patterns.length)];
            }

            if (!isTitleDuplicate(candidate)) {
                return candidate;
            }
        }

        // Guaranteed unique fallback if all random attempts collided
        const fallbackPrefix = cleanTopic || 'ស្រមោលស្នេហ៍';
        const uniqueId = Math.floor(100 + Math.random() * 900);
        return `${fallbackPrefix} (Edition #${uniqueId})`;
    }

    function generateSmartGeminiTitles(topic, theme, style, lyrics) {
        const results = [];
        const seenInBatch = new Set();
        let attempts = 0;

        while (results.length < 5 && attempts < 100) {
            attempts++;
            const t = generateSingleUniqueKhmerTitle(topic, theme?.name || '', style || '');
            if (!seenInBatch.has(t) && !isTitleDuplicate(t)) {
                seenInBatch.add(t);
                results.push(t);
            }
        }

        // Fill up to 5 if needed
        while (results.length < 5) {
            const randSuffix = Math.floor(10 + Math.random() * 90);
            const extra = `${topic || 'ចង្វាក់បេះដូង'} (Mix #${randSuffix})`;
            if (!seenInBatch.has(extra)) {
                seenInBatch.add(extra);
                results.push(extra);
            }
        }

        return results;
    }

    // Complete Gemini Models Hierarchy (from earliest to latest generation + Smart AI Engine)
    const GEMINI_MODELS = [
        // ជំនាន់ ៣.x (Next-Gen & Flagship)
        { id: 'gemini-3.1-flash-lite', name: 'Gemini 3.1 Flash-Lite (លឿនឆ្លាត សន្សំសំចៃ - ណែនាំ)', group: 'ជំនាន់ ៣.x (Next-Gen)' },
        { id: 'gemini-3.1-pro-preview', name: 'Gemini 3.1 Pro Preview (កំពូលស្នាដៃតែងនិពន្ធ & កម្រិតច្នៃប្រឌិតខ្ពស់)', group: 'ជំនាន់ ៣.x (Next-Gen)' },
        { id: 'gemini-3.5-flash', name: 'Gemini 3.5 Flash (ឆ្លាតវៃកម្រិតខ្ពស់ & ល្បឿនលឿន)', group: 'ជំនាន់ ៣.x (Next-Gen)' },
        { id: 'gemini-3.0-flash', name: 'Gemini 3.0 Flash (Next-Gen Flash)', group: 'ជំនាន់ ៣.x (Next-Gen)' },

        // ជំនាន់ ២.៥ (Balanced & Production)
        { id: 'gemini-2.5-flash', name: 'Gemini 2.5 Flash (រហ័សទាន់ចិត្ត និងមានតុល្យភាពល្អ)', group: 'ជំនាន់ ២.៥ (Stable)' },
        { id: 'gemini-2.5-flash-lite', name: 'Gemini 2.5 Flash-Lite (ទម្ងន់ស្រាល និងរហ័សបំផុត)', group: 'ជំនាន់ ២.៥ (Stable)' },
        { id: 'gemini-2.5-pro', name: 'Gemini 2.5 Pro (ជំនាញភាសាខ្មែរ និងតែងនិពន្ធស៊ីជម្រៅ)', group: 'ជំនាន់ ២.៥ (Stable)' },

        // ជំនាន់ ២.០ (Advanced Reasoning & Speed)
        { id: 'gemini-2.0-flash', name: 'Gemini 2.0 Flash (ជំនាន់ឆ្លាតវៃល្បឿនលឿន)', group: 'ជំនាន់ ២.០' },
        { id: 'gemini-2.0-flash-lite', name: 'Gemini 2.0 Flash-Lite (កម្រិតស្រាល រហ័ស)', group: 'ជំនាន់ ២.០' },
        { id: 'gemini-2.0-flash-thinking-exp', name: 'Gemini 2.0 Flash Thinking (គិតស៊ីជម្រៅ)', group: 'ជំនាន់ ២.០' },
        { id: 'gemini-2.0-pro-exp-02-05', name: 'Gemini 2.0 Pro Experimental (កម្រិតសរសេរខ្ពស់)', group: 'ជំនាន់ ២.០' },

        // ជំនាន់ ១.៥ & ១.០ (Classic & Foundation)
        { id: 'gemini-1.5-flash', name: 'Gemini 1.5 Flash (រហ័សទាន់ចិត្ត Context ធំ)', group: 'ជំនាន់ ១.៥ & ១.០ (Classic)' },
        { id: 'gemini-1.5-flash-8b', name: 'Gemini 1.5 Flash-8B (ខ្នាតតូច សន្សំសំចៃ)', group: 'ជំនាន់ ១.៥ & ១.០ (Classic)' },
        { id: 'gemini-1.5-pro', name: 'Gemini 1.5 Pro (កម្លាំងគិតស៊ីជម្រៅ)', group: 'ជំនាន់ ១.៥ & ១.០ (Classic)' },
        { id: 'gemini-1.0-pro', name: 'Gemini 1.0 Pro (ជំនាន់ដំបូងបង្អស់ Classic)', group: 'ជំនាន់ ១.៥ & ១.០ (Classic)' },

        // Local Engine
        { id: 'smart_engine', name: '⚡ Smart AI Engine (ដំណើរការ Offline គ្មាន Key)', group: 'Local Engine' }
    ];

    function getGeminiModelName(modelId) {
        const found = GEMINI_MODELS.find(m => m.id === modelId);
        return found ? found.name : (modelId || 'Gemini 3.1 Flash-Lite');
    }

    function renderGeminiModelOptions(selectedModel) {
        const groups = {};
        GEMINI_MODELS.forEach(m => {
            if (!groups[m.group]) groups[m.group] = [];
            groups[m.group].push(m);
        });

        let html = '';
        for (const [groupName, models] of Object.entries(groups)) {
            html += `<optgroup label="${groupName}" style="background:#1b152d; color:#c4b5fd; font-weight:700;">`;
            models.forEach(m => {
                const isSel = m.id === selectedModel ? 'selected' : '';
                html += `<option value="${m.id}" ${isSel} style="background:#100d1c; color:#ffffff; font-weight:500;">${m.name}</option>`;
            });
            html += `</optgroup>`;
        }
        return html;
    }

    // Complete Multilingual Songwriting Configuration (កំណត់ភាសានិពន្ធចម្រៀង គ្រប់ភាសាទាំងអស់)
    const SUNO_SUPPORTED_LANGUAGES = [
        { code: 'km', name: '🇰🇭 ភាសាខ្មែរ (Khmer - Standard)', label: 'Khmer', vocalTag: 'Khmer vocals', directive: 'Khmer language (ភាសាខ្មែរ) with beautiful poetic Khmer vocabulary, idioms, and natural rhyme schemes', titleRule: 'A creative, catchy, and poetic song title in Khmer (can include English subtitle in parentheses, e.g. "ស្រមោលស្នេហ៍ (Shadow of Love)")' },
        { code: 'en', name: '🇬🇧 ភាសាអង់គ្លេស (English)', label: 'English', vocalTag: 'English vocals', directive: 'English language with catchy, natural, hit-maker English lyrics, memorable hooks, and deep emotion', titleRule: 'A creative, catchy, and hit-worthy song title in English' },
        { code: 'zh', name: '🇨🇳 ភាសាចិន (Chinese - Mandarin)', label: 'Chinese', vocalTag: 'Chinese vocals, Mandarin', directive: 'Standard Mandarin Chinese (中文) with poetic, meaningful lyrics and beautiful phrasing (Simplified or Traditional characters)', titleRule: 'A creative, poetic song title in Chinese (with English subtitle in parentheses if suitable)' },
        { code: 'ja', name: '🇯🇵 ភាសាជប៉ុន (Japanese)', label: 'Japanese', vocalTag: 'Japanese vocals', directive: 'Japanese language (日本語) with emotive, expressive J-Pop/Anime lyrical style with natural kanji/hiragana/katakana', titleRule: 'A creative, poetic song title in Japanese (with English or Romaji subtitle in parentheses)' },
        { code: 'ko', name: '🇰🇷 ភាសាកូរ៉េ (Korean)', label: 'Korean', vocalTag: 'Korean vocals', directive: 'Korean language (한국어) with catchy K-Pop / K-Ballad rhythm, style, and natural Hangul lyrics', titleRule: 'A creative, catchy song title in Korean (with English subtitle in parentheses)' },
        { code: 'th', name: '🇹🇭 ភាសាថៃ (Thai)', label: 'Thai', vocalTag: 'Thai vocals', directive: 'Thai language (ภาษาไทย) with melodic and expressive Thai phrasing and natural rhyming', titleRule: 'A creative, melodic song title in Thai (with English subtitle in parentheses)' },
        { code: 'vi', name: '🇻🇳 ភាសាវៀតណាម (Vietnamese)', label: 'Vietnamese', vocalTag: 'Vietnamese vocals', directive: 'Vietnamese language (Tiếng Việt) with poetic tones and expressive V-Pop songwriting', titleRule: 'A creative, poetic song title in Vietnamese (with English subtitle in parentheses)' },
        { code: 'fr', name: '🇫🇷 ភាសាបារាំង (French)', label: 'French', vocalTag: 'French vocals', directive: 'French language (Français) with romantic, poetic, and elegant French lyrics', titleRule: 'A creative, romantic song title in French' },
        { code: 'es', name: '🇪🇸 ភាសាអេស្ប៉ាញ (Spanish)', label: 'Spanish', vocalTag: 'Spanish vocals', directive: 'Spanish language (Español) with passionate, rhythmic, and poetic Spanish lyrics', titleRule: 'A creative, passionate song title in Spanish' },
        { code: 'de', name: '🇩🇪 ភាសាអាល្លឺម៉ង់ (German)', label: 'German', vocalTag: 'German vocals', directive: 'German language (Deutsch) with expressive, rhythmic, and powerful German lyrical structure', titleRule: 'A creative, catchy song title in German' },
        { code: 'it', name: '🇮🇹 ភាសាអ៊ីតាលី (Italian)', label: 'Italian', vocalTag: 'Italian vocals', directive: 'Italian language (Italiano) with melodic, passionate, and emotive Italian songwriting', titleRule: 'A creative, melodic song title in Italian' },
        { code: 'ru', name: '🇷🇺 ភាសារុស្ស៊ី (Russian)', label: 'Russian', vocalTag: 'Russian vocals', directive: 'Russian language (Русский) with deep, atmospheric, and emotive Russian lyrics', titleRule: 'A creative, atmospheric song title in Russian' },
        { code: 'hi', name: '🇮🇳 ភាសាហិណ្ឌូ (Hindi)', label: 'Hindi', vocalTag: 'Hindi vocals', directive: 'Hindi language (हिन्दी) with Bollywood / Indie melodic flair and emotive Hindi phrasing', titleRule: 'A creative, catchy song title in Hindi' },
        { code: 'km_en', name: '🌐 ខ្មែរ + អង់គ្លេស (Khmer & English Bilingual)', label: 'Khmer & English', vocalTag: 'Khmer & English vocals', directive: 'Bilingual Khmer & English mix (ភាសាខ្មែរលាយអង់គ្លេស) - blending catchy English chorus/hooks with emotional Khmer verses', titleRule: 'A bilingual Khmer & English title (e.g. "រាត្រីភ្នំពេញ (Phnom Penh Midnight)")' },
        { code: 'custom', name: '✏️ ភាសាផ្សេងៗ / ផ្ទាល់ខ្លួន (Custom Any Language...)', label: 'Custom', vocalTag: 'Vocals', directive: 'specified custom language', titleRule: 'A creative song title in the specified language' }
    ];

    function renderLanguageOptions(selectedCode) {
        return SUNO_SUPPORTED_LANGUAGES.map(l => {
            const isSel = l.code === selectedCode ? 'selected' : '';
            return `<option value="${l.code}" ${isSel} style="background:#100d1c; color:#ffffff;">${l.name}</option>`;
        }).join('');
    }

    function getSongLanguageConfig() {
        const savedCode = localStorage.getItem('suno_song_language') || 'km';
        const customName = (localStorage.getItem('suno_custom_language_name') || '').trim();
        let match = SUNO_SUPPORTED_LANGUAGES.find(l => l.code === savedCode) || SUNO_SUPPORTED_LANGUAGES[0];
        if (savedCode === 'custom' && customName) {
            return {
                code: 'custom',
                name: `✏️ ${customName}`,
                label: customName,
                vocalTag: `${customName} vocals`,
                directive: `${customName} language with culturally authentic, poetic, and native songwriting conventions`,
                titleRule: `A creative, catchy song title in ${customName} language`
            };
        }
        return match;
    }

    function setSongLanguage(code, customName = '', isBroadcast = false) {
        if (!code) return;
        localStorage.setItem('suno_song_language', code);
        if (customName !== undefined && customName !== null) {
            localStorage.setItem('suno_custom_language_name', customName);
        }
        const cfg = getSongLanguageConfig();

        // Sync all select elements
        document.querySelectorAll('#suno-language-select, #suno-loop-language-select').forEach(sel => {
            if (sel.value !== code) sel.value = code;
        });

        // Toggle custom inputs
        const showCustom = code === 'custom';
        document.querySelectorAll('#suno-custom-language-input, #suno-loop-custom-lang-input').forEach(inp => {
            inp.style.display = showCustom ? 'block' : 'none';
            if (showCustom && customName) inp.value = customName;
        });

        // Update badges
        document.querySelectorAll('#suno-current-lang-badge, #suno-loop-current-lang-badge').forEach(badge => {
            badge.textContent = cfg.name.split('(')[0].trim();
        });

        if (isBroadcast) {
            try {
                if (window.chrome && window.chrome.webview) {
                    window.chrome.webview.postMessage(JSON.stringify({
                        action: 'set_song_language',
                        language: code,
                        customLanguage: customName
                    }));
                }
            } catch (e) { }
            showToast(`🌐 បានកំណត់ភាសានិពន្ធចម្រៀង៖ ${cfg.name}!`, 'success');
        }
    }
    window.setSongLanguage = setSongLanguage;
    window.getSongLanguageConfig = getSongLanguageConfig;

    // Auto-Bind Gemini model across entire application
    window.syncGeminiModel = function(modelCode, isInternalBroadcast = false) {
        if (!modelCode) return;
        localStorage.setItem('gemini_model_choice', modelCode);
        
        // 1. Update all model selects
        document.querySelectorAll('.suno-gemini-model-select, #suno-gemini-model-select').forEach(sel => {
            if (sel.value !== modelCode) sel.value = modelCode;
        });

        // 2. Update active badges & labels
        const shortName = getGeminiModelName(modelCode).split('(')[0].trim();
        const badge = document.getElementById('suno-gemini-model-badge');
        if (badge) badge.textContent = `✓ ${shortName}`;
        const activeName = document.getElementById('suno-active-model-name');
        if (activeName) activeName.textContent = shortName;

        console.log('[Suno Studio] Synced Gemini model across app:', modelCode);

        // 3. Broadcast to SunoApp host via WebView2 postMessage
        if (isInternalBroadcast) {
            try {
                if (window.chrome && window.chrome.webview) {
                    window.chrome.webview.postMessage(JSON.stringify({ action: 'set_gemini_model', model: modelCode }));
                }
            } catch (e) { }

            showToast(`✓ បានភ្ជាប់ ${shortName} ជាមួយកម្មវិធីទាំងមូលដោយស្វ័យប្រវត្តិ!`, 'success');
        }
    };

    async function callGeminiApiForTitles(apiKey, model, topic, theme, style, lyrics) {
        const targetModel = model || localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';
        const langConfig = getSongLanguageConfig();
        if (targetModel === 'smart_engine') {
            return generateSmartGeminiTitles(topic, theme, style, lyrics);
        }

        const recentUsed = (typeof getUsedTitlesHistory === 'function') ? getUsedTitlesHistory().slice(-18) : [];
        const avoidClause = recentUsed.length > 0 
            ? `\n- CRITICAL ANTI-REPETITION REQUIREMENT:\nDo NOT repeat, duplicate, or output titles similar to these previously used titles:\n[${recentUsed.map(t => `"${t}"`).join(', ')}]\nEvery title must be completely novel and unique!`
            : '';

        const promptText = `You are a professional hit songwriter and song title specialist for Suno AI music creation.
Generate 5 completely brand new, unique, catchy, viral, poetic, and creative song titles written in ${langConfig.directive} for Suno based on these details:
- Song Theme/Mood: "${topic || theme?.name || 'Contemporary Track'}"
- Music Style/Genre: "${style}"
- Lyrics Excerpt: "${(lyrics || '').slice(0, 350)}"
${avoidClause}

Guidelines:
1. Every title MUST be fresh and completely unique. Never repeat previous titles.
2. Titles should be creative and appealing in ${langConfig.label} context (${langConfig.titleRule}).
3. Titles must be diverse in mood: from poetic to energetic and emotional.
4. Return ONLY a valid JSON array of exactly 5 strings, with no markdown code blocks, explanation, or extra characters.
Example format:
["Title 1", "Title 2", "Title 3", "Title 4", "Title 5"]`;

        const url = `https://generativelanguage.googleapis.com/v1beta/models/${targetModel}:generateContent?key=${apiKey}`;

        const res = await fetch(url, {
            method: 'POST',
            signal: AbortSignal.timeout ? AbortSignal.timeout(6500) : undefined,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                contents: [{ parts: [{ text: promptText }] }],
                generationConfig: {
                    temperature: 0.95,
                    maxOutputTokens: 350
                }
            })
        });

        if (!res.ok) {
            const errText = await res.text().catch(() => '');
            throw new Error(`Gemini API returned status ${res.status}: ${errText}`);
        }

        const data = await res.json();
        const textOutput = data?.candidates?.[0]?.content?.parts?.[0]?.text || '';

        let candidateList = [];
        try {
            const cleanJson = textOutput.replace(/```json/gi, '').replace(/```/g, '').trim();
            const parsed = JSON.parse(cleanJson);
            if (Array.isArray(parsed) && parsed.length > 0) {
                candidateList = parsed.map(t => String(t).trim()).filter(Boolean);
            }
        } catch (e) {
            const lines = textOutput.split('\n')
                .map(l => l.replace(/^[\d\.\-\*\s"']+|["',]+$/g, '').trim())
                .filter(l => l.length > 1 && !l.startsWith('[') && !l.startsWith('{'));
            if (lines.length >= 3) {
                candidateList = lines;
            }
        }

        // Deduplication & uniqueness guarantee
        const finalUnique = [];
        const seenInBatch = new Set();
        candidateList.forEach(t => {
            const clean = t.trim();
            if (clean && !seenInBatch.has(clean) && !isTitleDuplicate(clean)) {
                seenInBatch.add(clean);
                finalUnique.push(clean);
            }
        });

        // If any candidates collided with history, replace them with fresh procedural titles
        while (finalUnique.length < 5) {
            const fresh = generateSingleUniqueKhmerTitle(topic, theme?.name || '', style || '');
            if (!seenInBatch.has(fresh)) {
                seenInBatch.add(fresh);
                finalUnique.push(fresh);
            }
        }

        return finalUnique.slice(0, 5);
    }

    function renderGeminiTitleChips(titles, activeTitle) {
        const container = document.getElementById('suno-gemini-title-chips');
        if (!container) return;

        container.innerHTML = titles.map((t, idx) => {
            const isActive = t === activeTitle;
            return `
                <button class="suno-title-chip" data-title="${encodeURIComponent(t)}" style="
                    background: ${isActive ? 'linear-gradient(135deg, #8b5cf6, #7c3aed)' : '#232034'};
                    border: 1px solid ${isActive ? '#c4b5fd' : '#453860'};
                    color: ${isActive ? '#ffffff' : '#e0d8f6'};
                    border-radius: 6px;
                    padding: 4px 9px;
                    font-size: 11px;
                    font-weight: ${isActive ? '700' : '500'};
                    cursor: pointer;
                    transition: all 0.2s;
                    display: inline-flex;
                    align-items: center;
                    gap: 4px;
                    box-shadow: ${isActive ? '0 2px 8px rgba(139,92,246,0.4)' : 'none'};
                ">
                    <span>${idx === 0 ? '⭐' : '💡'}</span>
                    <span>${t}</span>
                </button>
            `;
        }).join('');

        container.querySelectorAll('.suno-title-chip').forEach(btn => {
            btn.onclick = () => {
                const rawTitle = decodeURIComponent(btn.getAttribute('data-title'));
                const titleInput = document.getElementById('suno-title-output');
                if (titleInput) {
                    titleInput.value = rawTitle;
                }
                renderGeminiTitleChips(titles, rawTitle);
                fillSingleField('title');
                showToast(`✨ បានជ្រើសរើសចំណងជើង៖ "${rawTitle}"`, 'success');
            };
        });
    }

    async function requestGeminiSongTitles(isManual = false) {
        const topic = document.getElementById('suno-custom-topic')?.value?.trim() || '';
        const themeId = document.getElementById('suno-theme-select')?.value;
        const selectedTheme = songData.themes.find(t => t.id === themeId) || songData.themes[0];
        const style = document.getElementById('suno-style-output')?.value || '';
        const lyrics = document.getElementById('suno-lyrics-output')?.value || '';

        const apiKey = localStorage.getItem('gemini_api_key') || '';
        const modelChoice = localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';
        const modelName = getGeminiModelName(modelChoice).split('(')[0].trim();

        const loadingIndicator = document.getElementById('suno-gemini-loading');
        if (loadingIndicator) loadingIndicator.style.display = 'inline';

        let titles = [];
        let usedApi = false;

        if (apiKey && modelChoice !== 'smart_engine') {
            try {
                titles = await callGeminiApiForTitles(apiKey, modelChoice, topic, selectedTheme, style, lyrics);
                usedApi = true;
            } catch (err) {
                console.warn(`[${modelName}] API call failed, falling back to Smart AI engine:`, err);
                titles = generateSmartGeminiTitles(topic, selectedTheme, style, lyrics);
            }
        } else {
            titles = generateSmartGeminiTitles(topic, selectedTheme, style, lyrics);
        }

        if (loadingIndicator) loadingIndicator.style.display = 'none';

        if (titles && titles.length > 0) {
            renderGeminiTitleChips(titles, titles[0]);
            const titleInput = document.getElementById('suno-title-output');
            if (titleInput) {
                titleInput.value = titles[0];
                titleInput.style.borderColor = '#8b5cf6';
                setTimeout(() => { if (titleInput) titleInput.style.borderColor = '#4a3e6a'; }, 1000);
            }

            if (isManual) {
                fillSingleField('title');
                showToast(usedApi ? `✨ ${modelName} បានបង្កើតចំណងជើងថ្មី ៥ ជម្រើស!` : '✨ Smart AI Engine បានបង្កើតចំណងជើងថ្មី ៥ ជម្រើស!', 'success');
            }
        }
    }

    async function composeFullSongWithGemini(topic, theme, genre, vocalTypeOrProf, tempo, apiKey, modelChoice) {
        const model = modelChoice || localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';
        const vocalProf = (typeof vocalTypeOrProf === 'object' && vocalTypeOrProf.stylePrefix) 
            ? vocalTypeOrProf 
            : getVocalProfile(vocalTypeOrProf);
        const langConfig = getSongLanguageConfig();

        if (model === 'smart_engine') {
            return composeDynamicSmartSong(topic, theme, genre, vocalProf, tempo);
        }

        const recentUsed = (typeof getUsedTitlesHistory === 'function') ? getUsedTitlesHistory().slice(-18) : [];
        const avoidClause = recentUsed.length > 0 
            ? `\n- CRITICAL ANTI-REPETITION: Do NOT reuse, repeat, or generate titles similar to these previously used titles:\n[${recentUsed.map(t => `"${t}"`).join(', ')}]\nEvery title must be completely novel and fresh!\n`
            : '';

        const promptText = `You are a master hit-maker songwriter, poet, and music producer for Suno AI.
Generate a completely original, brand new, deeply emotional, and viral song written in ${langConfig.directive} based on these details:
- Song Topic / Idea: "${topic || theme?.name || 'Hit Song'}"
- Base Theme: "${theme?.name || ''}"
- Music Genre / Vibe: "${genre?.name || ''} (${genre?.style || ''})"
- Vocals: "${vocalProf.name}"
${vocalProf.promptInstruction}
- Tempo: "${tempo}"
${avoidClause}

Requirements:
1. "title": ${langConfig.titleRule}. MUST be completely unique and never used before.
2. "alternativeTitles": Exactly 4 additional creative alternative titles in an array of strings in ${langConfig.label} (all unique).
3. "style": A rich, highly optimized Suno AI Music Style Prompt (in English).
   - CRITICAL VOCAL DIRECTIVE: "style" MUST start with "${vocalProf.stylePrefix}" as the very first words at index 0. Include "${langConfig.vocalTag}" if vocals are enabled. Then append specific instruments, mood, bpm, audio production quality (e.g. "Dolby Atmos 3D mix, wide acoustic stereo, pristine studio detail").
4. "lyrics": Complete, fully-written, poetic song lyrics written in ${langConfig.directive} with proper Suno structure tags:
   - Must begin with "${vocalProf.lyricTag}" at the top.
   ${vocalProf.isInstrumental ? '- Pure instrumental structure with cues like [Instrumental], [Main Theme], [Melodic Solo], [Outro - Fade Out]. NO singing words.' : '- Structure with [Intro], [Verse 1], [Pre-Chorus], [Chorus], [Verse 2], [Bridge], [Chorus], [Outro].'}

Return ONLY a valid JSON object with keys "title", "alternativeTitles", "style", and "lyrics", with no markdown code blocks or extra text:
{
  "title": "...",
  "alternativeTitles": ["...", "...", "...", "..."],
  "style": "...",
  "lyrics": "..."
}`;

        const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

        const res = await fetch(url, {
            method: 'POST',
            signal: AbortSignal.timeout ? AbortSignal.timeout(6500) : undefined,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                contents: [{ parts: [{ text: promptText }] }],
                generationConfig: {
                    temperature: 0.95,
                    maxOutputTokens: 1400
                }
            })
        });

        if (!res.ok) {
            const errText = await res.text().catch(() => '');
            throw new Error(`Gemini API error: ${res.status} ${errText}`);
        }

        const data = await res.json();
        const textOutput = data?.candidates?.[0]?.content?.parts?.[0]?.text || '';
        const cleanJson = textOutput.replace(/```json/gi, '').replace(/```/g, '').trim();
        const parsed = JSON.parse(cleanJson);
        if (parsed.title && parsed.lyrics && parsed.style) {
            // Apply dual-layer vocal enforcement
            parsed.style = enforceVocalStylePrompt(parsed.style, vocalProf);
            parsed.lyrics = enforceVocalLyricsTags(parsed.lyrics, vocalProf);

            if (typeof isTitleDuplicate === 'function' && isTitleDuplicate(parsed.title)) {
                const alt = (parsed.alternativeTitles || []).find(t => !isTitleDuplicate(t));
                parsed.title = alt || generateSingleUniqueKhmerTitle(topic, theme?.name, genre?.name);
            }
            if (typeof recordUsedTitle === 'function') {
                recordUsedTitle(parsed.title);
            }
            return parsed;
        }
        throw new Error('Incomplete song JSON from Gemini');
    }

    function composeDynamicSmartSong(topic, theme, genre, vocalTypeOrProf, tempo) {
        const vocalProf = (typeof vocalTypeOrProf === 'object' && vocalTypeOrProf.stylePrefix)
            ? vocalTypeOrProf
            : getVocalProfile(vocalTypeOrProf);

        const rawTopic = (topic || '').trim();
        const themeId = theme?.id || 'love_sweet';
        const cleanTopic = rawTopic.replace(/^(បទ|ចម្រៀង|បទចម្រៀង)[\s៖:]*/, '').trim();

        const topicWord = cleanTopic || (theme ? theme.defaultTitle.replace(/^បទ៖\s*/, '') : 'ស្រមោលស្នេហ៍');
        const titles = generateSmartGeminiTitles(topic, theme, genre?.style || '', '');
        let primaryTitle = (titles && titles.length > 0) ? (titles.find(t => !isTitleDuplicate(t)) || titles[0]) : `បទ៖ ${topicWord}`;
        if (typeof recordUsedTitle === 'function') {
            recordUsedTitle(primaryTitle);
        }
        const altTitles = (titles || []).filter(t => t !== primaryTitle).slice(0, 4);

        const instrumentsList = [
            'melodic grand piano, acoustic nylon guitar, warm khmer kloy flute, ambient strings',
            'mellow fingerstyle acoustic guitar, soft electric rhodes piano, gentle bass, warm reverb',
            'intimate acoustic piano, crying electric guitar solo, orchestral string quartet, deep warm bass',
            'resonant roneat ek, soft acoustic guitar, ambient synth pads, pristine studio mix',
            'crisp acoustic strums, atmospheric pads, gentle live drums, crystal clear female harmony',
            'driving acoustic rhythm, mellow cello accents, fingerpicked guitar warmth, delicate chimes'
        ];
        const randomInst = instrumentsList[Math.floor(Math.random() * instrumentsList.length)];

        const spatialMixList = [
            'Dolby Atmos 3D spatial mix, pristine studio recording, ultra-clear 24-bit/192 kHz audio',
            'wide festival stereo soundstage, warm analog tape texture, pristine audio fidelity',
            'intimate acoustic room reverb, deep dynamic range, ultra-clean studio production',
            'holographic audio mix, wide stereo panning, emotional acoustic clarity'
        ];
        const randomMix = spatialMixList[Math.floor(Math.random() * spatialMixList.length)];

        let bpm = 80;
        if (tempo && (tempo.includes('72') || tempo.includes('slow'))) bpm = 68 + Math.floor(Math.random() * 8);
        else if (tempo && (tempo.includes('124') || tempo.includes('fast'))) bpm = 120 + Math.floor(Math.random() * 8);
        else bpm = 82 + Math.floor(Math.random() * 8);

        const baseStyle = `${genre?.style?.split(',')[0] || 'Contemporary Khmer Pop'}, ${randomInst}, ${bpm} bpm, ${randomMix}`;
        const dynamicStyle = enforceVocalStylePrompt(baseStyle, vocalProf);

        const isSad = /heartbreak|sad|ភ្លៀង|បែកបាក់|ឈឺចាប់/i.test(themeId + cleanTopic);
        const isCafe = /cafe|កាហ្វេ|រាត្រី|យប់/i.test(cleanTopic);
        const isMother = /mother|homesick|ម្តាយ|ម៉ែ|ស្រុកស្រែ|ស្រុកកំណើត|ភូមិ/i.test(themeId + cleanTopic);
        const isMotivational = /motivational|rise|តស៊ូ|កម្លាំង|ចម្បាំង|ជោគជ័យ|កុំចុះចាញ់/i.test(themeId + cleanTopic);
        const isParty = /dance|party|romvong|saravan|ចូលឆ្នាំ|រាំ|សប្បាយ|រាំវង់|សារ៉ាវ៉ាន់/i.test(themeId + cleanTopic);

        let verses = [];
        let preChorus = '';
        let chorus = '';
        let bridge = '';
        let outro = '';

        if (isMother) {
            const v1Pool = [
                `[Verse 1]\nខ្យល់រំភើយបក់មកពីទិសខាងកើត នឹកស្រុកកំណើតធ្លាប់រស់នៅ\nនឹកក្លិនបាយក្ដៅម្ដាយដាំ នឹកផ្ទះស្លឹកចាស់ម្លប់ជ្រៃ\nកូនមកតស៊ូនៅទីក្រុង ឆ្ងាយស្រុកឆ្ងាយភូមិ\nរាល់រាត្រីសម្លឹងមើលផ្កាយ នឹកម៉ែឪរាល់វេលា`,
                `[Verse 1]\nស្រណោះវាលស្រែខៀវស្រងាត់ ធ្លាប់រត់លេងកាលពីកុមារ\nឮសំឡេងម៉ែហៅហូបបាយ ផ្អែមល្ហែមជាប់ក្នុងចិន្តា\nពេលនេះមកនៅឆ្ងាយផ្ទះ ឯកាក្នុងទីក្រុងធំ\nមានតែរូបថតចាស់របស់ម៉ែ ជាកម្លាំងចិត្តកូនតស៊ូ`,
                `[Verse 1]\nតំណក់ទឹកភ្លៀងធ្លាក់លើដំបូលផ្ទះជួល ធ្វើឱ្យកូននឹកផ្ទះស្រុកស្រែ\nនឹកដៃម៉ែដែលធ្លាប់បបោសអង្អែល ពេលកូនឈឺម្តងៗ\nកូនសូមអភ័យទោសដែលមិនទាន់បានតបស្នងគុណ\nតែសន្យាថានឹងខំប្រឹង ឱ្យម៉ែមានមោទនភាព`
            ];
            const v2Pool = [
                `[Verse 2]\nឃើញដៃម៉ែគគ្រើមព្រោះធ្វើការ ទឹកភ្នែកហូរស្រក់ស្រណោះ\nម៉ែរងទុក្ខវេទនាដើម្បីកូន មិនដែលរអ៊ូពាក្យហត់នឿយ\nគុណម៉ែធំធេងដូចមហាសាគរ រកអ្វីប្រៀបផ្ទឹមគ្មាន\nកូនសូមសំពះបួងសួង សូមឱ្យម៉ែមានសុខភាពល្អ`,
                `[Verse 2]\nរាល់ពេលហត់នឿយនឹងការងារ នឹកដល់ទឹកមុខម៉ែ\nញើសម៉ែស្រក់មួយតំណក់ តម្លៃលើសអ្វីៗទាំងអស់\nកូនចងចាំរាល់ពាក្យប្រៀនប្រដៅ ឱ្យធ្វើជាមនុស្សល្អ\nមិនឱ្យម៉ែត្រូវខកបំណង ព្រោះតែកូនឡើយ`,
                `[Verse 2]\nឆ្នាំនេះចូលឆ្នាំមកដល់ កូននឹងវិលទៅរកម៉ែ\nទិញនំចំណីផ្ញើអ្នកមានគុណ ថ្វាយបង្គំពរជ័យ\nជួបជុំបងប្អូនភូមិផង ហូបបាយជុំគ្នាដ៏មានន័យ\nនេះជាក្ដីសុខពិតប្រាកដ ក្នុងជីវិតកូន`
            ];
            const prePool = [
                `[Pre-Chorus]\nឮសូរសំឡេងម៉ែតាមទូរស័ព្ទ សួរកូនថាញ៉ាំបាយហើយឬនៅ?\nទឹកភ្នែកកូនហូរដោយមិនដឹងខ្លួន នឹកម៉ែណាស់...`,
                `[Pre-Chorus]\nទោះផ្លូវវែងឆ្ងាយរាប់រយគីឡូ ក៏ចិត្តនៅតែ hướng ទៅរកផ្ទះ\nបេះដូងកូននៅក្បែរម៉ែជានិច្ច...`
            ];
            const choPool = [
                `[Chorus]\nម៉ែអើយកូននឹកម៉ែណាស់ នឹកទាំងដំបូន្មាន\nកូនខំតស៊ូធ្វើការងារ ដើម្បីអនាគតថ្លៃថ្លា\nរង់ចាំកូនណាអ្នកម្ដាយ មិនយូរឡើយកូននឹងត្រឡប់\nយកជោគជ័យទៅជូនម៉ែ ជួបជុំគ្រួសារ`,
                `[Chorus]\nគុណម៉ែធ្ងន់ដូចព្រះធរណី កូនឆ្លាក់ជាប់ក្នុងឱរា\nដង្ហើមម៉ែជាពន្លឺជីវិត បំភ្លឺផ្លូវកូនដើរ\nសូមទេវតាថែរក្សាអ្នកម្តាយ ឱ្យមានអាយុយឺនយូរ\nរស់នៅជាម្លប់ដ៏ត្រជាក់ សម្រាប់កូនចៅរៀងទៅ`
            ];
            const briPool = [
                `[Bridge - Emotional Tro & Kloy Flute Harmony]\n(សំឡេងទ្រ និង ខ្លុយរំជួលចិត្ត... នឹកភូមិកំណើត...)\nកូននឹងវិលទៅរកផ្ទះយើងវិញ ម៉ែរង់ចាំកូនណា...`,
                `[Bridge - Gentle Acoustic Strings]\n(ហ្គីតា និងខ្សែសំនៀងស្រុកស្រែ... នឹកម៉ែ...)\nគ្មានកន្លែងណា កក់ក្តៅដូចទ្រូងអ្នកម្តាយឡើយ...`
            ];
            const outPool = [
                `[Outro - Soft Flute Melody]\nកូនស្រឡាញ់ម៉ែ... ស្រឡាញ់រហូត...\n(Fade Out with Kloy Flute...)`,
                `[Outro]\nរង់ចាំកូនណាអ្នកម្តាយ... កូននឹងវិលត្រឡប់...\n(Fade Out...)`
            ];

            verses.push(v1Pool[Math.floor(Math.random() * v1Pool.length)]);
            verses.push(v2Pool[Math.floor(Math.random() * v2Pool.length)]);
            preChorus = prePool[Math.floor(Math.random() * prePool.length)];
            chorus = choPool[Math.floor(Math.random() * choPool.length)];
            bridge = briPool[Math.floor(Math.random() * briPool.length)];
            outro = outPool[Math.floor(Math.random() * outPool.length)];

        } else if (isMotivational) {
            const v1Pool = [
                `[Verse 1]\nទោះផ្លូវខាងមុខមានបន្លា ឧបសគ្គរាប់រយរាប់ពាន់\nដួលប៉ុន្មានដងត្រូវតែងើប មិនត្រូវចុះចាញ់ព្រហ្មលិខិត\nញើសហូរស្រក់ដើម្បីក្ដីស្រមៃ ខំប្រឹងតស៊ូឥតឈប់\nថ្ងៃស្អែកនឹងជាថ្ងៃរបស់យើង ជោគជ័យនឹងមកដល់`,
                `[Verse 1]\nមេឃងងឹតមិនមែនមានន័យថា ព្រះអាទិត្យនឹងលែងរះឡើយ\nជីវិតត្រូវតែដើរទៅមុខ ទោះមានព្យុះភ្លៀងបោកបក់\nក្តាប់ដៃឱ្យណែន ប្រាប់បេះដូងខ្លួនឯងថាកុំភ័យ\nយើងកើតមកដើម្បីឈ្នះ មិនមែនមកដើម្បីចុះចាញ់`,
                `[Verse 1]\nរាល់ស្នាមរបួសលើដងខ្លួន ជាមេរៀនដ៏មានតម្លៃ\nកុំឱ្យពាក្យមើលងាយរបស់អ្នកដទៃ មកកាត់សេចក្តីវាសនាយើង\nបោះជំហានទៅមុខដោយមោទនភាព ជឿជាក់លើសមត្ថភាព\nពន្លឺជោគជ័យកំពុងរង់ចាំ នៅចុងបញ្ចប់នៃផ្លូវ`
            ];
            const v2Pool = [
                `[Verse 2]\nការរិះគន់រាប់ពាន់សម្តី ក្លាយជាកម្លាំងរុញច្រាន\nឱ្យយើងកាន់តែរឹងមាំ មិនទន់ជ្រាយដូចពីមុន\nរាល់ដំណក់ញើសដែលបានស្រក់ នឹងក្លាយជាពេជ្រចាំងចែង\nស្មាមញញឹមនៃជ័យជម្នះ នឹងបំភ្លឺជីវិត`,
                `[Verse 2]\nថ្ងៃនេះហត់នឿយស្ទើរដាច់ខ្យល់ តែថ្ងៃស្អែកនឹងស្រស់បំព្រង\nគ្មានជោគជ័យណាដែលស្រួល គ្មានផ្លូវណាដែលរាបស្មើ\nស៊ូទ្រាំនឹងការលំបាក ដើម្បីក្ដីសុខគ្រួសារ\nឱ្យពិភពលោកបានដឹង ថាយើងជាមនុស្សរឹងមាំ`,
                `[Verse 2]\nសម្លឹងមើលទៅលើមេឃា ដឹងថាក្តីស្រមៃនៅទីនោះ\nលាតស្លាបហោះហើរឡើង ឆ្លងកាត់រាល់ពពកខ្មៅ\nគ្មានអ្វីអាចបញ្ឈប់យើងបានឡើយ ឱ្យតែបេះដូងនៅតែលោត\nឆ្ពោះទៅមុខជានិច្ច គ្មានថ្ងៃងាកក្រោយ`
            ];
            const prePool = [
                `[Pre-Chorus]\nជឿជាក់លើខ្លួនឯង ជឿលើកម្លាំងចិត្ត\nគ្មានអ្វីដែលថាមិនអាចធ្វើបាន បើយើងមិនបោះបង់!`,
                `[Pre-Chorus]\nក្រោកឡើង! បោសធូលីដីចេញ\nហើយបន្តដំណើរឆ្ពោះទៅកាន់ជ័យជម្នះ!`
            ];
            const choPool = [
                `[Chorus]\nក្រោកឈរឡើង! ហោះហើរទៅលើមេឃាក្រឡាស់\nបញ្ចេញពន្លឺក្នុងចិត្ត ឱ្យលោកដឹងថាយើងខ្លាំង\nទោះខ្យល់ព្យុះបក់បោក ក៏មិនរាថយ\nយើងជាអ្នកចម្បាំង ក្តោបក្តាប់ជ័យជម្នះក្នុងដៃ!`,
                `[Chorus]\nមិនចុះចាញ់! មិនរាថយ! ឆ្ពោះទៅមុខឥតឈប់\nរាល់ឧបសគ្គជាស្ពាន ចម្លងយើងទៅរកគោលដៅ\nស្រែកឱ្យកក្រើកមេឃ ថាយើងធ្វើបានហើយ\nជ័យជម្នះជារបស់យើង ជារៀងរហូត!`
            ];
            const briPool = [
                `[Bridge - Powerful Rock Guitar Solo & Heavy Drums]\n(ហ្គីតាវាយយ៉ាងកក្រើក... បង្ហាញភាពក្លាហាន...)\nស្រែកឱ្យអស់ពីចិត្ត! នេះជាពេលវេលារបស់យើង!`,
                `[Bridge - Epic Orchestral Drop & Drums]\n(ស្គរធំទូងបោកបន្លឺ... កម្លាំងចិត្តពុះកញ្ជ្រោល...)\nគ្មានអ្វីរារាំងយើងបានឡើយ!`
            ];
            const outPool = [
                `[Outro - Triumphant Ending]\nជ័យជម្នះជារបស់យើង! កុំចុះចាញ់!\n(Big Final Drum Hit & Crash)`,
                `[Outro]\nយើងជាអ្នកឈ្នះ... ជានិច្ចនិរន្តរ៍!\n(Rock Guitar Sustain...)`
            ];

            verses.push(v1Pool[Math.floor(Math.random() * v1Pool.length)]);
            verses.push(v2Pool[Math.floor(Math.random() * v2Pool.length)]);
            preChorus = prePool[Math.floor(Math.random() * prePool.length)];
            chorus = choPool[Math.floor(Math.random() * choPool.length)];
            bridge = briPool[Math.floor(Math.random() * briPool.length)];
            outro = outPool[Math.floor(Math.random() * outPool.length)];

        } else if (isParty) {
            const v1Pool = [
                `[Verse 1]\nសូរស័ព្ទស្គរដៃបន្លឺកងរំពង បងប្អូនជួបជុំភូមិផងរបងជាមួយ\nផ្កាឈូកផ្ការំដួលរីកស្គុសស្គាយ ស្រីស្រស់ប្រិមប្រិយញញឹមស្រស់ថ្លា\nតោះនាំគ្នារាំកម្សាន្ត ចង្វាក់រាំវង់សារ៉ាវ៉ាន់\nភ្លេចទុក្ខកង្វល់ឱ្យអស់ រីករាយគ្រប់គ្នា`,
                `[Verse 1]\nរនាតឯកបន្លឺភ្លេងរន្ថើន ពិរោះរណ្តំចិត្តកាយ\nបងប្អូនជិតឆ្ងាយមកជួបជុំគ្នា សើចសប្បាយក្អាកក្អាយ\nដៃរាំជើងឈានទៅតាមចង្វាក់ ស្គរដៃតាក់ទែនទែនតាក់\nរាំលេងចូលឆ្នាំថ្មី សិរីសួស្តីកើតមាន`,
                `[Verse 1]\nមេឃស្រឡះខ្យល់បក់ត្រជាក់ ក្លិនផ្កាក្រអូបឈ្ងុយឈ្ងប់\nកម្លោះក្រមុំតុបតែងខ្លួនយ៉ាងស្អាត មកវត្តជួបជុំគ្នា\nស្រីស្អាតញញឹមស្រស់ ហុចដៃមកបបួលរាំ\nតោះរាំទាំងអស់គ្នា កុំនៅអៀនខ្មាសធ្វើអ្វី`
            ];
            const v2Pool = [
                `[Verse 2]\nយុវជនយុវតីស្លៀកពាក់ចម្រុះពណ៌ រាំបណ្ដាក់គ្នាជារង្វង់មូល\nលេងល្បែងប្រជាប្រិយចោលឈូង បោះអង្គញ់ និងទាញព្រ័ត្រ\nសើចសប្បាយក្អាកក្អាយ ពេញភូមិកំណើត\nមោទនភាពជាតិខ្មែរ ប្រពៃណីថ្លៃថ្លា`,
                `[Verse 2]\nចង្វាក់កន្ទ្រាក់អារម្មណ៍ ធ្វើឱ្យជើងចង់តែរាំ\nអ្នកណានៅអង្គុយស្ងៀម សូមអញ្ជើញចូលមករាំវង់\nរាំកម្សាន្តឱ្យសប្បាយ ឱ្យផុតទុក្ខផុតភ័យ\nរកស៊ីទទួលទានមានបាន គ្រប់ៗក្រុមគ្រួសារ`,
                `[Verse 2]\nចាស់ៗញញឹមសម្លឹងមើលកូនចៅ រាំលេងដោយសាមគ្គី\nស្រុកទេសមានសុខសន្តិភាព ប្រជាជនរស់នៅក្សេមក្សាន្ត\nលើកកែវទឹកត្នោតជូរ ជូនពរគ្នាទៅវិញទៅមក\nសប្បាយរីករាយពេញមួយឆ្នាំ គ្មានទុក្ខសោកសៅ`
            ];
            const prePool = [
                `[Pre-Chorus]\nតោះរាំ! តោះរាំ! កុំនៅឈរស្ងៀម\nតាក់ទែនទែនតាក់ រាំលេងសប្បាយ!`,
                `[Pre-Chorus]\nតោះចូលមករាំវង់ទាំងអស់គ្នា!\nសប្បាយៗ ចូលឆ្នាំថ្មីប្រពៃណីជាតិ!`
            ];
            const choPool = [
                `[Chorus]\nរាំទៅៗ កុំនៅអៀនខ្មាស\nចូលឆ្នាំថ្មីហើយ សប្បាយណាស់ណា\nជូនពរពុកម៉ែ បងប្អូនជិតឆ្ងាយ\nសុខសប្បាយ រកស៊ីមានបានគ្រប់គ្នា!`,
                `[Chorus]\nសារ៉ាវ៉ាន់រាំវង់ កន្ត្រាក់អារម្មណ៍រំភើប\nរាំមួយយប់ទល់ភ្លឺ ក៏មិនចេះហត់នឿយ\nសប្បាយរីករាយជួបជុំគ្រួសារខ្មែរ\nសិរីសួស្តីជ័យមង្គល កើតមានរៀងទៅ!`
            ];
            const briPool = [
                `[Bridge - Festive Percussion, Roneat & Cheering]\n(ហោរ... ជយោ! រាំកន្ត្រាក់អារម្មណ៍... សប្បាយៗ!)\n(សំឡេងស្គរដៃ និងរនាតឯករន្ថើនយ៉ាងរស់រវើក...)`,
                `[Bridge - Upbeat Tro & Drum Solo]\n(សំឡេងទ្រ និងស្គរវាយយ៉ាងកក្រើក...)\nតោះបងប្អូន! រាំទាំងអស់គ្នា!`
            ];
            const outPool = [
                `[Outro - Fast Upbeat Finish]\nជយោចូលឆ្នាំថ្មី! សប្បាយៗ!\n(Drum Roll & Cymbal Crash)`,
                `[Outro]\nជួបគ្នាឆ្នាំក្រោយទៀតណា! សុខសប្បាយគ្រប់គ្នា!\n(Big Traditional Cymbal Finish)`
            ];

            verses.push(v1Pool[Math.floor(Math.random() * v1Pool.length)]);
            verses.push(v2Pool[Math.floor(Math.random() * v2Pool.length)]);
            preChorus = prePool[Math.floor(Math.random() * prePool.length)];
            chorus = choPool[Math.floor(Math.random() * choPool.length)];
            bridge = briPool[Math.floor(Math.random() * briPool.length)];
            outro = outPool[Math.floor(Math.random() * outPool.length)];

        } else if (isSad) {
            const v1Pool = [
                `[Verse 1]\nភ្លៀងធ្លាក់ស្រក់កាត់បង្អួចចាស់ ដូចទឹកភ្នែកហូរមិនឈប់\nការចងចាំរឿងរ៉ាវគ្រប់យ៉ាង នៅតែដិតជាប់រាល់យប់\nធ្លាប់ដើរកាត់ភ្លៀងជាមួយគ្នា ឥឡូវនៅសល់តែបង\nពាក្យថាស្នេហ៍ដែលអូនធ្លាប់ផ្ដល់ រសាត់បាត់អស់ហើយថ្លៃ`,
                `[Verse 1]\nរាត្រីស្ងាត់ជ្រងំគ្មានរូបថ្លៃ បេះដូងរងាញាប់ញ័រ\nអង្គុយចាំមនុស្សម្នាក់ដែលដើរចេញ គ្មានសូម្បីពាក្យលា\nខ្យល់រាត្រីបក់ផាត់នាំភាពឯកា មកចាក់ដោតក្នុងឱរា\nតើពេលនេះថ្លៃនៅទីណា មានដឹងថាបងឈឺទេ?`,
                `[Verse 1]\nមើលទៅមេឃខ្មៅងងឹតសូន្យសុង គ្មានពន្លឺតារា\nដូចចិត្តបងដែលបាត់បង់អូន គ្មានសល់ក្ដីមេត្តា\nគ្រប់ដង្ហើមដែលធ្លាប់ដកដង្ហើមរួមគ្នា ឥឡូវក្លាយជាផ្សែង\nសល់តែស្លាកស្នាមការឈឺចាប់ ដែលបងត្រូវទ្រាំតែឯង`
            ];
            const v2Pool = [
                `[Verse 2]\nអង្គុយមើលរូបថតចាស់ៗ ដែលយើងធ្លាប់សើចជាមួយគ្នា\nពេលនេះក្លាយជារឿងអតីត ដែលគ្មានថ្ងៃវិលត្រឡប់\nខំប្រាប់បេះដូងឱ្យបំភ្លេច តែចិត្តមិនព្រមស្ដាប់\nនៅតែនឹក នៅតែស្រឡាញ់ ទោះអូនក្បត់ចិត្ត`,
                `[Verse 2]\nព្យាយាមបំភ្លេចស្នាមញញឹមអូន តែភ្នែកនៅតែមើលឃើញ\nគ្រប់ទីកន្លែងដែលធ្លាប់ទៅ សុទ្ធតែក្លាយជារឿងអតីត\nចង់ស្រែកសួរទៅកាន់មេឃា ហេតុអ្វីព្រហ្មលិខិតចងកម្ម\nឱ្យជួបមនុស្សដែលស្រឡាញ់អស់ពីចិត្ត រួចបំបែកចាកឆ្ងាយ`,
                `[Verse 2]\nដបស្រា និងផ្សែងបារី មិនអាចជួយរំងាប់ចិត្ត\nរាល់យប់នៅតែយល់សប្តិឃើញអូន ត្រឡប់មកក្បែរប្រាណ\nតែពេលភ្ញាក់ឡើងសល់តែខ្នើយទទឹកទឹកភ្នែក\nទទួលស្គាល់ការពិតដ៏ជូរចត់ ថាអូនលែងជារបស់បង`
            ];
            const prePool = [
                `[Pre-Chorus]\nតើបងធ្វើខុសអ្វី ទើបអូនចាកចេញគ្មានស្ដាយ?\nទុកឱ្យបេះដូងមួយនេះ រងាវខ្លោចផ្សា...`,
                `[Pre-Chorus]\nបើដឹងថាស្នេហានឹងត្រូវចប់បែបនេះ...\nបងនឹងមិនជ្រើសរើសឱ្យយើងស្គាល់គ្នាឡើយ...`
            ];
            const choPool = [
                `[Chorus]\nទឹកភ្នែកហូរស្រក់កាត់ថ្ពាល់ លាយឡំនឹងទឹកភ្លៀង\nឈឺចាប់ឥតល្ហែ ពេលស្នេហ៍ត្រូវប្រេះឆា\nជូនពរឱ្យអូនបានសុខ ជាមួយអ្នកថ្មីថ្លៃថ្លា\nទុកការឈឺផ្សា ឱ្យបងជាអ្នករ៉ាប់រង`,
                `[Chorus]\nលាហើយស្នេហាដែលធ្លាប់កក់ក្តៅ\nលាហើយដួងចិត្តដែលបងធ្លាប់ស្រឡាញ់លើសជីវិត\nទោះបីបេះដូងត្រូវបែកបាក់មួយពាន់បំណែក\nក៏នៅតែចងចាំថា ធ្លាប់បានស្រឡាញ់អូន`,
                `[Chorus]\nបេះដូងរងគ្រោះកណ្តាលរាត្រី\nស្រែកហៅឈ្មោះអូនទាំងទឹកភ្នែកហូរ\nតើអូនដឹងទេ ថាបងនឹកអូនប៉ុណ្ណា?\nរឿងរ៉ាវស្នេហាយើង ចប់ដោយគ្មានពាក្យលា`
            ];
            const briPool = [
                `[Bridge - Crying Guitar & Violin Solo]\n(ហ្គីតា និងវីយូឡុងទួញសោកយ៉ាងរំជួលចិត្ត...)\nបើសិនថ្ងៃណាមួយអូនខកបំណង...\nសូមចាំថាបងនៅតែនៅត្រង់នេះ...\nទោះដឹងថាមិនអាចត្រឡប់...`,
                `[Bridge - Emotive Acoustic Interlude]\n(សំឡេងភ្លៀងលាយឡំសំឡេងហ្គីតាយឺតៗ...)\nពេលវេលាអាចព្យាបាលរបួស...\nតែមិនអាចលុបឈ្មោះអូនចេញពីបេះដូងបានឡើយ...`
            ];
            const outPool = [
                `[Outro - Slow Piano & Fade Out]\nលាហើយស្នេហា... លាហើយមនុស្សដែលបងស្រឡាញ់...\n(Fade Out with Rain Sounds...)`,
                `[Outro]\nគេងឱ្យស្រួលណាម្ចាស់បេះដូងបង...\nលាហើយរហូត...\n(Fade Out...)`
            ];

            verses.push(v1Pool[Math.floor(Math.random() * v1Pool.length)]);
            verses.push(v2Pool[Math.floor(Math.random() * v2Pool.length)]);
            preChorus = prePool[Math.floor(Math.random() * prePool.length)];
            chorus = choPool[Math.floor(Math.random() * choPool.length)];
            bridge = briPool[Math.floor(Math.random() * briPool.length)];
            outro = outPool[Math.floor(Math.random() * outPool.length)];

        } else if (isCafe) {
            verses.push(`[Verse 1]\nក្លិនកាហ្វេឈ្ងុយសាយភាយពេញហាងតូចមួយនេះ\nអង្គុយក្បែរបង្អួចកញ្ចក់ មើលមនុស្សដើរកាត់ទៅមក\nភ្លេងឡូហ្វាយបន្លឺឡើងតិចៗ នាំអារម្មណ៍ឱ្យស្រមើស្រមៃ\nនឹកឃើញរឿងរ៉ាវ "${topicWord}" ដែលដក់ជាប់ក្នុងចិត្ត`);
            verses.push(`[Verse 2]\nកាហ្វេមួយកែវ រសជាតិល្វីងតែបង្កប់ភាពផ្អែម\nដូចស្នេហាគ្រាដំបូង ដែលមានទាំងសើចទាំងយំ\nសៀវភៅមួយក្បាលបើកចំហរ រង់ចាំមនុស្សពិសេស\nតែពេលនេះមានតែរូបបង និងកាហ្វេត្រជាក់`);
            preChorus = `[Pre-Chorus]\nតើពេលណាទើបអូនដើរកាត់ទ្វារមួយនេះ?\nមកអង្គុយក្បែរបង ដូចគ្រាមុន...`;
            chorus = `[Chorus]\nរាត្រីកាហ្វេ និងការចងចាំដ៏ស្រស់បំព្រង\nរសជាតិកាហ្វេកក់ក្តៅ លួងលោមបេះដូងឯកា\nសូមឱ្យភ្លេងមួយបទនេះ រសាត់ទៅដល់ចិន្តា\nប្រាប់ថាបងនៅតែចាំ នៅហាងកាហ្វេចាស់`;
            bridge = `[Bridge - Soft Saxophone & Acoustic Solo]\n(សំឡេងសាក់សូហ្វូន និងហ្គីតារ៉ូមែនទិក...)\nទោះពេលនេះនៅម្នាក់ឯង...\nតែក្តីសុខនៅតែមានក្នុងកែវកាហ្វេ...`;
            outro = `[Outro - Mellow Piano]\nកាហ្វេជិតអស់ហើយ... តែការចងចាំនៅតែដដែល...\n(Fade Out...)`;

        } else {
            const v1Pool = [
                `[Verse 1]\nរាល់ពេលឃើញស្នាមញញឹមថ្លៃ បេះដូងរំភើបឥតឧបមា\nកែវភ្នែកស្រទន់ដូចតារា បំភ្លឺចិន្តាឱ្យភ្លឺថ្លា\nដើរកាត់ខ្យល់ត្រជាក់រាត្រី មានរូបថ្លៃក្បែរប្រាណ\nក្ដីសុខសាមញ្ញតែមានន័យ គ្មានអ្វីផ្ទឹមបាន`,
                `[Verse 1]\nពន្លឺថ្ងៃរះបំភ្លឺលើផែនដី ដូចស្នាមញញឹមអូនបំភ្លឺបេះដូងបង\nគ្រប់ជំហានដែលយើងដើរក្បែរគ្នា ពេញដោយក្តីស្រឡាញ់កក់ក្តៅ\nមិនដែលគិតថានឹងបានជួប មនុស្សដែលល្អដូចជាអូន\nកែវភ្នែកមួយគូនោះ ធ្វើឱ្យបងលង់ស្នេហ៍រាល់ថ្ងៃ`,
                `[Verse 1]\nរដូវផ្ការីកបានមកដល់ នាំមកនូវក្លិនក្រអូបស្នេហា\nមានអូននៅក្បែរប្រាណ ពិភពលោកទាំងមូលប្រែជាស្រស់បំព្រង\nសំឡេងសើចដ៏ពិរោះរបស់អូន ដូចជាតន្ត្រីបំពេចិត្ត\nបងសន្យាថានឹងថែអូន មិនឱ្យនឿយណាយឡើយ`
            ];
            const v2Pool = [
                `[Verse 2]\nពេលមានទុក្ខកង្វល់ក្នុងចិត្ត ស្នាមញញឹមអូនលួងលោម\nរាល់ពាក្យផ្អែមល្ហែមដូចទឹកឃ្មុំ ថ្នាក់ថ្នមចិត្តកាយ\nសូមអរគុណមេឃដែលប្រទានអូនមកឱ្យបង\nមិនឱ្យរបូតបាត់បង់ ស្នេហ៍ដ៏មានន័យ`,
                `[Verse 2]\nទោះមេឃមានភ្លៀងផ្គររន្ទះ ក៏បងមិនដែលភ័យតក់ស្លុត\nឱ្យតែមានដៃអូនក្តាប់ជាប់ បងអាចឆ្លងកាត់គ្រប់ឧបសគ្គ\nក្តីស្រឡាញ់មួយនេះ នឹងរីកធំធាត់តាមពេលវេលា\nគ្មានថ្ងៃសាបរលាបឡើយ ម្ចាស់ស្នេហ៍បង`,
                `[Verse 2]\nផ្កាយលើមេឃរាប់លានដួង មិនអាចផ្ទឹមនឹងសម្រស់អូន\nចិត្តស្មោះមួយនេះប្រគល់ជូន គ្មានលាក់លៀមសូម្បីបន្តិច\nសូមសច្ចាចំពោះមុខដួងចន្ទ ស្រឡាញ់អូនមួយជីវិត\nទោះសក់ស្កូវធ្មេញបាក់ ក៏បងនៅតែក្បែរអូន`
            ];
            const prePool = [
                `[Pre-Chorus]\nទោះបីថ្ងៃស្អែកទៅជាយ៉ាងណា\nចិត្តមួយនេះសន្យា ស្រឡាញ់តែអូន...`,
                `[Pre-Chorus]\nបេះដូងមួយនេះលោតដើម្បីតែអូន\nគ្រប់ដង្ហើមចេញចូល មានតែឈ្មោះអូន...`
            ];
            const choPool = [
                `[Chorus]\nអូនជាដង្ហើម ជាក្ដីសុខក្នុងជីវិត\nស្រឡាញ់ស្មោះពិត គ្មានថ្ងៃប្រែប្រួលឡើយ\nកាន់ដៃបងឆ្លងកាត់រាល់ឧបសគ្គកន្លង\nមានតែរូបអូន ជាម្ចាស់បេះដូងបងរហូត`,
                `[Chorus]\nស្រឡាញ់អូនលើសអ្វីៗទាំងអស់នៅលើលោកីយ៍\nបេះដូងមួយនេះសច្ចា ថែរក្សាអូនរហូតដល់ចាស់\nទោះផ្លូវខាងមុខវែងឆ្ងាយលំបាកយ៉ាងណា\nក៏យើងដើរទៅមុខជាមួយគ្នា គ្មានថ្ងៃបែក`,
                `[Chorus]\nស្នេហ៍ពិតដែលបងស្វែងរក ឥឡូវបានជួបហើយ\nគឺរូបអូនហ្នឹងហើយ ដួងកែវភ្នែករបស់បង\nសូមអរគុណព្រហ្មលិខិត ដែលនាំយើងឱ្យជួបគ្នា\nបងនឹងស្រឡាញ់អូន ឱ្យអស់ពីបេះដូង`
            ];
            const briPool = [
                `[Bridge - Traditional Flute & Acoustic Strings Solo]\n(ភ្លេងខ្លុយ និងហ្គីតារំជួលចិត្ត...)\nទោះមេឃរលាយ ផ្កាយរលត់អស់ពីដួងចិត្ត...\nក្ដីស្រឡាញ់ពិត នៅតែមានសម្រាប់អូន...`,
                `[Bridge - Emotional Vocal Harmony]\n(សំឡេងច្រៀងឆ្លើយឆ្លងយ៉ាងស្រទន់...)\nគ្មានអ្វីអាចបំបែកស្នេហាយើងបានឡើយ...\nបងនិងអូន... ជារៀងរហូត...`
            ];
            const outPool = [
                `[Outro - Gentle Piano & Fade Out]\nស្រឡាញ់អូន... ជារៀងរហូត...\n(Fade Out...)`,
                `[Outro]\nកាន់ដៃគ្នា... ដើរដល់ចុងបញ្ចប់នៃជីវិត...\n(Gentle Acoustic Fade Out...)`
            ];

            verses.push(v1Pool[Math.floor(Math.random() * v1Pool.length)]);
            verses.push(v2Pool[Math.floor(Math.random() * v2Pool.length)]);
            preChorus = prePool[Math.floor(Math.random() * prePool.length)];
            chorus = choPool[Math.floor(Math.random() * choPool.length)];
            bridge = briPool[Math.floor(Math.random() * briPool.length)];
            outro = outPool[Math.floor(Math.random() * outPool.length)];
        }

        if (cleanTopic) {
            verses[0] = `[Intro - Acoustic Warm Melody]\n(បទចម្រៀងអំពី៖ "${cleanTopic}")\n\n` + verses[0].replace('រាល់ពេលឃើញ', `នឹកឃើញរឿងរ៉ាវ "${cleanTopic}" `);
        } else {
            verses[0] = `[Intro - Soft Acoustic Melody]\n(ជួបអូនគ្រាដំបូង...)\n\n` + verses[0];
        }

        const fullLyrics = [
            verses[0],
            preChorus,
            chorus,
            verses[1],
            bridge,
            chorus,
            outro
        ].join('\n\n');

        const enforcedLyrics = enforceVocalLyricsTags(fullLyrics, vocalProf);

        return {
            title: primaryTitle,
            alternativeTitles: altTitles,
            style: dynamicStyle,
            lyrics: enforcedLyrics
        };
    }

    function enablePickAndPasteMode() {
        document.body.style.cursor = 'crosshair';
        showToast('🎯 សូមចុចលើប្រអប់ (Title, Lyrics, ឬ Style) ណាមួយក្នុង Suno ដើម្បីបិទភ្ជាប់ភ្លាមៗ!', 'warn');

        const overlayHandler = function(e) {
            const target = e.target;
            const editable = target.closest('textarea, input, [contenteditable="true"], [role="textbox"], div[data-lexical-editor="true"]');
            if (editable && !editable.id.startsWith('suno-')) {
                e.preventDefault();
                e.stopPropagation();

                const title = document.getElementById('suno-title-output').value;
                const lyrics = document.getElementById('suno-lyrics-output').value;
                const style = document.getElementById('suno-style-output').value;

                const ph = (editable.placeholder || '').toLowerCase();
                const aria = (editable.getAttribute('aria-label') || '').toLowerCase();
                const isLexical = editable.getAttribute('data-lexical-editor') === 'true' || aria.includes('lyrics');

                if (ph.includes('title') || aria.includes('title')) {
                    setElementValue(editable, title);
                    showToast('✓ បានបញ្ចូលចំប្រអប់ Song Title (Optional)!', 'success');
                } else if (ph.includes('style') || ph.includes('dangdut') || ph.includes('violin') || aria.includes('style')) {
                    setElementValue(editable, style);
                    showToast('✓ បានបញ្ចូលចំប្រអប់ Styles!', 'success');
                } else if (isLexical || aria.includes('lyrics') || ph.includes('lyrics')) {
                    setElementValue(editable, lyrics);
                    showToast('✓ បានបញ្ចូលចំប្រអប់ Lyrics editor!', 'success');
                } else {
                    setElementValue(editable, lyrics);
                    showToast('✓ បានបញ្ចូលទៅក្នុងប្រអប់!', 'success');
                }

                cleanup();
            }
        };

        const escHandler = function(e) {
            if (e.key === 'Escape') cleanup();
        };

        const cleanup = function() {
            document.body.style.cursor = 'default';
            document.removeEventListener('click', overlayHandler, true);
            document.removeEventListener('keydown', escHandler, true);
        };

        setTimeout(() => {
            document.addEventListener('click', overlayHandler, true);
            document.addEventListener('keydown', escHandler, true);
        }, 100);
    }

    // =========================================================================
    // 9. RECENT SONGS LIST & DOWNLOAD UI
    // =========================================================================
    function updateRecentSongsUI() {
        const listContainer = document.getElementById('suno-recent-songs-list');
        if (!listContainer) return;

        const clips = Array.from(clipDatabase.values())
            .filter(c => c.title && c.status === 'complete')
            .sort((a, b) => (b.discoveredAt || 0) - (a.discoveredAt || 0))
            .slice(0, 8);

        if (clips.length === 0) {
            listContainer.innerHTML = `<div style="font-size:11px; color:#888; text-align:center; padding:8px;">មិនទាន់មានចម្រៀងទើបបង្កើតនៅឡើយទេ</div>`;
            return;
        }

        listContainer.innerHTML = clips.map(clip => {
            const isDownloaded = downloadedClips.has(clip.id);
            return `
                <div style="display:flex; align-items:center; justify-content:space-between; background:#1c1c24; border:1px solid #2e2e3a; border-radius:6px; padding:6px 10px; gap:8px;">
                    <div style="flex:1; min-width:0;">
                        <div style="font-size:12px; font-weight:600; color:#fff; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${clip.title}</div>
                        <div style="font-size:10px; color:#888;">${clip.duration ? Math.floor(clip.duration/60) + ':' + String(Math.floor(clip.duration%60)).padStart(2,'0') : 'រួចរាល់'} · ${isDownloaded ? '✅ បានទាញយក' : '⚡ ត្រៀមទាញយក'}</div>
                    </div>
                    <button class="suno-dl-wav-btn" data-id="${clip.id}" data-title="${clip.title}" style="background:${isDownloaded ? '#243b2e' : 'linear-gradient(135deg, #10b981, #059669)'}; border:none; border-radius:4px; color:${isDownloaded ? '#10b981' : '#fff'}; font-size:11px; font-weight:700; padding:5px 8px; cursor:pointer; display:flex; align-items:center; gap:4px; white-space:nowrap;">
                        ${isDownloaded ? '✓ WAV' : '⬇️ ទាញ WAV'}
                    </button>
                </div>
            `;
        }).join('');

        // Attach click listeners to download buttons
        listContainer.querySelectorAll('.suno-dl-wav-btn').forEach(btn => {
            btn.onclick = () => {
                const id = btn.getAttribute('data-id');
                const title = btn.getAttribute('data-title');
                const clip = clipDatabase.get(id);
                downloadClipAsWav(id, title, clip?.audio_url);
            };
        });
    }

    function updateDownloadedUI(clipId) {
        updateRecentSongsUI();

        // Auto-Check and deduplicate sibling clip titles in real-time
        if (!isInitialLoad && typeof autoCheckAndDedupSiblingClips === 'function') {
            setTimeout(autoCheckAndDedupSiblingClips, 1800);
        }
    }

    // =========================================================================
    // 10. STUDIO UI (Smart Floating Dock + Unified Master Drawer + Native Inline Bar)
    // =========================================================================
    function initStudioUI() {
        if (document.getElementById('suno-studio-dock')) {
            window.sunoStudioLoaded = true;
            return;
        }
        window.sunoStudioLoaded = true;

        // --- 1. Inject Suno Matching CSS Theme & Styles (STYLE iOS 27 ឆ្លាតវៃ) ---
        let styleTag = document.getElementById('suno-studio-css');
        if (!styleTag) {
            styleTag = document.createElement('style');
            styleTag.id = 'suno-studio-css';
            document.head.appendChild(styleTag);
        }
        styleTag.textContent = `
            @keyframes sunoPulseGlow {
                0%, 100% { transform: scale(1); opacity: 0.9; }
                50% { transform: scale(1.15); opacity: 1; filter: drop-shadow(0 0 6px #10b981); }
            }
            .suno-pulse-dot {
                width: 7px;
                height: 7px;
                background: #10b981;
                border-radius: 50%;
                box-shadow: 0 0 8px #10b981;
                animation: sunoPulseGlow 2.5s infinite ease-in-out;
                display: inline-block;
            }

            /* --- STANDARD SUNO STUDIO BUTTON STYLES (ស្ទីលធម្មតា) --- */
            /* Authentic Native Suno Dark Aesthetic: clean, flat, high-contrast, professional */
            .suno-btn-standard {
                position: relative;
                border-radius: 8px;
                font-family: inherit;
                font-weight: 600;
                font-size: 13px;
                padding: 7px 14px;
                border: 1px solid #3f3f46;
                background: #18181b;
                color: #f4f4f5;
                cursor: pointer;
                transition: background 0.15s ease, border-color 0.15s ease, transform 0.1s ease;
                display: inline-flex;
                align-items: center;
                justify-content: center;
                gap: 6px;
                outline: none;
            }
            .suno-btn-standard:hover {
                background: #27272a;
                border-color: #52525b;
                color: #ffffff;
            }
            .suno-btn-standard:active {
                transform: scale(0.98);
                background: #141417;
            }
            .suno-btn-primary {
                background: #ea580c;
                border-color: #f97316;
                color: #ffffff;
                font-weight: 700;
            }
            .suno-btn-primary:hover {
                background: #f97316;
                border-color: #fb923c;
                color: #ffffff;
            }
            .suno-btn-emerald {
                background: #059669;
                border-color: #10b981;
                color: #ffffff;
                font-weight: 700;
            }
            .suno-btn-emerald:hover {
                background: #10b981;
                border-color: #34d399;
                color: #ffffff;
            }
            .suno-btn-danger {
                background: #dc2626;
                border-color: #ef4444;
                color: #ffffff;
            }
            .suno-btn-danger:hover {
                background: #ef4444;
                color: #ffffff;
            }
            .suno-btn-glass {
                background: #27272a;
                border: 1px solid #3f3f46;
                color: #e4e4e7;
            }
            .suno-btn-glass:hover {
                background: #3f3f46;
                color: #ffffff;
            }

            .suno-seg-tab {
                flex: 1;
                padding: 8px 14px;
                border-radius: 12px;
                font-size: 12px;
                font-weight: 700;
                cursor: pointer;
                display: flex;
                align-items: center;
                justify-content: center;
                gap: 6px;
                transition: all 0.22s ease;
            }

            .suno-scrollbar::-webkit-scrollbar {
                width: 6px;
            }
            .suno-scrollbar::-webkit-scrollbar-track {
                background: rgba(0, 0, 0, 0.2);
            }
            .suno-scrollbar::-webkit-scrollbar-thumb {
                background: #2a2a36;
                border-radius: 3px;
            }
            .suno-scrollbar::-webkit-scrollbar-thumb:hover {
                background: #3f3f50;
            }
        `;

        // --- 2. Smart Floating Control Dock (Bottom-Right, above the 64px audio player) ---
        let isDockMinimized = localStorage.getItem('suno_dock_minimized') === 'true';

        const dock = document.createElement('div');
        dock.id = 'suno-studio-dock';
        Object.assign(dock.style, {
            position: 'fixed',
            bottom: '74px',
            right: '24px',
            zIndex: '999998',
            background: 'rgba(15, 15, 20, 0.90)',
            backdropFilter: 'blur(22px)',
            webkitBackdropFilter: 'blur(22px)',
            border: '1px solid rgba(255, 255, 255, 0.12)',
            borderRadius: '16px',
            boxShadow: '0 10px 32px rgba(0, 0, 0, 0.65), 0 0 1px rgba(255, 255, 255, 0.15)',
            padding: '5px 8px',
            display: 'flex',
            alignItems: 'center',
            gap: '6px',
            userSelect: 'none',
            fontFamily: 'system-ui, -apple-system, sans-serif',
            transition: 'all 0.3s cubic-bezier(0.16, 1, 0.3, 1)'
        });

        dock.innerHTML = `
            <!-- Brand / Expand trigger -->
            <div id="suno-dock-brand" style="display:flex; align-items:center; gap:6px; padding:4px 8px; cursor:pointer;" title="Suno Studio Hub (ចុចដើម្បីពង្រីក/បង្រួម)">
                <span style="font-size:16px;">✨</span>
                <span style="font-size:12px; font-weight:700; color:#ffffff; letter-spacing:0.3px;">Suno Studio</span>
                <span class="suno-pulse-dot"></span>
            </div>

            <!-- Separator -->
            <div class="suno-dock-full" style="width:1px; height:18px; background:rgba(255,255,255,0.12); margin:0 2px;"></div>

            <!-- Composer Button -->
            <button id="suno-dock-btn-composer" class="suno-btn-hover suno-dock-full" style="background:linear-gradient(135deg, rgba(255, 85, 0, 0.25), rgba(234, 88, 12, 0.25)); border:1px solid #ff5500; border-radius:10px; color:#ffedd5; font-size:12px; font-weight:700; padding:6px 12px; cursor:pointer; display:flex; align-items:center; gap:6px; box-shadow:0 2px 8px rgba(255,85,0,0.3);" title="ចុចដើម្បីឱ្យ AI និពន្ធចម្រៀង និងបញ្ចូលក្នុង Suno ភ្លាមៗ">
                <span>🎵</span>
                <span>AI និពន្ធចម្រៀង</span>
            </button>

            <!-- WAV Button -->
            <button id="suno-dock-btn-wav" class="suno-btn-hover suno-dock-full" style="background:rgba(2, 132, 199, 0.12); border:1px solid rgba(2, 132, 199, 0.35); border-radius:10px; color:#38bdf8; font-size:12px; font-weight:700; padding:6px 12px; cursor:pointer; display:flex; align-items:center; gap:6px;">
                <span>🔊</span>
                <span>ទាញ WAV</span>
                <span id="suno-dock-wav-status" style="font-size:9px; font-weight:800; padding:2px 6px; border-radius:8px; background:${autoDownloadWav ? 'rgba(16,185,129,0.2)' : 'rgba(255,255,255,0.08)'}; color:${autoDownloadWav ? '#10b981' : '#a1a1aa'}; border:1px solid ${autoDownloadWav ? 'rgba(16,185,129,0.4)' : 'rgba(255,255,255,0.1)'};">
                    ${autoDownloadWav ? 'Auto ON' : 'OFF'}
                </span>
            </button>

            <!-- Separator -->
            <div class="suno-dock-full" style="width:1px; height:18px; background:rgba(255,255,255,0.12); margin:0 2px;"></div>

            <!-- Auto-Loop Producer Button -->
            <button id="suno-dock-btn-loop" class="suno-btn-hover suno-dock-full" style="background:linear-gradient(135deg, rgba(139, 92, 246, 0.35), rgba(124, 58, 237, 0.35)); border:1px solid #8b5cf6; border-radius:10px; color:#f5f3ff; font-size:12px; font-weight:700; padding:6px 12px; cursor:pointer; display:flex; align-items:center; gap:6px; box-shadow:0 2px 10px rgba(139,92,246,0.35);" title="បើកផ្ទាំងបញ្ជា និពន្ធ និងបង្កើតចម្រៀងវិលជុំស្វ័យប្រវត្តិ (Auto-Loop Producer)">
                <span id="suno-dock-loop-icon">🔁</span>
                <span>វិលជុំស្វ័យប្រវត្តិ</span>
                <span id="suno-dock-loop-status" style="font-size:9px; font-weight:800; padding:2px 5px; border-radius:6px; background:rgba(255,255,255,0.08); color:#cbd5e1; border:1px solid rgba(255,255,255,0.1);">OFF</span>
            </button>

            <!-- Batch Playlist Button -->
            <button id="suno-dock-btn-playlist" class="suno-btn-hover suno-dock-full" style="background:rgba(168, 85, 247, 0.15); border:1px solid rgba(168, 85, 247, 0.4); border-radius:10px; color:#e9d5ff; font-size:12px; font-weight:700; padding:6px 11px; cursor:pointer; display:flex; align-items:center; gap:5px;" title="ជ្រើសរើស 10/14/18 បទ និងបង្កើត Playlist ស្វ័យប្រវត្តិ">
                <span>📁</span>
                <span>Playlist</span>
                <span id="suno-dock-playlist-badge" style="font-size:9px; font-weight:800; padding:2px 5px; border-radius:6px; background:rgba(255,255,255,0.08); color:#cbd5e1; border:1px solid rgba(255,255,255,0.1);">14បទ</span>
            </button>

            <!-- Clear Inputs Button -->
            <button id="suno-dock-btn-clear" class="suno-btn-hover suno-dock-full" style="background:rgba(239, 68, 68, 0.12); border:1px solid rgba(239, 68, 68, 0.35); border-radius:10px; color:#fca5a5; font-size:12px; font-weight:700; padding:6px 10px; cursor:pointer; display:flex; align-items:center; gap:5px;" title="លុបសម្អាត Lyrics, Styles, និង Title">
                <span>🗑️</span>
                <span>លុប</span>
            </button>

            <!-- Auto-Fill Quick Action -->
            <button id="suno-dock-btn-autofill" class="suno-btn-hover suno-dock-full" style="background:linear-gradient(135deg, #10b981, #059669); border:none; border-radius:10px; color:#ffffff; font-size:12px; font-weight:700; padding:6px 12px; cursor:pointer; display:flex; align-items:center; gap:5px; box-shadow:0 3px 10px rgba(16,185,129,0.35);" title="បញ្ចូល Title + Style + Lyrics ចូល Suno ភ្លាមៗ">
                <span>⚡</span>
                <span>Auto-Fill</span>
            </button>

            <!-- Generate New Quick Action -->
            <button id="suno-dock-btn-gen" class="suno-btn-hover suno-dock-full" style="background:linear-gradient(135deg, #ff5500, #ea580c); border:none; border-radius:10px; color:#ffffff; font-size:12px; font-weight:800; padding:7px 14px; cursor:pointer; display:flex; align-items:center; gap:6px; box-shadow:0 3px 12px rgba(255,85,0,0.45);" title="ចុចបង្កើត ចំណងជើង + ទំនុកច្រៀង + ស្ទីលបទភ្លេង ភ្លាមៗ">
                <span style="font-size:14px;">✨</span>
                <span>បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីលបទភ្លេង</span>
            </button>

            <!-- Minimize Button -->
            <button id="suno-dock-btn-min" class="suno-btn-hover" style="background:rgba(255,255,255,0.06); border:1px solid rgba(255,255,255,0.1); border-radius:8px; color:#a1a1aa; font-size:12px; width:26px; height:26px; cursor:pointer; display:flex; align-items:center; justify-content:center; margin-left:2px;" title="បង្រួម / ពង្រីក Dock">
                ${isDockMinimized ? '➕' : '—'}
            </button>
        `;

        // Backward compatibility proxy elements for host
        const proxyToggle = document.createElement('div');
        proxyToggle.id = 'suno-studio-toggle';
        proxyToggle.style.display = 'none';
        proxyToggle.onclick = () => {
            openStudioDrawer('composer');
            generateSong();
        };

        const proxyWavToggle = document.createElement('div');
        proxyWavToggle.id = 'suno-wav-toggle';
        proxyWavToggle.style.display = 'none';
        proxyWavToggle.onclick = () => toggleStudioDrawer('wav');

        document.body.appendChild(dock);
        document.body.appendChild(proxyToggle);
        document.body.appendChild(proxyWavToggle);

        function updateDockMinimizeUI() {
            const fullElements = dock.querySelectorAll('.suno-dock-full');
            const minBtn = document.getElementById('suno-dock-btn-min');
            if (isDockMinimized) {
                fullElements.forEach(el => el.style.display = 'none');
                dock.style.padding = '5px 10px';
                dock.style.borderRadius = '24px';
                if (minBtn) minBtn.innerHTML = '➕';
            } else {
                fullElements.forEach(el => el.style.display = (el.tagName === 'DIV' ? 'block' : 'flex'));
                dock.style.padding = '5px 8px';
                dock.style.borderRadius = '16px';
                if (minBtn) minBtn.innerHTML = '—';
            }
            localStorage.setItem('suno_dock_minimized', isDockMinimized ? 'true' : 'false');
        }

        document.getElementById('suno-dock-btn-min')?.addEventListener('click', (e) => {
            e.stopPropagation();
            isDockMinimized = !isDockMinimized;
            updateDockMinimizeUI();
        });

        document.getElementById('suno-dock-brand')?.addEventListener('click', () => {
            if (isDockMinimized) {
                isDockMinimized = false;
                updateDockMinimizeUI();
            } else {
                toggleStudioDrawer('composer');
            }
        });

        if (isDockMinimized) updateDockMinimizeUI();

        // --- 3. Unified Suno Studio Drawer with Segmented Controls ---
        const drawer = document.createElement('div');
        drawer.id = 'suno-studio-drawer';
        Object.assign(drawer.style, {
            position: 'fixed',
            top: '0',
            right: '-540px',
            width: '490px',
            maxWidth: '92vw',
            height: '100vh',
            zIndex: '1000000',
            background: 'rgba(13, 13, 17, 0.98)',
            backdropFilter: 'blur(28px)',
            webkitBackdropFilter: 'blur(28px)',
            borderLeft: '1px solid rgba(255, 255, 255, 0.1)',
            boxShadow: '-15px 0 45px rgba(0,0,0,0.85)',
            color: '#f0f0f5',
            fontFamily: 'system-ui, -apple-system, sans-serif',
            display: 'flex',
            flexDirection: 'column',
            transition: 'right 0.32s cubic-bezier(0.16, 1, 0.3, 1)',
            boxSizing: 'border-box'
        });

        drawer.innerHTML = `
            <!-- Header with Suno-style Segmented Switch (STYLE iOS 27 Liquid Frosted Glass) -->
            <div style="padding: 13px 18px; border-bottom: 1px solid rgba(255,255,255,0.1); display:flex; align-items:center; justify-content:space-between; background:rgba(18,19,28,0.88); backdrop-filter:blur(28px) saturate(210%);">
                <div style="background:rgba(10,11,16,0.65); border:1px solid rgba(255,255,255,0.12); border-radius:9999px; padding:3px; display:flex; gap:4px; flex:1; max-width:370px; box-shadow:inset 0 1px 2px rgba(0,0,0,0.4);">
                    <button id="suno-tab-btn-composer" class="suno-seg-tab suno-btn-standard" style="flex:1; padding:7px 14px; border-radius:9999px; border:none; background:linear-gradient(135deg, #ff5e3a 0%, #ff2a6d 100%); color:#ffffff; font-weight:700; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:6px; box-shadow:0 4px 16px rgba(255,42,109,0.5), inset 0 1px 1px rgba(255,255,255,0.6);">
                        <span style="font-size:14px;">🎵</span>
                        <span>AI និពន្ធចម្រៀង</span>
                    </button>
                    <button id="suno-tab-btn-wav" class="suno-seg-tab suno-btn-standard" style="flex:1; padding:7px 14px; border-radius:9999px; border:none; background:transparent; color:#a1a1aa; font-weight:700; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:6px;">
                        <span style="font-size:14px;">🔊</span>
                        <span>ទាញយក WAV</span>
                        <span id="suno-wav-tab-badge" style="font-size:9px; font-weight:800; padding:2px 6px; border-radius:8px; background:${autoDownloadWav ? 'rgba(16,185,129,0.2)' : 'rgba(255,255,255,0.08)'}; color:${autoDownloadWav ? '#10b981' : '#a1a1aa'};">
                            ${autoDownloadWav ? 'Auto ON' : 'OFF'}
                        </span>
                    </button>
                </div>
                <button id="suno-drawer-close" class="suno-btn-standard suno-btn-glass" style="background:rgba(255,255,255,0.08); border:1px solid rgba(255,255,255,0.18); color:#cbd5e1; font-size:14px; cursor:pointer; width:34px; height:34px; border-radius:9999px; display:flex; align-items:center; justify-content:center; box-shadow:inset 0 1px 1px rgba(255,255,255,0.3); transition:all 0.2s;" title="បិទផ្ទាំង (Esc)">✕</button>
            </div>

            <!-- PANEL 1: AI COMPOSER VIEW -->
            <div id="suno-view-composer" class="suno-scrollbar" style="flex:1; overflow-y:auto; padding:18px 20px; display:flex; flex-direction:column; gap:14px;">
                <!-- PRIMARY HERO GENERATE BUTTON (TOP) - STYLE iOS 27 SOLAR AURORA CAPSULE -->
                <div style="background: rgba(26, 26, 38, 0.82); backdrop-filter: blur(28px) saturate(210%); border: 1.5px solid rgba(255, 94, 58, 0.45); border-radius: 16px; padding: 13px; box-shadow: 0 8px 32px rgba(255, 42, 109, 0.28), inset 0 1px 1.5px rgba(255, 255, 255, 0.2);">
                    <button id="suno-generate-btn-top" class="suno-btn-standard suno-btn-primary" style="width:100%; padding:14px; border:none; border-radius:14px; color:#ffffff; font-weight:800; font-size:14.5px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:8px;">
                        <span style="font-size:18px;">✨</span>
                        <span>បង្កើត ចំណងជើងចម្រៀង ទំនុកច្រៀង ស្ទីលបទភ្លេង (F6)</span>
                    </button>
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-top:8px; font-size:11.5px; color:#f0f0f5; padding:0 4px;">
                        <span style="color:#ffd090; font-weight:600;">⚡ និពន្ធថ្មីដោយ Gemini 3.1 & AI Suite</span>
                        <span style="color:#10b981; font-weight:700;">✓ Title + Lyrics + Style</span>
                    </div>
                </div>

                <!-- 1. Theme Selection -->
                <div>
                    <label style="display:block; font-size:12px; font-weight:700; color:#ff7a38; text-transform:uppercase; margin-bottom:6px; letter-spacing:0.5px;">
                        ១. ជ្រើសរើសប្រធានបទ (Theme / Mood)
                    </label>
                    <select id="suno-theme-select" style="width:100%; padding:10px 12px; background:#181820; border:1px solid #2d2d38; border-radius:8px; color:#ffffff; font-size:13px; outline:none;">
                        ${songData.themes.map(t => `<option value="${t.id}">${t.name}</option>`).join('')}
                    </select>
                </div>

                <!-- Custom Idea Prompt -->
                <div>
                    <label style="display:block; font-size:12px; font-weight:600; color:#a1a1aa; margin-bottom:6px;">
                        ឬ បញ្ចូលគំនិតផ្ទាល់ខ្លួន (Custom Prompt):
                    </label>
                    <input id="suno-custom-topic" type="text" placeholder="ឧទាហរណ៍៖ ស្នេហាចម្ងាយ, រាត្រីកាហ្វេ, ដើរលេងមាត់សមុទ្រ..." style="width:100%; box-sizing:border-box; padding:10px 12px; background:#181820; border:1px solid #2d2d38; border-radius:8px; color:#ffffff; font-size:13px; outline:none;">
                </div>

                <!-- Title Output with Gemini AI Suite -->
                <div style="background:rgba(139,92,246,0.06); border:1px solid rgba(139,92,246,0.25); border-radius:10px; padding:12px;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                        <div style="display:flex; align-items:center; gap:6px;">
                            <span style="font-size:15px;">✨</span>
                            <label style="font-size:12px; font-weight:700; color:#c4b5fd; text-transform:uppercase; letter-spacing:0.5px;">
                                Gemini AI Suite
                            </label>
                        </div>
                        <div style="display:flex; align-items:center; gap:5px;">
                            <button id="suno-gemini-key-toggle" style="background:#262038; border:1px solid #4f3f75; border-radius:4px; color:#c4b5fd; font-size:11px; padding:3px 8px; cursor:pointer; display:inline-flex; align-items:center; gap:4px;" title="កំណត់ជំនាន់ Gemini និង API Key">
                                <span>🤖</span>
                                <span id="suno-active-model-name">${getGeminiModelName(localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite').split('(')[0].trim()}</span>
                                <span style="font-size:9px; opacity:0.7;">▼</span>
                            </button>
                            <button id="suno-gemini-gen-title-btn" style="background:linear-gradient(135deg, #8b5cf6, #ec4899); border:none; border-radius:5px; color:#ffffff; font-size:11px; font-weight:700; padding:4px 9px; cursor:pointer; box-shadow:0 2px 8px rgba(139,92,246,0.35);" title="បង្កើតចំណងជើងថ្មីដោយ Gemini">
                                ✨ បង្កើត Title
                            </button>
                        </div>
                    </div>

                    <!-- Collapsible Gemini Model & API Key Settings -->
                    <div id="suno-gemini-key-box" style="display:none; background:#1c182a; border:1px solid #443764; border-radius:6px; padding:10px; margin-bottom:8px;">
                        <div style="margin-bottom:8px;">
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:4px;">
                                <span style="font-size:11px; color:#c4b5fd; font-weight:700;">🤖 ជ្រើសរើសជំនាន់ Gemini (Version Selection):</span>
                                <span id="suno-gemini-model-badge" style="font-size:10px; color:#10b981; font-weight:700;">✓ Auto-Bound</span>
                            </div>
                            <select id="suno-gemini-model-select" class="suno-gemini-model-select" style="width:100%; box-sizing:border-box; background:#100d1c; border:1px solid #6d28d9; border-radius:5px; color:#f3e8ff; font-size:11px; font-weight:600; padding:6px 8px; outline:none; cursor:pointer;">
                                ${renderGeminiModelOptions(localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite')}
                            </select>
                            <div style="font-size:9.5px; color:#a78bfa; margin-top:4px;">
                                🔗 ភ្ជាប់ដោយស្វ័យប្រវត្តិចូលប្រព័ន្ធទាំងមូល (Auto-Bound to System: Web, Desktop, Composer, Titles)
                            </div>
                        </div>

                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:4px; margin-top:8px; border-top:1px solid rgba(255,255,255,0.06); padding-top:6px;">
                            <span style="font-size:11px; color:#c4b5fd; font-weight:600;">🔑 Google Gemini API Key:</span>
                            <a href="https://aistudio.google.com/app/apikey" target="_blank" style="font-size:10px; color:#60a5fa; text-decoration:underline;">យក Key ឥតគិតថ្លៃ ↗</a>
                        </div>
                        <div style="display:flex; gap:6px;">
                            <input id="suno-gemini-key-val" type="password" placeholder="AIzaSy..." style="flex:1; background:#100d1c; border:1px solid #4e3f73; border-radius:4px; color:#fff; font-size:11px; padding:4px 8px; outline:none;">
                            <button id="suno-gemini-key-save" style="background:#8b5cf6; border:none; border-radius:4px; color:#fff; font-size:11px; font-weight:600; padding:4px 8px; cursor:pointer;">Save</button>
                        </div>
                        <div style="font-size:10px; color:#958baa; margin-top:4px;">(បើជ្រើសរើស Smart Engine ឬគ្មាន Key កម្មវិធីនឹងប្រើ Smart AI Engine ដោយស្វ័យប្រវត្តិ)</div>
                    </div>

                    <!-- Auto-Generate Title Switch -->
                    <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:8px; padding-bottom:6px; border-bottom:1px solid rgba(255,255,255,0.06);">
                        <span style="font-size:11px; color:#d1c9e8;">⚡ បង្កើត Title ស្វ័យប្រវត្តិតាម Gemini 3.1</span>
                        <label style="position:relative; display:inline-block; width:34px; height:18px; cursor:pointer; margin:0;">
                            <input type="checkbox" id="suno-auto-gemini-title-chk" checked style="opacity:0; width:0; height:0;">
                            <span id="suno-gemini-slider" style="position:absolute; top:0; left:0; right:0; bottom:0; background:#8b5cf6; border-radius:18px; transition:0.3s; display:flex; align-items:center; padding:2px;">
                                <span style="display:block; width:14px; height:14px; background:#fff; border-radius:50%; transition:0.3s; transform:translateX(16px);"></span>
                            </span>
                        </label>
                    </div>

                    <!-- Title Output Field -->
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
                        <label style="font-size:11px; font-weight:600; color:#ffd090;">
                            🏷️ ចំណងជើងចម្រៀង ➔ Suno Title (Optional)
                        </label>
                        <div style="display:flex; gap:4px;">
                            <button id="suno-fill-title" style="background:#059669; border:none; border-radius:4px; color:#fff; font-size:11px; font-weight:700; padding:3px 8px; cursor:pointer;" title="បញ្ចូលតែចំណងជើងចូល Suno">⚡ បញ្ចូល Title</button>
                            <button id="suno-copy-title" style="background:#282834; border:1px solid #3c3c4c; border-radius:4px; color:#ffd090; font-size:11px; padding:3px 8px; cursor:pointer;">📋 Copy</button>
                        </div>
                    </div>
                    <input id="suno-title-output" type="text" style="width:100%; box-sizing:border-box; padding:10px 12px; background:#14141c; border:1px solid #4a3e6a; border-radius:8px; color:#ffd090; font-weight:700; font-size:14px; outline:none; transition:border 0.2s;">

                    <!-- Gemini 3.1 Alternative Title Chips -->
                    <div style="margin-top:8px;">
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:5px;">
                            <span style="font-size:10px; color:#a0a0c0; text-transform:uppercase; letter-spacing:0.5px;">💡 ជម្រើសចំណងជើងផ្សេងទៀតពី Gemini 3.1:</span>
                            <span id="suno-gemini-loading" style="display:none; font-size:10px; color:#ec4899; font-weight:600;">⏳ កំពុងគិត...</span>
                        </div>
                        <div id="suno-gemini-title-chips" style="display:flex; flex-wrap:wrap; gap:5px;"></div>
                    </div>
                </div>

                <!-- 2. Genre & Music Style -->
                <div>
                    <label style="display:block; font-size:12px; font-weight:700; color:#ff7a38; text-transform:uppercase; margin-bottom:6px; letter-spacing:0.5px;">
                        ២. ជ្រើសរើសរចនាបថបទភ្លេង (Music Genre)
                    </label>
                    <select id="suno-genre-select" style="width:100%; padding:10px 12px; background:#181820; border:1px solid #2d2d38; border-radius:8px; color:#ffffff; font-size:13px; outline:none;">
                        ${songData.genres.map(g => `<option value="${g.id}">${g.name}</option>`).join('')}
                    </select>
                </div>

                <!-- Vocal Type & Tempo -->
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:10px;">
                    <div>
                        <label style="display:block; font-size:11px; color:#a1a1aa; margin-bottom:4px;">🎤 សំឡេងច្រៀង (Vocals)</label>
                        <select id="suno-vocal-select" style="width:100%; padding:8px 10px; background:#181820; border:1px solid #2d2d38; border-radius:6px; color:#ffffff; font-size:12px;">
                            <option value="female">👩 ស្រី (Female Vocals)</option>
                            <option value="male">👨 ប្រុស (Male Vocals)</option>
                            <option value="duet">👥 ឆ្លើយឆ្លង (Duet: Male & Female)</option>
                            <option value="instrumental">🎸 ភ្លេងសុទ្ធ (Instrumental)</option>
                        </select>
                    </div>
                    <div>
                        <label style="display:block; font-size:11px; color:#a1a1aa; margin-bottom:4px;">ចង្វាក់ល្បឿន (Tempo)</label>
                        <select id="suno-tempo-select" style="width:100%; padding:8px 10px; background:#181820; border:1px solid #2d2d38; border-radius:6px; color:#ffffff; font-size:12px;">
                            <option value="slow tempo 72 bpm">យឺត (Slow 72 BPM)</option>
                            <option value="moderate tempo 88 bpm" selected>មធ្យម (Mid 88 BPM)</option>
                            <option value="fast upbeat 124 bpm">ញាក់ (Fast 124 BPM)</option>
                        </select>
                    </div>
                </div>

                <!-- 🌐 Song Language Selection (កំណត់ភាសានិពន្ធចម្រៀង គ្រប់ភាសាទាំងអស់) -->
                <div style="background:rgba(255,255,255,0.03); border:1px solid #2d2d38; border-radius:8px; padding:8px 10px;">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:5px;">
                        <label style="font-size:11px; font-weight:700; color:#ff9f87;">🌐 ភាសានិពន្ធចម្រៀង (Song Language):</label>
                        <span id="suno-current-lang-badge" style="font-size:10px; background:#2d2d38; color:#38bdf8; padding:1px 6px; border-radius:4px; font-weight:700;">${getSongLanguageConfig().name.split('(')[0].trim()}</span>
                    </div>
                    <div style="display:flex; gap:6px;">
                        <select id="suno-language-select" style="flex:1; padding:7px 9px; background:#181820; border:1px solid #3d2d48; border-radius:6px; color:#ffffff; font-size:12px; outline:none;">
                            ${renderLanguageOptions(localStorage.getItem('suno_song_language') || 'km')}
                        </select>
                        <input id="suno-custom-language-input" type="text" placeholder="វាយភាសា... (ឧ. Arabic, Portuguese...)" style="display:${localStorage.getItem('suno_song_language') === 'custom' ? 'block' : 'none'}; flex:1; padding:7px 9px; background:#181820; border:1px solid #ff7a59; border-radius:6px; color:#ffffff; font-size:12px; outline:none;" value="${localStorage.getItem('suno_custom_language_name') || ''}" />
                    </div>
                </div>

                <!-- Generate Button -->
                <button id="suno-generate-btn" class="suno-btn-hover" style="width:100%; padding:13px; background:linear-gradient(135deg, #ff5500, #ea580c); border:none; border-radius:10px; color:#ffffff; font-weight:800; font-size:14px; cursor:pointer; box-shadow:0 4px 16px rgba(255,85,0,0.35); display:flex; align-items:center; justify-content:center; gap:8px;">
                    <span style="font-size:15px;">✨</span>
                    <span>បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីលបទភ្លេង ឡើងវិញ</span>
                </button>

                <!-- Results: Style of Music Box -->
                <div>
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
                        <label style="font-size:12px; font-weight:700; color:#ff7a38; text-transform:uppercase;">
                            🎼 ស្ទីលបទភ្លេង ➔ Suno Style of Music
                        </label>
                        <button id="suno-fill-style" style="background:#059669; border:none; border-radius:4px; color:#fff; font-size:11px; font-weight:700; padding:3px 8px; cursor:pointer;" title="បញ្ចូលតែ Styles ចូល Suno">⚡ បញ្ចូល Style</button> <button id="suno-copy-style" style="background:#282834; border:1px solid #3c3c4c; border-radius:4px; color:#c0c0d0; font-size:11px; padding:3px 8px; cursor:pointer;">
                            📋 Copy
                        </button>
                    </div>
                    <input id="suno-style-output" type="text" style="width:100%; box-sizing:border-box; padding:10px; background:#14141a; border:1px solid #2d2d38; border-radius:8px; color:#ffb09c; font-size:12px;">
                </div>

                <!-- Results: Lyrics Box -->
                <div>
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
                        <label style="font-size:12px; font-weight:700; color:#ff7a38; text-transform:uppercase;">
                            📝 ទំនុកច្រៀង ➔ Suno Lyrics
                        </label>
                        <button id="suno-fill-lyrics" style="background:#059669; border:none; border-radius:4px; color:#fff; font-size:11px; font-weight:700; padding:3px 8px; cursor:pointer;" title="បញ្ចូលតែ Lyrics ចូល Suno">⚡ បញ្ចូល Lyrics</button> <button id="suno-copy-lyrics" style="background:#282834; border:1px solid #3c3c4c; border-radius:4px; color:#c0c0d0; font-size:11px; padding:3px 8px; cursor:pointer;">
                            📋 Copy
                        </button>
                    </div>
                    <textarea id="suno-lyrics-output" rows="7" style="width:100%; box-sizing:border-box; padding:10px; background:#14141a; border:1px solid #2d2d38; border-radius:8px; color:#e6e6f0; font-size:12px; line-height:1.6; resize:vertical; font-family:monospace;"></textarea>
                </div>

                <!-- ⏱️ Song Duration Controller in Drawer -->
                <div style="background:rgba(20, 24, 38, 0.7); border:1px solid rgba(56, 189, 248, 0.3); border-radius:12px; padding:12px 14px; display:flex; flex-direction:column; gap:8px;">
                    <div style="display:flex; justify-content:space-between; align-items:center;">
                        <div style="display:flex; align-items:center; gap:6px;">
                            <span style="font-size:14px;">⏱️</span>
                            <span style="font-size:12px; font-weight:800; color:#bae6fd; letter-spacing:0.3px;">កំណត់នាទីចម្រៀង (SONG DURATION)</span>
                        </div>
                        <span id="suno-drawer-duration-badge" style="font-size:10px; font-weight:800; padding:2px 8px; border-radius:10px; background:rgba(255,255,255,0.06); color:#a5b4fc; border:1px solid rgba(165,180,252,0.3);">⚡ Auto</span>
                    </div>
                    <div style="display:grid; grid-template-columns:repeat(6, 1fr); gap:5px;">
                        <button id="suno-drawer-dur-auto" style="background:rgba(148,163,184,0.15); border:1px solid rgba(148,163,184,0.35); border-radius:6px; color:#cbd5e1; font-size:11px; font-weight:700; padding:6px 0; cursor:pointer;" title="Auto default">Auto</button>
                        <button id="suno-drawer-dur-2m" style="background:rgba(56,189,248,0.12); border:1px solid rgba(56,189,248,0.35); border-radius:6px; color:#7dd3fc; font-size:11px; font-weight:700; padding:6px 0; cursor:pointer;" title="2 នាទី (2:00)">2:00</button>
                        <button id="suno-drawer-dur-3m" style="background:rgba(59,130,246,0.15); border:1px solid rgba(59,130,246,0.4); border-radius:6px; color:#93c5fd; font-size:11px; font-weight:700; padding:6px 0; cursor:pointer;" title="3 នាទី (3:00)">3:00</button>
                        <button id="suno-drawer-dur-4m" style="background:linear-gradient(135deg, rgba(236,72,153,0.2), rgba(168,85,247,0.2)); border:1px solid rgba(236,72,153,0.45); border-radius:6px; color:#f472b6; font-size:11px; font-weight:800; padding:6px 0; cursor:pointer;" title="4 នាទី (4:00 - Standard)">4:00</button>
                        <button id="suno-drawer-dur-5m" style="background:rgba(168,85,247,0.15); border:1px solid rgba(168,85,247,0.4); border-radius:6px; color:#d8b4fe; font-size:11px; font-weight:700; padding:6px 0; cursor:pointer;" title="5 នាទី (5:00)">5:00</button>
                        <button id="suno-drawer-dur-6m" style="background:rgba(239,68,68,0.12); border:1px solid rgba(239,68,68,0.35); border-radius:6px; color:#fca5a5; font-size:11px; font-weight:700; padding:6px 0; cursor:pointer;" title="6 នាទី (6:00 - Max)">6:00</button>
                    </div>
                </div>

                <!-- 📁 គ្រប់គ្រង PLAYLIST & BATCH SELECTION (10, 14, 18 Tracks) IN DRAWER -->
                <div style="background:rgba(26, 20, 42, 0.7); border:1px solid rgba(168, 85, 247, 0.3); border-radius:12px; padding:12px 14px; display:flex; flex-direction:column; gap:8px;">
                    <div style="display:flex; justify-content:space-between; align-items:center;">
                        <div style="display:flex; align-items:center; gap:6px;">
                            <span style="font-size:14px;">📁</span>
                            <span style="font-size:12px; font-weight:800; color:#e9d5ff; letter-spacing:0.3px;">ជ្រើសរើសចម្រៀង & បង្កើត PLAYLIST</span>
                        </div>
                        <span id="suno-drawer-playlist-badge" style="font-size:10px; font-weight:800; padding:2px 8px; border-radius:10px; background:rgba(255,255,255,0.06); color:#94a3b8; border:1px solid rgba(255,255,255,0.1);">បានធិក 0 បទ</span>
                    </div>

                    <div style="display:grid; grid-template-columns:1fr 1.1fr 1fr 1fr; gap:5px;">
                        <button id="suno-drawer-btn-select-10" style="background:rgba(139,92,246,0.15); border:1px solid rgba(139,92,246,0.4); border-radius:8px; color:#c4b5fd; font-size:11px; font-weight:700; padding:7px 2px; cursor:pointer;" title="ធិកជ្រើសរើសចម្រៀង 10 បទ">
                            ☑️ 10 បទ
                        </button>
                        <button id="suno-drawer-btn-select-14" style="background:linear-gradient(135deg, rgba(168,85,247,0.25), rgba(236,72,153,0.25)); border:1px solid rgba(168,85,247,0.5); border-radius:8px; color:#f472b6; font-size:11px; font-weight:800; padding:7px 2px; cursor:pointer; box-shadow:0 2px 6px rgba(168,85,247,0.2);" title="ធិកជ្រើសរើសចម្រៀង 14 បទ (ស្តង់ដារ Playlist)">
                            ⭐ 14 បទ
                        </button>
                        <button id="suno-drawer-btn-select-18" style="background:rgba(59,130,246,0.15); border:1px solid rgba(59,130,246,0.4); border-radius:8px; color:#93c5fd; font-size:11px; font-weight:700; padding:7px 2px; cursor:pointer;" title="ធិកជ្រើសរើសចម្រៀង 18 បទ">
                            ☑️ 18 បទ
                        </button>
                        <button id="suno-drawer-btn-deselect-all" style="background:rgba(239,68,68,0.1); border:1px solid rgba(239,68,68,0.3); border-radius:8px; color:#fca5a5; font-size:10px; font-weight:600; padding:7px 2px; cursor:pointer;" title="ដោះការធិកទាំងអស់">
                            🔄 ដោះធិក
                        </button>
                    </div>

                    <div style="display:flex; gap:6px;">
                        <input id="suno-drawer-playlist-input" type="text" placeholder="ឈ្មោះ Playlist (ឧ. Khmer Hits 2026)..." style="flex:1; background:rgba(15,15,23,0.8); border:1px solid rgba(168,85,247,0.3); border-radius:8px; padding:7px 10px; font-size:11px; color:#ffffff; outline:none;" />
                        <button id="suno-drawer-btn-smart-name" style="background:rgba(139,92,246,0.2); border:1px solid rgba(139,92,246,0.4); border-radius:8px; color:#c4b5fd; font-size:11px; font-weight:700; padding:0 8px; cursor:pointer;" title="បង្កើតឈ្មោះឆ្លាតវៃថ្មី">
                            ✨ ឈ្មោះថ្មី
                        </button>
                    </div>

                    <button id="suno-drawer-btn-auto-add" style="background:linear-gradient(135deg, #10b981, #059669); border:none; border-radius:10px; color:#ffffff; font-size:12px; font-weight:800; padding:9px 12px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:6px; box-shadow:0 3px 10px rgba(16,185,129,0.35);">
                        <span>🚀</span>
                        <span>បង្កើត Playlist ថ្មី & Add ស្វ័យប្រវត្តិ</span>
                    </button>

                    <!-- Sibling Pair Cohesive Rename Card in Drawer -->
                    <div style="background:rgba(15, 23, 42, 0.7); border:1px solid rgba(56, 189, 248, 0.3); border-radius:10px; padding:9px 10px; margin-top:6px; display:flex; flex-direction:column; gap:6px;">
                        <div style="display:flex; justify-content:space-between; align-items:center;">
                            <div style="display:flex; align-items:center; gap:5px;">
                                <span style="font-size:13px;">🪄</span>
                                <span style="font-size:11px; font-weight:800; color:#38bdf8;">ប្តូរឈ្មោះបទភ្លោះ ដោយ AI</span>
                            </div>
                            <label style="display:flex; align-items:center; gap:5px; cursor:pointer; font-size:10px; color:#93c5fd;">
                                <span>ស្វ័យប្រវត្តិ</span>
                                <input type="checkbox" id="suno-drawer-auto-dedup-chk" ${localStorage.getItem('suno_auto_dedup_titles') !== 'false' ? 'checked' : ''} style="accent-color:#38bdf8; cursor:pointer;" />
                            </label>
                        </div>
                        <div style="font-size:10px; color:#94a3b8; line-height:1.35;">
                            ពេលបង្កើតចេញ ២ បទឈ្មោះដូចគ្នា AI នឹងចាប់យកបទទី ២ មកកែឈ្មោះថ្មីអោយស៊ីសង្វាក់ជាមួយបទទី ១។
                        </div>
                        <button id="suno-drawer-btn-dedup-now" style="background:linear-gradient(135deg, rgba(14,165,233,0.25), rgba(59,130,246,0.25)); border:1px solid rgba(56,189,248,0.45); border-radius:8px; color:#7dd3fc; font-size:11px; font-weight:700; padding:6px 10px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;" title="ស្កេន និងប្តូរឈ្មោះបទភ្លោះក្នុង Feed ឥឡូវនេះ">
                            <span>🪄</span>
                            <span>ប្តូរឈ្មោះបទភ្លោះក្នុង Feed ឥឡូវនេះ</span>
                        </button>
                    </div>

                    <!-- 📦 Playlist Zip Downloader Card in Drawer -->
                    <div id="suno-drawer-playlist-zip-card" style="background:rgba(23, 26, 40, 0.95); border:1px solid rgba(255, 110, 80, 0.55); border-radius:10px; padding:12px; margin-top:8px; display:flex; flex-direction:column; gap:8px; box-shadow:0 4px 15px rgba(0,0,0,0.35);">
                        <div style="display:flex; justify-content:space-between; align-items:center;">
                            <div style="display:flex; align-items:center; gap:6px;">
                                <span style="font-size:16px;">📦</span>
                                <span style="font-size:12px; font-weight:800; color:#ff7a59; letter-spacing:0.3px;">ទាញយក PLAYLIST ជា FILE ZIP</span>
                            </div>
                            <span style="font-size:9.5px; font-weight:800; padding:3px 7px; border-radius:6px; background:rgba(255,110,80,0.18); color:#ff9f87; border:1px solid rgba(255,110,80,0.35);">MP3 320k HQ</span>
                        </div>
                        <div style="font-size:10.5px; color:#cbd5e1; line-height:1.4;">
                            ទាញយកចម្រៀងទាំងមូលពី Playlist ដោះកូដជា MP3 320kbps រួមទាំង Cover & Lyrics វេចខ្ចប់ជា ZIP។
                        </div>
                        <div style="display:flex; gap:8px; align-items:center;">
                            <button id="suno-drawer-btn-launch-pl-dl" style="flex:1; background:linear-gradient(135deg, #ff5b38, #ff8a65); border:none; border-radius:8px; color:#ffffff; font-size:12px; font-weight:800; padding:10px 14px; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:6px; box-shadow:0 4px 14px rgba(255,91,56,0.4); transition:all 0.2s ease;">
                                <span style="font-size:14px;">📦</span>
                                <span>បើកកម្មវិធី Playlist Downloader</span>
                            </button>
                            <button id="suno-drawer-btn-quick-pl-dl" style="background:rgba(255,255,255,0.08); border:1px solid rgba(255,255,255,0.22); border-radius:8px; color:#ffffff; font-size:11px; font-weight:800; padding:10px 12px; cursor:pointer; display:flex; align-items:center; gap:4px; transition:all 0.2s ease;" title="ទាញយក Playlist Target (10 Tracks) ជា File ZIP">
                                <span>⚡</span>
                                <span>ទាញយក ZIP</span>
                            </button>
                        </div>
                    </div>
                </div>
            </div>

            <!-- PANEL 2: WAV GRABBER VIEW -->
            <div id="suno-view-wav" class="suno-scrollbar" style="flex:1; overflow-y:auto; padding:18px 20px; display:none; flex-direction:column; gap:14px;">
                <!-- AUTO-DOWNLOAD WAV CARD -->
                <div style="background:linear-gradient(135deg, rgba(2,132,199,0.12), rgba(37,99,235,0.06)); border:1px solid rgba(56,189,248,0.25); border-radius:12px; padding:14px;">
                    <div style="display:flex; align-items:center; justify-content:space-between;">
                        <div style="display:flex; align-items:center; gap:10px;">
                            <span style="font-size:24px;">🔊</span>
                            <div>
                                <div style="font-size:14px; font-weight:700; color:#7dd3fc;">ទាញយកជា WAV ដោយស្វ័យប្រវត្តិ</div>
                                <div style="font-size:11px; color:#bae6fd;">ទាញយកពេល Suno បង្កើតចម្រៀងរួចភ្លាមៗ (Lossless 16-bit PCM)</div>
                            </div>
                        </div>
                        <label style="position:relative; display:inline-block; width:44px; height:24px; cursor:pointer;">
                            <input type="checkbox" id="suno-auto-wav-checkbox" ${autoDownloadWav ? 'checked' : ''} style="opacity:0; width:0; height:0;">
                            <span id="suno-wav-slider" style="position:absolute; cursor:pointer; top:0; left:0; right:0; bottom:0; background:${autoDownloadWav ? '#0284c7' : '#333340'}; transition:0.3s; border-radius:24px; display:flex; align-items:center; padding:2px;">
                                <span style="display:block; width:20px; height:20px; background:#fff; border-radius:50%; transition:0.3s; transform:${autoDownloadWav ? 'translateX(20px)' : 'translateX(0px)'};"></span>
                            </span>
                        </label>
                    </div>
                </div>

                <!-- DIRECT URL DOWNLOADER CARD -->
                <div style="background:#161922; border:1px solid rgba(56,189,248,0.25); border-radius:12px; padding:14px;">
                    <div style="margin-bottom:8px;">
                        <div style="display:flex; align-items:center; gap:8px;">
                            <span style="font-size:18px;">🔗</span>
                            <div>
                                <div style="font-size:13px; font-weight:700; color:#7dd3fc;">ទាញយកតាម Link URL ដោយផ្ទាល់</div>
                                <div style="font-size:11px; color:#94a3b8;">បិទភ្ជាប់ Link URL បទចម្រៀង Suno រួចទាញយកជា WAV ភ្លាមៗ</div>
                            </div>
                        </div>
                    </div>
                    <div style="display:flex; gap:8px;">
                        <input id="suno-direct-url-input" type="text" placeholder="https://suno.com/song/c9505feb-5492-400b..." style="flex:1; background:#10121a; border:1px solid #2d3748; border-radius:8px; padding:9px 12px; color:#fff; font-size:12px; outline:none;" />
                        <button id="suno-direct-dl-btn" class="suno-btn-hover" style="background:linear-gradient(135deg, #0284c7, #0369a1); border:none; border-radius:8px; color:#fff; font-size:12px; font-weight:700; padding:9px 15px; cursor:pointer; white-space:nowrap; box-shadow:0 2px 8px rgba(2,132,199,0.35);">
                            ⬇️ ទាញ WAV
                        </button>
                    </div>
                </div>

                <!-- RECENT SONGS SECTION -->
                <div style="background:#16161d; border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:14px;">
                    <div style="font-size:12px; font-weight:700; color:#a1a1aa; margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;">
                        <span>ចម្រៀងទើបបង្កើតរួច (Recent Songs):</span>
                        <span id="suno-songs-status" style="color:#10b981; font-size:11px;">🟢 ត្រៀមទាញយក</span>
                    </div>
                    <div id="suno-recent-songs-list" style="display:flex; flex-direction:column; gap:8px;"></div>
                </div>
            </div>

            <!-- FOOTER 1: COMPOSER ACTIONS -->
            <div id="suno-footer-composer" style="padding:14px 20px; border-top:1px solid rgba(255,255,255,0.08); background:rgba(16,16,22,0.98); display:flex; flex-direction:column; gap:8px;">
                <button id="suno-autofill-btn" class="suno-btn-hover" style="width:100%; padding:13px; background:linear-gradient(135deg, #10b981, #059669); border:none; border-radius:8px; color:#ffffff; font-weight:700; font-size:14px; cursor:pointer; box-shadow:0 4px 15px rgba(16,185,129,0.35); display:flex; align-items:center; justify-content:center; gap:8px;">
                    <span>⚡</span>
                    <span id="suno-autofill-text">បញ្ចូលទាំងអស់ (Title + Style + Lyrics) ទៅក្នុង Suno</span>
                </button>
                <button id="suno-open-composer-app-btn" class="suno-btn-hover" style="width:100%; padding:10px; background:linear-gradient(135deg, #ff5500, #ea580c); border:none; border-radius:8px; color:#ffffff; font-weight:700; font-size:13px; cursor:pointer; box-shadow:0 3px 12px rgba(255,85,0,0.35); display:flex; align-items:center; justify-content:center; gap:8px;">
                    <span>🎼</span> <span>បើកកម្មវិធី Suno Composer App (ផ្ទាំងធំ Desktop)</span>
                </button>
                <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:2px;">
                    <button id="suno-btn-open-title-gen" class="suno-btn-hover" style="padding:7px; background:#1e1e26; border:1px solid #7c3aed; border-radius:6px; color:#c4b5fd; font-size:11px; font-weight:600; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;">
                        <span>💡</span> <span>Title AI</span>
                    </button>
                    <button id="suno-btn-open-theme-sel" class="suno-btn-hover" style="padding:7px; background:#1e1e26; border:1px solid #ec4899; border-radius:6px; color:#fbcfe8; font-size:11px; font-weight:600; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;">
                        <span>🎨</span> <span>Theme & Style</span>
                    </button>
                    <button id="suno-btn-open-sono-pro" class="suno-btn-hover" style="padding:7px; background:#1e1e26; border:1px solid #38bdf8; border-radius:6px; color:#bae6fd; font-size:11px; font-weight:600; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;">
                        <span>🚀</span> <span>SONO.PRO</span>
                    </button>
                    <button id="suno-btn-open-auto-shutdown" class="suno-btn-hover" style="padding:7px; background:#1e1e26; border:1px solid #f59e0b; border-radius:6px; color:#fde68a; font-size:11px; font-weight:600; cursor:pointer; display:flex; align-items:center; justify-content:center; gap:5px;">
                        <span>⏰</span> <span>Auto Shutdown</span>
                    </button>
                </div>
                <div style="display:flex; gap:8px;">
                    <button id="suno-pick-paste-btn" class="suno-btn-hover" style="flex:1; padding:9px; background:#1e1e26; border:1px solid #ff7a38; border-radius:6px; color:#ff9078; font-size:12px; font-weight:600; cursor:pointer;">
                        🎯 ចុចលើប្រអប់ក្នុង Suno
                    </button>
                    <button id="suno-copy-all-btn" class="suno-btn-hover" style="flex:1; padding:9px; background:#1e1e26; border:1px solid #3c3c4c; border-radius:6px; color:#d0d0e0; font-size:12px; font-weight:600; cursor:pointer;">
                        📋 Copy ទាំងអស់ (Ctrl+V)
                    </button>
                </div>
            </div>

            <!-- FOOTER 2: WAV ACTIONS -->
            <div id="suno-footer-wav" style="padding:14px 20px; border-top:1px solid rgba(255,255,255,0.08); background:rgba(16,18,26,0.98); display:none; flex-direction:column; gap:8px;">
                <button id="suno-open-downloader-app-btn" class="suno-btn-hover" style="width:100%; padding:11px; background:linear-gradient(135deg, #0284c7, #2563eb); border:none; border-radius:8px; color:#ffffff; font-weight:700; font-size:13px; cursor:pointer; box-shadow:0 4px 15px rgba(2,132,199,0.35); display:flex; align-items:center; justify-content:center; gap:8px;">
                    <span>🚀</span> <span>បើកកម្មវិធី Suno Downloader App (Desktop)</span>
                </button>
                <div style="text-align:center; font-size:11px; color:#64748b;">
                    📁 ឯកសារ WAV រក្សាទុកដោយស្វ័យប្រវត្តិក្នុង Downloads Folder របស់អ្នក
                </div>
            </div>
        `;

        document.body.appendChild(drawer);

        // --- 4. Drawer & Tab State Management ---
        let isDrawerOpen = false;
        let activeTab = 'composer';

        function switchDrawerTab(tab) {
            activeTab = tab;
            const compView = document.getElementById('suno-view-composer');
            const wavView = document.getElementById('suno-view-wav');
            const compFoot = document.getElementById('suno-footer-composer');
            const wavFoot = document.getElementById('suno-footer-wav');
            const compTabBtn = document.getElementById('suno-tab-btn-composer');
            const wavTabBtn = document.getElementById('suno-tab-btn-wav');

            if (tab === 'composer') {
                if (compView) compView.style.display = 'flex';
                if (wavView) wavView.style.display = 'none';
                if (compFoot) compFoot.style.display = 'flex';
                if (wavFoot) wavFoot.style.display = 'none';

                if (compTabBtn) {
                    compTabBtn.style.background = 'linear-gradient(135deg, #ff5e3a 0%, #ff2a6d 100%)';
                    compTabBtn.style.color = '#ffffff';
                    compTabBtn.style.boxShadow = '0 4px 16px rgba(255, 42, 109, 0.5), inset 0 1px 1px rgba(255, 255, 255, 0.6)';
                }
                if (wavTabBtn) {
                    wavTabBtn.style.background = 'transparent';
                    wavTabBtn.style.color = '#a1a1aa';
                    wavTabBtn.style.boxShadow = 'none';
                }
            } else {
                if (compView) compView.style.display = 'none';
                if (wavView) wavView.style.display = 'flex';
                if (compFoot) compFoot.style.display = 'none';
                if (wavFoot) wavFoot.style.display = 'flex';

                if (wavTabBtn) {
                    wavTabBtn.style.background = 'linear-gradient(135deg, #0284c7 0%, #38bdf8 100%)';
                    wavTabBtn.style.color = '#ffffff';
                    wavTabBtn.style.boxShadow = '0 4px 16px rgba(2, 132, 199, 0.5), inset 0 1px 1px rgba(255, 255, 255, 0.6)';
                }
                if (compTabBtn) {
                    compTabBtn.style.background = 'transparent';
                    compTabBtn.style.color = '#a1a1aa';
                    compTabBtn.style.boxShadow = 'none';
                }
                updateRecentSongsUI();

        // Auto-Check and deduplicate sibling clip titles in real-time
        if (!isInitialLoad && typeof autoCheckAndDedupSiblingClips === 'function') {
            setTimeout(autoCheckAndDedupSiblingClips, 1800);
        }
            }
        }

        function openStudioDrawer(tab = 'composer') {
            isDrawerOpen = true;
            drawer.style.right = '0px';
            switchDrawerTab(tab);
        }

        function closeStudioDrawer() {
            isDrawerOpen = false;
            drawer.style.right = '-540px';
        }

        function toggleStudioDrawer(tab = 'composer') {
            if (!isDrawerOpen) {
                openStudioDrawer(tab);
            } else if (activeTab !== tab) {
                switchDrawerTab(tab);
            } else {
                closeStudioDrawer();
            }
        }

        // Global APIs
        window.openStudioDrawer = openStudioDrawer;
        window.closeStudioDrawer = closeStudioDrawer;
        window.toggleStudioDrawer = toggleStudioDrawer;
        window.switchDrawerTab = switchDrawerTab;

        // Drawer Event Listeners
        document.getElementById('suno-drawer-close')?.addEventListener('click', closeStudioDrawer);
        document.getElementById('suno-tab-btn-composer')?.addEventListener('click', () => switchDrawerTab('composer'));
        document.getElementById('suno-tab-btn-wav')?.addEventListener('click', () => switchDrawerTab('wav'));

        // Dock Tab Triggers
        document.getElementById('suno-dock-btn-composer')?.addEventListener('click', () => {
            openStudioDrawer('composer');
            generateSong();
        });
        document.getElementById('suno-dock-btn-wav')?.addEventListener('click', () => toggleStudioDrawer('wav'));

        // Auto open drawer smoothly on first load
        setTimeout(() => { openStudioDrawer('composer'); }, 1200);

        // Keyboard Shortcuts
        window.addEventListener('keydown', (e) => {
            if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'm') {
                openStudioDrawer('composer');
                generateSong();
                e.preventDefault();
            } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'w') {
                toggleStudioDrawer('wav');
                e.preventDefault();
            } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'd') {
                openDownloaderApp();
                e.preventDefault();
            }
        });

        // --- 5. Auto-WAV Synchronizer ---
        function setAutoWavState(enabled) {
            autoDownloadWav = enabled;
            localStorage.setItem('suno_auto_download_wav', enabled ? 'true' : 'false');
            
            // Drawer Switch
            const chk = document.getElementById('suno-auto-wav-checkbox');
            const slider = document.getElementById('suno-wav-slider');
            if (chk) chk.checked = enabled;
            if (slider) {
                slider.style.background = enabled ? '#0284c7' : '#333340';
                slider.querySelector('span').style.transform = enabled ? 'translateX(20px)' : 'translateX(0px)';
            }

            // Drawer Tab Badge
            const tabBadge = document.getElementById('suno-wav-tab-badge');
            if (tabBadge) {
                tabBadge.innerText = enabled ? 'Auto ON' : 'OFF';
                tabBadge.style.color = enabled ? '#10b981' : '#a1a1aa';
                tabBadge.style.background = enabled ? 'rgba(16,185,129,0.2)' : 'rgba(255,255,255,0.08)';
            }

            // Dock Badge
            const dockBadge = document.getElementById('suno-dock-wav-status');
            if (dockBadge) {
                dockBadge.innerText = enabled ? 'Auto ON' : 'OFF';
                dockBadge.style.color = enabled ? '#10b981' : '#a1a1aa';
                dockBadge.style.background = enabled ? 'rgba(16,185,129,0.2)' : 'rgba(255,255,255,0.08)';
            }

            showToast(enabled ? '🔊 បានបើកការទាញយកជា WAV ដោយស្វ័យប្រវត្តិ!' : '🔇 បានបិទការទាញយកជា WAV ដោយស្វ័យប្រវត្តិ', enabled ? 'success' : 'warn');
        }

        document.getElementById('suno-auto-wav-checkbox')?.addEventListener('change', (e) => {
            setAutoWavState(e.target.checked);
        });

        // Downloader & Composer App handlers
        function openComposerApp() {
            if (window.chrome && window.chrome.webview) {
                try {
                    window.chrome.webview.postMessage({
                        type: 'open_composer'
                    });
                } catch (e) {}
            }
            showToast('🎼 កំពុងបើកកម្មវិធី Suno Composer App...', 'info');
        }

        document.getElementById('suno-open-composer-app-btn')?.addEventListener('click', openComposerApp);
        document.getElementById('suno-btn-open-title-gen')?.addEventListener('click', () => {
            if (window.sunoDesktop) window.sunoDesktop.launchTitleGenerator();
            else if (window.chrome?.webview) window.chrome.webview.postMessage({ type: 'open_title_generator' });
            showToast('💡 កំពុងបើកកម្មវិធី Gemini Title Generator...', 'info');
        });
        document.getElementById('suno-btn-open-theme-sel')?.addEventListener('click', () => {
            if (window.sunoDesktop) window.sunoDesktop.launchThemeSelector();
            else if (window.chrome?.webview) window.chrome.webview.postMessage({ type: 'open_theme_selector' });
            showToast('🎨 កំពុងបើកកម្មវិធី Suno Theme & Style Selector...', 'info');
        });
        document.getElementById('suno-btn-open-sono-pro')?.addEventListener('click', () => {
            if (window.sunoDesktop) window.sunoDesktop.launchSonoPro();
            else if (window.chrome?.webview) window.chrome.webview.postMessage({ type: 'open_sono_pro' });
            showToast('🚀 កំពុងបើក SONO.PRO Web Downloader...', 'info');
        });
        document.getElementById('suno-btn-open-auto-shutdown')?.addEventListener('click', () => {
            if (window.sunoDesktop) window.sunoDesktop.launchAutoShutdown();
            else if (window.chrome?.webview) window.chrome.webview.postMessage({ type: 'open_auto_shutdown' });
            showToast('⏰ កំពុងបើកកម្មវិធី Auto Shutdown Studio...', 'info');
        });

        function openDownloaderApp(songUrl = '') {
            if (window.chrome && window.chrome.webview) {
                try {
                    window.chrome.webview.postMessage({
                        type: 'open_downloader',
                        url: songUrl
                    });
                } catch (e) {}
            }
            showToast('🚀 កំពុងបើកកម្មវិធី Suno Downloader...', 'info');
        }

        document.getElementById('suno-open-downloader-app-btn')?.addEventListener('click', () => {
            const urlInput = document.getElementById('suno-direct-url-input');
            openDownloaderApp(urlInput?.value?.trim() || '');
        });

        document.getElementById('suno-direct-dl-btn')?.addEventListener('click', async () => {
            const inp = document.getElementById('suno-direct-url-input');
            const val = inp?.value?.trim() || '';
            const match = val.match(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/i);
            if (!match) {
                showToast('⚠️ សូមបញ្ចូល Link URL បទចម្រៀង Suno អោយបានត្រឹមត្រូវ!', 'warn');
                return;
            }
            const clipId = match[0];
            showToast(`⏳ កំពុងដំណើរការទាញយក ${clipId} ជា WAV...`, 'warn');

            if (window.chrome && window.chrome.webview) {
                try {
                    window.chrome.webview.postMessage({
                        type: 'song_completed',
                        url: `https://suno.com/song/${clipId}`,
                        clipId: clipId
                    });
                } catch (e) {}
            }
            await downloadClipAsWav(clipId, 'Suno_Song_' + clipId.slice(0, 8));
        });

        // --- 6. In-Form Native Create Bar Injection ---
        function tryInjectNativeCreateBar() {
            if (document.getElementById('suno-native-inline-bar')) return;
            const lyricsEl = getSunoLyricsElement();
            if (!lyricsEl) return;

            const formCol = lyricsEl.closest('.relative') || lyricsEl.parentElement;
            if (!formCol || !formCol.parentElement) return;

            const inlineBar = document.createElement('div');
            inlineBar.id = 'suno-native-inline-bar';
            inlineBar.innerHTML = `
                <div style="display:flex; align-items:center; justify-content:space-between; background:rgba(9,9,11,0.96); backdrop-filter:blur(24px) saturate(200%); border:1px solid rgba(255,255,255,0.1); border-radius:9999px; padding:4px 12px; margin-bottom:10px; gap:8px; box-shadow:0 4px 16px rgba(0,0,0,0.5);">
                    <div style="display:flex; align-items:center; gap:8px;">
                        <span style="font-size:14px;">✨</span>
                        <span style="font-size:12px; font-weight:800; color:#ffffff; letter-spacing:0.2px;">AI Studio Quick Bar:</span>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px;">
                        <button id="suno-inline-autofill" class="suno-btn-standard" style="background:rgba(255,255,255,0.05); border:1.5px solid rgba(16,185,129,0.85); border-radius:9999px; color:#ffffff; font-size:12px; font-weight:800; padding:7px 15px; cursor:pointer; display:flex; align-items:center; gap:5px; box-shadow:0 0 12px rgba(16,185,129,0.25), inset 0 1px 1px rgba(255,255,255,0.4);">
                            ⚡ Auto-Fill
                        </button>
                        <button id="suno-inline-gen" class="suno-btn-standard suno-btn-primary" style="background:rgba(255,255,255,0.06); border:1.5px solid rgba(255,94,58,0.9); border-radius:9999px; color:#ffffff; font-size:12px; font-weight:800; padding:8px 18px; cursor:pointer; display:flex; align-items:center; gap:6px; box-shadow:0 0 14px rgba(255,42,109,0.35), inset 0 1px 1.5px rgba(255,255,255,0.5);">
                            <span>✨</span>
                            <span>បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីលបទភ្លេង (F6)</span>
                        </button>
                        <button id="suno-inline-open-comp" class="suno-btn-standard" style="background:rgba(255,255,255,0.05); border:1.5px solid rgba(233,64,87,0.85); border-radius:9999px; color:#ffffff; font-size:12px; font-weight:800; padding:7px 15px; cursor:pointer; display:flex; align-items:center; gap:5px; box-shadow:0 0 12px rgba(233,64,87,0.25), inset 0 1px 1px rgba(255,255,255,0.4);">
                            🎵 បើក Studio
                        </button>
                        <button id="suno-inline-open-wav" class="suno-btn-standard" style="background:rgba(255,255,255,0.05); border:1.5px solid rgba(56,189,248,0.85); border-radius:9999px; color:#ffffff; font-size:12px; font-weight:800; padding:7px 14px; cursor:pointer; display:flex; align-items:center; gap:5px; box-shadow:0 0 12px rgba(56,189,248,0.25), inset 0 1px 1px rgba(255,255,255,0.4);">
                            🔊 WAV (${autoDownloadWav ? 'ON' : 'OFF'})
                        </button>
                    </div>
                </div>
            `;

            formCol.parentElement.insertBefore(inlineBar, formCol);

            document.getElementById('suno-inline-autofill')?.addEventListener('click', doAutoFill);
            document.getElementById('suno-inline-gen')?.addEventListener('click', generateSong);
            document.getElementById('suno-inline-open-comp')?.addEventListener('click', () => openStudioDrawer('composer'));
            document.getElementById('suno-inline-open-wav')?.addEventListener('click', () => openStudioDrawer('wav'));
        }

        setInterval(tryInjectNativeCreateBar, 3000);

        // Note: generateSong is defined in outer studio scope above sunoAutoLoop

        // --- GEMINI 3.1 SUITE EVENT HANDLERS ---
        const geminiKeyToggle = document.getElementById('suno-gemini-key-toggle');
        const geminiKeyBox = document.getElementById('suno-gemini-key-box');
        const geminiKeyVal = document.getElementById('suno-gemini-key-val');
        const geminiKeySave = document.getElementById('suno-gemini-key-save');
        const geminiGenBtn = document.getElementById('suno-gemini-gen-title-btn');
        const geminiAutoChk = document.getElementById('suno-auto-gemini-title-chk');
        const geminiSlider = document.getElementById('suno-gemini-slider');

        if (geminiKeyVal) {
            geminiKeyVal.value = localStorage.getItem('gemini_api_key') || '';
        }

        const geminiModelSelect = document.getElementById('suno-gemini-model-select');
        if (geminiModelSelect) {
            geminiModelSelect.value = localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';
            geminiModelSelect.onchange = () => {
                const newM = geminiModelSelect.value;
                window.syncGeminiModel(newM, true);
            };
        }

        if (geminiKeyToggle && geminiKeyBox) {
            geminiKeyToggle.onclick = () => {
                const isHidden = geminiKeyBox.style.display === 'none';
                geminiKeyBox.style.display = isHidden ? 'block' : 'none';
                geminiKeyToggle.style.background = isHidden ? '#4f3f75' : '#262038';
            };
        }

        if (geminiKeySave && geminiKeyVal) {
            geminiKeySave.onclick = () => {
                const key = geminiKeyVal.value.trim();
                localStorage.setItem('gemini_api_key', key);
                const curM = localStorage.getItem('gemini_model_choice') || 'gemini-3.1-flash-lite';
                try {
                    if (window.chrome && window.chrome.webview) {
                        window.chrome.webview.postMessage(JSON.stringify({ action: 'set_gemini_model', model: curM, apiKey: key }));
                    }
                } catch (e) { }
                geminiKeyBox.style.display = 'none';
                showToast(key ? '✓ បានរក្សាទុក Gemini API Key និងភ្ជាប់ម៉ូឌែលរួចរាល់!' : '✓ បានលុប Key (ប្រើ Smart AI Engine)', 'success');
                requestGeminiSongTitles(true);
            };
        }

        if (geminiAutoChk && geminiSlider) {
            geminiAutoChk.onchange = (e) => {
                const en = e.target.checked;
                localStorage.setItem('gemini_auto_title_enabled', en ? 'true' : 'false');
                geminiSlider.style.background = en ? '#8b5cf6' : '#383844';
                geminiSlider.querySelector('span').style.transform = en ? 'translateX(16px)' : 'translateX(0px)';
                showToast(en ? '✨ បានបើកការបង្កើតចំណងជើងស្វ័យប្រវត្តិតាម Gemini 3.1' : '🔇 បានបិទការបង្កើតចំណងជើងស្វ័យប្រវត្តិ', en ? 'success' : 'warn');
            };
        }

        if (geminiGenBtn) {
            geminiGenBtn.onclick = () => {
                requestGeminiSongTitles(true);
            };
        }

        // Initial generation
        try {
            generateSong();
        } catch (e) {
            console.warn('[Suno Studio] Initial generation catch:', e);
        }

        document.getElementById('suno-generate-btn')?.addEventListener('click', generateSong);
        document.getElementById('suno-generate-btn-top')?.addEventListener('click', generateSong);
        document.getElementById('suno-dock-btn-gen')?.addEventListener('click', () => {
            generateSong();
            openStudioDrawer('composer');
        });
        document.getElementById('suno-dock-btn-loop')?.addEventListener('click', toggleAutoLoopPanel);
        document.getElementById('suno-dock-btn-playlist')?.addEventListener('click', () => {
            toggleAutoLoopPanel();
            setTimeout(() => {
                const card = document.getElementById('suno-playlist-card-loop');
                if (card) card.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }, 100);
        });
        document.getElementById('suno-dock-btn-clear')?.addEventListener('click', clearAllSunoFields);
        document.getElementById('suno-dock-btn-autofill')?.addEventListener('click', doAutoFill);
        document.getElementById('quick-gen-btn')?.addEventListener('click', generateSong);
        document.getElementById('suno-theme-select')?.addEventListener('change', generateSong);
        document.getElementById('suno-genre-select')?.addEventListener('change', generateSong);
        document.getElementById('suno-tempo-select')?.addEventListener('change', generateSong);

        // Vocal Selection State & Listener
        const savedVocal = localStorage.getItem('suno_vocal_choice') || 'female';
        const vocalSelect = document.getElementById('suno-vocal-select');
        if (vocalSelect) {
            const match = Array.from(vocalSelect.options).find(o => o.value === savedVocal || o.value.includes(savedVocal) || savedVocal.includes(o.value));
            if (match) vocalSelect.value = match.value;
            vocalSelect.addEventListener('change', (e) => {
                localStorage.setItem('suno_vocal_choice', e.target.value);
                const prof = getVocalProfile(e.target.value);
                showToast(`🎤 សំឡេងច្រៀងកំណត់ជា៖ ${prof.name}`, 'info');
                generateSong();
            });
        }

        // Language Select in Drawer
        const drawerLangSel = document.getElementById('suno-language-select');
        const drawerCustomInp = document.getElementById('suno-custom-language-input');
        if (drawerLangSel) {
            const savedLang = localStorage.getItem('suno_song_language') || 'km';
            drawerLangSel.value = savedLang;
            drawerLangSel.addEventListener('change', (e) => {
                const code = e.target.value;
                const customVal = drawerCustomInp ? drawerCustomInp.value.trim() : '';
                setSongLanguage(code, customVal, true);
                generateSong();
            });
        }
        if (drawerCustomInp) {
            drawerCustomInp.addEventListener('input', (e) => {
                setSongLanguage('custom', e.target.value.trim(), true);
            });
            drawerCustomInp.addEventListener('change', () => {
                generateSong();
            });
        }

        // Auto-Fill Buttons
        function doAutoFill() {
            const title = document.getElementById('suno-title-output')?.value || '';
            const lyrics = document.getElementById('suno-lyrics-output')?.value || '';
            const style = document.getElementById('suno-style-output')?.value || '';
            mapAndFillSunoFields(lyrics, style, title);
            try {
                if (typeof applySavedSongDuration === 'function') {
                    applySavedSongDuration();
                }
            } catch (e) { }
        }

        document.getElementById('suno-fill-title')?.addEventListener('click', () => fillSingleField('title'));
        document.getElementById('suno-fill-style')?.addEventListener('click', () => fillSingleField('style'));
        document.getElementById('suno-fill-lyrics')?.addEventListener('click', () => fillSingleField('lyrics'));

        document.getElementById('suno-autofill-btn')?.addEventListener('click', doAutoFill);
        document.getElementById('quick-fill-btn')?.addEventListener('click', doAutoFill);

        // Pick & Paste
        document.getElementById('suno-pick-paste-btn')?.addEventListener('click', () => {
            toggleComposerDrawer(false);
            enablePickAndPasteMode();
        });
        document.getElementById('quick-pick-btn')?.addEventListener('click', enablePickAndPasteMode);

        // Copy Handlers
        function copyText(val, msg) {
            navigator.clipboard.writeText(val).then(() => {
                showToast(msg || '✓ បានចម្លងរួចរាល់ (ចុច Ctrl + V ដើម្បី Paste)!', 'success');
            });
        }

        document.getElementById('suno-copy-title')?.addEventListener('click', () => {
            copyText(document.getElementById('suno-title-output')?.value || '', '✓ បានចម្លងចំណងជើង (Title)! ចុច Ctrl + V ដើម្បី Paste');
        });
        document.getElementById('quick-copy-title')?.addEventListener('click', () => {
            copyText(document.getElementById('suno-title-output')?.value || '', '✓ បានចម្លងចំណងជើង (Title)! ចុច Ctrl + V ដើម្បី Paste');
        });

        document.getElementById('suno-copy-lyrics')?.addEventListener('click', () => {
            copyText(document.getElementById('suno-lyrics-output')?.value || '', '✓ បានចម្លងទំនុកច្រៀង (Lyrics)! ចុច Ctrl + V ដើម្បី Paste');
        });
        document.getElementById('quick-copy-lyrics')?.addEventListener('click', () => {
            copyText(document.getElementById('suno-lyrics-output')?.value || '', '✓ បានចម្លងទំនុកច្រៀង (Lyrics)! ចុច Ctrl + V ដើម្បី Paste');
        });

        document.getElementById('suno-copy-style')?.addEventListener('click', () => {
            copyText(document.getElementById('suno-style-output')?.value || '', '✓ បានចម្លងស្ទីលភ្លេង (Style)! ចុច Ctrl + V ដើម្បី Paste');
        });
        document.getElementById('quick-copy-style')?.addEventListener('click', () => {
            copyText(document.getElementById('suno-style-output')?.value || '', '✓ បានចម្លងស្ទីលភ្លេង (Style)! ចុច Ctrl + V ដើម្បី Paste');
        });

        document.getElementById('suno-copy-all-btn')?.addEventListener('click', () => {
            const title = document.getElementById('suno-title-output')?.value || '';
            const lyrics = document.getElementById('suno-lyrics-output')?.value || '';
            const style = document.getElementById('suno-style-output')?.value || '';
            copyText(`[Title]: ${title}\n[Style]: ${style}\n\n[Lyrics]:\n${lyrics}`, '✓ បានចម្លងទាំង Title + Lyrics + Style! ចុច Ctrl + V ដើម្បី Paste');
        });

        // Drawer Playlist Listeners
        let drawerBatchTarget = 14;
        document.getElementById('suno-drawer-btn-select-10')?.addEventListener('click', async () => {
            drawerBatchTarget = 10;
            const input = document.getElementById('suno-drawer-playlist-input');
            const newName = await generateSmartPlaylistName(10);
            if (input) input.value = newName;
            updatePlaylistSelectionUI(10, newName);
            await selectBatchSongs(10);
        });
        document.getElementById('suno-drawer-btn-select-14')?.addEventListener('click', async () => {
            drawerBatchTarget = 14;
            const input = document.getElementById('suno-drawer-playlist-input');
            const newName = await generateSmartPlaylistName(14);
            if (input) input.value = newName;
            updatePlaylistSelectionUI(14, newName);
            await selectBatchSongs(14);
        });
        document.getElementById('suno-drawer-btn-select-18')?.addEventListener('click', async () => {
            drawerBatchTarget = 18;
            const input = document.getElementById('suno-drawer-playlist-input');
            const newName = await generateSmartPlaylistName(18);
            if (input) input.value = newName;
            updatePlaylistSelectionUI(18, newName);
            await selectBatchSongs(18);
        });
        document.getElementById('suno-drawer-btn-deselect-all')?.addEventListener('click', () => {
            deselectAllSongs();
        });
        document.getElementById('suno-drawer-btn-smart-name')?.addEventListener('click', async () => {
            const input = document.getElementById('suno-drawer-playlist-input');
            const newName = await generateSmartPlaylistName(drawerBatchTarget);
            if (input) input.value = newName;
            updatePlaylistSelectionUI(currentlySelectedSongCount, newName);
            showToast(`✨ ឈ្មោះ Playlist ថ្មី៖ ${newName}`, 'info');
        });
        document.getElementById('suno-drawer-btn-auto-add')?.addEventListener('click', async () => {
            const input = document.getElementById('suno-drawer-playlist-input');
            let plName = (input && input.value) ? input.value.trim() : '';
            if (!plName) {
                plName = await generateSmartPlaylistName(drawerBatchTarget);
                if (input) input.value = plName;
            }
            await createAndAddToPlaylist(plName, drawerBatchTarget);
        });

        document.getElementById('suno-drawer-auto-dedup-chk')?.addEventListener('change', (e) => {
            const en = e.target.checked;
            localStorage.setItem('suno_auto_dedup_titles', en ? 'true' : 'false');
            const mainChk = document.getElementById('suno-auto-dedup-chk');
            if (mainChk) mainChk.checked = en;
            showToast(en ? '✨ បានបើកមុខងារប្តូរឈ្មោះបទភ្លោះស្វ័យប្រវត្តិដោយ AI' : '🔇 បានបិទមុខងារប្តូរឈ្មោះបទភ្លោះស្វ័យប្រវត្តិ', en ? 'success' : 'warn');
        });

        document.getElementById('suno-drawer-btn-dedup-now')?.addEventListener('click', async () => {
            await renameDuplicateSiblingClips();
        });

        document.getElementById('suno-drawer-btn-launch-pl-dl')?.addEventListener('click', () => {
            openPlaylistDownloaderApp();
        });

        document.getElementById('suno-drawer-btn-quick-pl-dl')?.addEventListener('click', () => {
            openPlaylistDownloaderApp('https://suno.com/playlist/059caa04-8eb7-4cbc-884d-66198d5f286f');
        });

        // Drawer Duration Listeners
        document.getElementById('suno-drawer-dur-auto')?.addEventListener('click', () => {
            resetSunoSongDurationToAuto();
            updateSunoDurationUI('auto');
            showToast('⚡ បានប្តូរទៅជារយៈពេល Auto (Default របស់ Suno)', 'info');
        });
        document.getElementById('suno-drawer-dur-2m')?.addEventListener('click', async () => {
            await setSunoSongDuration(120);
            updateSunoDurationUI(120);
            showToast('⏱️ បានកំណត់រយៈពេល ២ នាទី (2:00)', 'success');
        });
        document.getElementById('suno-drawer-dur-3m')?.addEventListener('click', async () => {
            await setSunoSongDuration(180);
            updateSunoDurationUI(180);
            showToast('⏱️ បានកំណត់រយៈពេល ៣ នាទី (3:00)', 'success');
        });
        document.getElementById('suno-drawer-dur-4m')?.addEventListener('click', async () => {
            await setSunoSongDuration(240);
            updateSunoDurationUI(240);
            showToast('⏱️ បានកំណត់រយៈពេល ៤ នាទី (4:00)', 'success');
        });
        document.getElementById('suno-drawer-dur-5m')?.addEventListener('click', async () => {
            await setSunoSongDuration(300);
            updateSunoDurationUI(300);
            showToast('⏱️ បានកំណត់រយៈពេល ៥ នាទី (5:00)', 'success');
        });
        document.getElementById('suno-drawer-dur-6m')?.addEventListener('click', async () => {
            await setSunoSongDuration(360);
            updateSunoDurationUI(360);
            showToast('⏱️ បានកំណត់រយៈពេល ៦ នាទី (6:00)', 'success');
        });

        function triggerSunoCreate() {
            const analysis = analyzeSunoCreateButton();
            if (analysis && analysis.button && !analysis.button.disabled && analysis.button.getAttribute('aria-disabled') !== 'true') {
                analysis.button.click();
                console.log('[Suno Studio] Clicked native Suno Create button via triggerSunoCreate');
                return true;
            }
            const createBtn = document.querySelector('button[aria-label="Create song"]') ||
                              Array.from(document.querySelectorAll('button')).find(b => {
                                  const aria = (b.getAttribute('aria-label') || '').toLowerCase();
                                  const txt = (b.textContent || '').trim().toLowerCase();
                                  return (aria.includes('create song') || txt === 'create') && !b.id.startsWith('suno-');
                              });
            if (createBtn && !createBtn.disabled && createBtn.getAttribute('aria-disabled') !== 'true') {
                createBtn.click();
                console.log('[Suno Studio] Clicked native Suno Create button directly');
                return true;
            }
            return false;
        }

        window.triggerSunoCreate = triggerSunoCreate;
        window.generateSong = generateSong;
        window.doAutoFill = doAutoFill;
        window.sunoClearAll = clearAllSunoFields;
        window.sunoClearLyrics = clearSunoLyricsOnly;
        window.sunoAnalyzeCreate = analyzeSunoCreateButton;
        window.sunoAnalyzeToday = analyzeSunoTodayFeed;
        window.sunoGenerateTitleOnly = generateFreshTitleOnly;
        window.toggleAutoLoop = toggleAutoLoopPanel;
        window.switchSunoModel = switchSunoModel;
        window.selectBatchSongs = selectBatchSongs;
        window.deselectAllSongs = deselectAllSongs;
        window.isSongCheckboxChecked = isSongCheckboxChecked;
        window.getFeedSongCheckboxes = getFeedSongCheckboxes;
        window.getCheckedSongClipIds = getCheckedSongClipIds;
        window.getCheckedSongsList = getCheckedSongsList;
        window.generateSmartPlaylistName = generateSmartPlaylistName;
        window.createAndAddToPlaylist = createAndAddToPlaylist;
        window.renameDuplicateSiblingClips = renameDuplicateSiblingClips;
        window.renameSunoClip = renameSunoClip;
        window.generateCohesiveSisterTitle = generateCohesiveSisterTitle;
        window.setSunoSongDuration = setSunoSongDuration;
        window.resetSunoSongDurationToAuto = resetSunoSongDurationToAuto;
        window.getSunoCurrentDuration = getSunoCurrentDuration;
        window.updateSunoDurationUI = updateSunoDurationUI;
        window.applySavedSongDuration = applySavedSongDuration;

        window.applyThemeAndStyle = function(themeId, genreId) {
            const theme = songData.themes.find(t => t.id === themeId) || songData.themes[0];
            const genre = songData.genres.find(g => g.id === genreId) || songData.genres[0];
            if (theme && genre) {
                setSunoTitle(theme.defaultTitle);
                setSunoStyles(genre.style);
                setSunoLyrics(theme.lyricsKhmer);
                showToast(`🎨 បានបញ្ចូល Theme "${theme.name}"\n🎼 Style: "${genre.name}"`, 'success');
                return true;
            }
            return false;
        };

        window.getSunoSongData = function() {
            return {
                themes: songData.themes.map(t => ({ id: t.id, name: t.name, defaultTitle: t.defaultTitle })),
                genres: songData.genres.map(g => ({ id: g.id, name: g.name, style: g.style }))
            };
        };

        // =========================================================================
        // STANDARD SUNO STUDIO (ស្ទីលធម្មតា) - CLEANUP ANY LEFTOVER iOS 27 CLASSES
        // =========================================================================
        function cleanupIOS27Styling() {
            try {
                document.querySelectorAll('.ios27-btn, .ios27-suno-create, .ios27-btn-primary, .ios27-btn-download, .ios27-btn-azure, .ios27-btn-emerald, .ios27-btn-crimson, .ios27-btn-glass, .ios27-applied').forEach(el => {
                    el.classList.remove('ios27-btn', 'ios27-suno-create', 'ios27-btn-primary', 'ios27-btn-download', 'ios27-btn-azure', 'ios27-btn-emerald', 'ios27-btn-crimson', 'ios27-btn-glass', 'ios27-applied');
                });
            } catch (e) {}
        }
        window.cleanupIOS27Styling = cleanupIOS27Styling;
        window.applySmartIOS27Styling = cleanupIOS27Styling; // backwards compatibility

        cleanupIOS27Styling();

        let periodicTick = 0;
        setInterval(() => {
            periodicTick++;
            const panel = document.getElementById('suno-auto-loop-panel');
            if ((panel && panel.style.display === 'flex') || (window.sunoAutoLoop && window.sunoAutoLoop.isRunning)) {
                updateAutoLoopUI();
            }
            updateSunoModelBadge();
            if (typeof updateSunoDurationUI === 'function') {
                updateSunoDurationUI();
            }

            // Periodic auto-check for sibling pairs (every 4.5 seconds)
            if (periodicTick % 3 === 0 && typeof autoCheckAndDedupSiblingClips === 'function') {
                autoCheckAndDedupSiblingClips();
            }

            // Periodic re-application of iOS 27 styling to dynamic elements
            if (periodicTick % 4 === 0 && typeof cleanupIOS27Styling === 'function') { cleanupIOS27Styling(); }
        }, 1500);

        updateRecentSongsUI();

        // Auto-Check and deduplicate sibling clip titles in real-time
        if (!isInitialLoad && typeof autoCheckAndDedupSiblingClips === 'function') {
            setTimeout(autoCheckAndDedupSiblingClips, 1800);
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initStudioUI);
    } else {
        initStudioUI();
    }
})();
