// Suno Playlist Downloader & Decryption Engine
// Downloads full playlists from Suno, decrypts AES-CTR audio streams, and converts to MP3/WAV/M4A

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const crypto = require('crypto').webcrypto;

function getFfmpegPath() {
    const candidates = [
        "C:\\Users\\PS\\AppData\\Local\\Microsoft\\WinGet\\Packages\\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\\ffmpeg-9.0.2-full_build\\bin\\ffmpeg.exe",
        path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'WinGet', 'Packages', 'Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe', 'ffmpeg-9.0.2-full_build', 'bin', 'ffmpeg.exe'),
        path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Suno', 'ffmpeg.exe'),
        path.join(process.env.USERPROFILE || '', 'AppData', 'Local', 'Programs', 'Suno', 'ffmpeg.exe'),
        'ffmpeg.exe',
        'ffmpeg'
    ];
    for (const c of candidates) {
        if (c && fs.existsSync(c)) return c;
    }
    // Dynamic PATH search via where.exe
    try {
        const check = spawnSync('where.exe', ['ffmpeg'], { encoding: 'utf8', windowsHide: true });
        if (check.status === 0 && check.stdout) {
            const found = check.stdout.trim().split(/\r?\n/)[0];
            if (found && fs.existsSync(found)) return found;
        }
    } catch (e) {}
    return 'ffmpeg';
}

const FFMPEG_PATH = getFfmpegPath();

function b64Decode(b64) {
    return Uint8Array.from(Buffer.from(b64, 'base64'));
}

async function decryptClipStream(clipId, encryptedBuffer) {
    // 1. Fetch license rights
    const rightsRes = await fetch('https://studio-api.prod.suno.com/api/mango/rights', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        },
        body: JSON.stringify({
            content_params: {
                content_id: clipId,
                content_type: 'clip'
            }
        })
    });

    if (!rightsRes.ok) {
        throw new Error(`License server returned HTTP ${rightsRes.status}`);
    }

    const rights = await rightsRes.json();
    if (!rights.key || !rights.iv || !rights.glt) {
        throw new Error('Invalid rights response: missing key, iv, or glt');
    }

    // 2. Derive master key from glt via SHA-256
    const gltBytes = new TextEncoder().encode(rights.glt);
    const gltHash = await crypto.subtle.digest('SHA-256', gltBytes);
    const gcmKey = await crypto.subtle.importKey('raw', gltHash, { name: 'AES-GCM' }, false, ['decrypt']);

    // 3. Decrypt AES-CTR key and IV
    const addData = new TextEncoder().encode(clipId);
    const encKeyBytes = b64Decode(rights.key);
    const encIvBytes = b64Decode(rights.iv);

    const rawCtrKey = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: encKeyBytes.slice(0, 12), additionalData: addData },
        gcmKey,
        encKeyBytes.slice(12)
    );

    const rawCtrIv = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: encIvBytes.slice(0, 12), additionalData: addData },
        gcmKey,
        encIvBytes.slice(12)
    );

    const ctrKey = await crypto.subtle.importKey('raw', rawCtrKey, { name: 'AES-CTR' }, false, ['decrypt']);

    // 4. Decrypt audio stream with AES-CTR
    const decryptedAudio = await crypto.subtle.decrypt(
        { name: 'AES-CTR', counter: new Uint8Array(rawCtrIv), length: 128 },
        ctrKey,
        encryptedBuffer
    );

    return Buffer.from(decryptedAudio);
}

function cleanFilename(name) {
    return (name || 'track').trim().replace(/[/\\?%*:|"<>]/g, '_');
}

async function downloadPlaylist(playlistIdOrUrl, options = {}) {
    const format = options.format || 'mp3'; // mp3, wav, m4a
    const outDir = options.outDir || path.join(process.env.USERPROFILE || 'C:\\Users\\PS', 'Downloads');
    const onProgress = options.onProgress || console.log;

    // Extract playlist ID
    const match = playlistIdOrUrl.match(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/i);
    if (!match) throw new Error('Invalid Suno playlist ID or URL: ' + playlistIdOrUrl);
    const playlistId = match[0];

    onProgress(`⏳ កំពុងទាញយកព័ត៌មាន Playlist (${playlistId})...`);

    // Fetch playlist metadata
    const plRes = await fetch(`https://studio-api.prod.suno.com/api/playlist/${playlistId}`, {
        headers: { 'User-Agent': 'Mozilla/5.0' }
    });
    if (!plRes.ok) throw new Error(`Playlist API returned HTTP ${plRes.status}`);
    const plData = await plRes.json();

    const plTitle = cleanFilename(plData.name || 'Suno_Playlist');
    const clips = (plData.playlist_clips || []).map(item => item.clip).filter(Boolean);

    onProgress(`🎵 ទទួលបាន Playlist៖ "${plTitle}" (${clips.length} បទ)`);

    // Create temporary work directory
    const workDir = path.join(outDir, plTitle);
    if (!fs.existsSync(workDir)) fs.mkdirSync(workDir, { recursive: true });

    // Download playlist cover image if available
    if (plData.image_url) {
        try {
            const imgRes = await fetch(plData.image_url);
            if (imgRes.ok) {
                const imgBuf = Buffer.from(await imgRes.arrayBuffer());
                fs.writeFileSync(path.join(workDir, 'cover.jpg'), imgBuf);
            }
        } catch (e) {}
    }

    // Write Tracklist & Lyrics file
    let tracklistContent = `====================================================\n`;
    tracklistContent += `PLAYLIST: ${plData.name}\n`;
    tracklistContent += `CREATOR: ${plData.user_display_name || plData.user_handle || 'Suno Artist'}\n`;
    tracklistContent += `DATE: ${new Date().toLocaleDateString('km-KH')}\n`;
    tracklistContent += `TOTAL TRACKS: ${clips.length}\n`;
    tracklistContent += `====================================================\n\n`;

    const downloadedFiles = [];

    for (let i = 0; i < clips.length; i++) {
        const clip = clips[i];
        const numStr = String(i + 1).padStart(2, '0');
        const songTitle = cleanFilename(clip.title || `Track_${numStr}`);
        const clipId = clip.id;

        onProgress(`[${i + 1}/${clips.length}] ⏳ កំពុងទាញយក & ដោះកូដ "${songTitle}"...`);

        // Add to tracklist
        tracklistContent += `[${numStr}] ${clip.title} (${Math.floor(clip.metadata?.duration || 0)}s)\n`;
        if (clip.metadata?.tags) tracklistContent += `    Style: ${clip.metadata.tags}\n`;
        if (clip.metadata?.prompt) tracklistContent += `    Lyrics:\n${clip.metadata.prompt}\n\n`;

        // Download cover artwork per song
        if (clip.image_url) {
            try {
                const cImgRes = await fetch(clip.image_url);
                if (cImgRes.ok) {
                    const cImgBuf = Buffer.from(await cImgRes.arrayBuffer());
                    fs.writeFileSync(path.join(workDir, `${numStr}_${songTitle}.jpg`), cImgBuf);
                }
            } catch (e) {}
        }

        // Fetch encrypted stream
        const streamUrl = `https://d2lwuy8qc234o3.cloudfront.net/1/clip/${clipId}.m4a`;
        const audioRes = await fetch(streamUrl);
        if (!audioRes.ok) {
            onProgress(`⚠️ បរាជ័យទាញយក Audio សម្រាប់ "${songTitle}" (HTTP ${audioRes.status})`);
            continue;
        }

        const encBuf = await audioRes.arrayBuffer();

        // Decrypt stream
        const decBuf = await decryptClipStream(clipId, encBuf);

        // Save temporary M4A file
        const tempM4a = path.join(workDir, `_temp_${numStr}.m4a`);
        fs.writeFileSync(tempM4a, decBuf);

        let finalAudioPath = tempM4a;
        const targetFilename = `${numStr}_${songTitle}.${format}`;
        const targetPath = path.join(workDir, targetFilename);

        if (format === 'mp3') {
            onProgress(`[${i + 1}/${clips.length}] ⚙️ កំពុងបំលែងជា 320kbps MP3...`);
            const coverPath = path.join(workDir, `${numStr}_${songTitle}.jpg`);
            const hasCover = fs.existsSync(coverPath);

            const ffmpegArgs = ['-y', '-i', tempM4a];
            if (hasCover) {
                ffmpegArgs.push('-i', coverPath, '-map', '0:0', '-map', '1:0', '-c:v', 'copy', '-id3v2_version', '3');
            } else {
                ffmpegArgs.push('-vn');
            }
            ffmpegArgs.push(
                '-c:a', 'libmp3lame',
                '-b:a', '320k',
                '-metadata', `title=${clip.title || ''}`,
                '-metadata', `artist=${plData.user_display_name || plData.user_handle || 'Suno'}`,
                '-metadata', `album=${plData.name || ''}`,
                '-metadata', `track=${i + 1}/${clips.length}`,
                targetPath
            );

            const ret = spawnSync(FFMPEG_PATH, ffmpegArgs, { windowsHide: true });
            if (ret.status === 0 && fs.existsSync(targetPath)) {
                fs.unlinkSync(tempM4a);
                finalAudioPath = targetPath;
            } else {
                // Keep m4a if conversion fails
                fs.renameSync(tempM4a, path.join(workDir, `${numStr}_${songTitle}.m4a`));
                finalAudioPath = path.join(workDir, `${numStr}_${songTitle}.m4a`);
            }
        } else if (format === 'wav') {
            onProgress(`[${i + 1}/${clips.length}] ⚙️ កំពុងបំលែងជា Lossless WAV (16-bit 44.1kHz)...`);
            const ret = spawnSync(FFMPEG_PATH, ['-y', '-i', tempM4a, '-vn', '-c:a', 'pcm_s16le', '-ar', '44100', targetPath], { windowsHide: true });
            if (ret.status === 0 && fs.existsSync(targetPath)) {
                fs.unlinkSync(tempM4a);
                finalAudioPath = targetPath;
            } else {
                fs.renameSync(tempM4a, path.join(workDir, `${numStr}_${songTitle}.m4a`));
                finalAudioPath = path.join(workDir, `${numStr}_${songTitle}.m4a`);
            }
        } else {
            // Original decrypted M4A
            fs.renameSync(tempM4a, targetPath);
            finalAudioPath = targetPath;
        }

        downloadedFiles.push(finalAudioPath);
        onProgress(`[${i + 1}/${clips.length}] ✓ រួចរាល់៖ "${songTitle}" (${(fs.statSync(finalAudioPath).size / (1024 * 1024)).toFixed(2)} MB)`);
    }

    // Write tracklist file
    fs.writeFileSync(path.join(workDir, 'tracklist.txt'), tracklistContent, 'utf-8');

    // Create Zip file
    const zipPath = path.join(outDir, `${plTitle}.zip`);
    onProgress(`📦 កំពុងវេចខ្ចប់ជា File ZIP៖ "${path.basename(zipPath)}"...`);

    if (fs.existsSync(zipPath)) fs.unlinkSync(zipPath);

    // Call PowerShell Compress-Archive
    const psCmd = `Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::CreateFromDirectory('${workDir.replace(/'/g, "''")}', '${zipPath.replace(/'/g, "''")}')`;
    const zipRet = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psCmd], { windowsHide: true });

    if (!fs.existsSync(zipPath) || fs.statSync(zipPath).size === 0) {
        throw new Error('Failed to create ZIP file');
    }

    const zipSizeMb = (fs.statSync(zipPath).size / (1024 * 1024)).toFixed(2);
    onProgress(`🎉 ជោគជ័យ ១០០%! បានទាញយក និងវេចខ្ចប់ជា File ZIP រួចរាល់៖`);
    onProgress(`📁 ទីតាំង File ZIP៖ ${zipPath} (${zipSizeMb} MB)`);

    return {
        success: true,
        playlistTitle: plData.name,
        totalTracks: clips.length,
        downloadedCount: downloadedFiles.length,
        zipPath,
        zipSizeMb,
        workDir
    };
}

// CLI runner
if (require.main === module) {
    const args = process.argv.slice(2);
    const targetUrl = args[0] || 'https://suno.com/playlist/059caa04-8eb7-4cbc-884d-66198d5f286f';
    const targetFormat = args[1] || 'mp3';
    const targetDir = args[2] || path.join(process.env.USERPROFILE || 'C:\\Users\\PS', 'Downloads');

    console.log(`[Suno Playlist Downloader Engine] Starting...`);
    console.log(`URL: ${targetUrl} | Format: ${targetFormat} | Output Dir: ${targetDir}`);

    downloadPlaylist(targetUrl, {
        format: targetFormat,
        outDir: targetDir,
        onProgress: (msg) => console.log(msg)
    }).then(res => {
        console.log('RESULT_JSON:' + JSON.stringify(res));
        process.exit(0);
    }).catch(err => {
        console.error('ERROR:', err);
        process.exit(1);
    });
}

module.exports = { downloadPlaylist, decryptClipStream };
