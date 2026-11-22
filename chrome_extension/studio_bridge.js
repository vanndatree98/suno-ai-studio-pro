// ==============================================================================
// Suno AI Studio Pro - Chrome Extension Bridge (studio_bridge.js)
// Enables real-time IPC connection between Theme Selector and Google Chrome
// ==============================================================================

(function() {
    console.log('[Suno Studio Chrome] Bridge initialized on Google Chrome');

    let isPolling = true;
    let pollInterval = 1000;

    async function pollLocalQueue() {
        if (!isPolling) return;
        try {
            const resp = await fetch('http://127.0.0.1:48999/poll', {
                method: 'GET',
                cache: 'no-cache'
            });

            if (resp.ok) {
                const data = await resp.json();
                if (data && data.items && data.items.length > 0) {
                    for (const item of data.items) {
                        handleQueueItem(item);
                    }
                }
            }
        } catch (e) {
            // Server might not be running or no items, silently continue
        }

        setTimeout(pollLocalQueue, pollInterval);
    }

    function handleQueueItem(item) {
        console.log('[Suno Studio Chrome] Processing received queue item:', item);
        const action = item.action || '';
        const title = item.title || '';
        const style = item.style || '';
        const lyrics = item.lyrics || '';

        if (action === 'set_song_data' || action === 'generate_with_data') {
            if (typeof window.mapAndFillSunoFields === 'function') {
                window.mapAndFillSunoFields(lyrics, style, title);
                console.log('[Suno Studio Chrome] Mapped song fields into Suno form');
            } else {
                console.warn('[Suno Studio Chrome] mapAndFillSunoFields not ready yet, retrying in 500ms');
                setTimeout(() => {
                    if (typeof window.mapAndFillSunoFields === 'function') {
                        window.mapAndFillSunoFields(lyrics, style, title);
                    }
                }, 500);
            }

            if (action === 'generate_with_data') {
                setTimeout(() => {
                    if (typeof window.triggerSunoCreate === 'function') {
                        window.triggerSunoCreate();
                        console.log('[Suno Studio Chrome] Triggered native Suno Create button');
                    }
                }, 700);
            }
        }
    }

    // Start polling when document is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => setTimeout(pollLocalQueue, 1500));
    } else {
        setTimeout(pollLocalQueue, 1500);
    }
})();
