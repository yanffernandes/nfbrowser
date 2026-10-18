import Foundation

enum OraBrowserScripts {
    static func userScripts() -> [BrowserUserScript] {
        var scripts = [
            BrowserUserScript(
                name: "ora-bridge",
                source: bridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ),
            BrowserUserScript(
                name: "ora-navigation",
                source: navigationAndMediaScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ),
            BrowserUserScript(
                name: "ora-webstore-helper",
                source: chromeWebStoreScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        ]

        if let passwordManagerScript = loadResourceScript(named: "password-manager") {
            scripts.append(
                BrowserUserScript(
                    name: "ora-password-manager",
                    source: passwordManagerScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }

        return scripts
    }

    private static func loadResourceScript(named name: String) -> String? {
        guard let scriptURL = Bundle.main.url(forResource: name, withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8)
        else {
            return nil
        }
        return script
    }

    private static let bridgeScript = """
    (function () {
        if (window.__oraBridge && typeof window.__oraBridge.postMessage === 'function') {
            return;
        }

        const bridge = {
            postMessage: function(name, payload) {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
                        window.webkit.messageHandlers[name].postMessage(payload);
                        return true;
                    }
                } catch (error) {}
                return false;
            }
        };

        try {
            Object.defineProperty(window, '__oraBridge', {
                value: bridge,
                enumerable: false,
                configurable: true,
                writable: true
            });
        } catch (e) {
            window.__oraBridge = bridge;
        }
    })();
    """

    private static let navigationAndMediaScript = """
    (function () {
        let lastHref = location.href;
        let lastTitle = document.title;
        let lastFavicon = '';

        function post(name, payload) {
            try {
                window.__oraBridge && window.__oraBridge.postMessage(name, payload);
            } catch (error) {}
        }

        function getFaviconUrl() {
            try {
                const link = document.querySelector('link[rel~="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]');
                return link && link.href ? link.href : '';
            } catch (e) {
                return '';
            }
        }

        function notifyChange(force = false) {
            const currentFavicon = getFaviconUrl();
            if (force || location.href !== lastHref || document.title !== lastTitle || currentFavicon !== lastFavicon) {
                lastHref = location.href;
                lastTitle = document.title;
                lastFavicon = currentFavicon;
                post('listener', JSON.stringify({ href: lastHref, title: lastTitle, favicon: lastFavicon }));
            }
        }

        const titleObserver = new MutationObserver(() => notifyChange());
        const titleElement = document.querySelector('title');
        if (titleElement) {
            titleObserver.observe(titleElement, { childList: true });
        }

        const headElement = document.head || document.querySelector('head');
        if (headElement) {
            const headObserver = new MutationObserver(() => notifyChange());
            headObserver.observe(headElement, { childList: true, subtree: true });
        }

        try {
            const origPushState = history.pushState;
            history.pushState = function() {
                const ret = origPushState.apply(this, arguments);
                setTimeout(() => notifyChange(true), 0);
                return ret;
            };

            const origReplaceState = history.replaceState;
            history.replaceState = function() {
                const ret = origReplaceState.apply(this, arguments);
                setTimeout(() => notifyChange(true), 0);
                return ret;
            };
        } catch (e) {}

        setInterval(() => notifyChange(), 500);
        window.addEventListener('popstate', () => notifyChange(true));
        notifyChange(true);

        let currentHoverUrl = '';
        function postHover(url) {
            const normalized = url || '';
            if (normalized === currentHoverUrl) {
                return;
            }
            currentHoverUrl = normalized;
            post('linkHover', normalized);
        }

        function onMouseOver(event) {
            const anchor = event.target && event.target.closest ? event.target.closest('a[href]') : null;
            postHover(anchor ? anchor.href : '');
        }

        function onMouseOut(event) {
            const related = event.relatedTarget;
            if (!related) {
                postHover('');
            }
        }

        document.addEventListener('mouseover', onMouseOver, true);
        document.addEventListener('mouseout', onMouseOut, true);
    })();

    (function () {
        if (window.__oraMediaInstalled) {
            return;
        }
        window.__oraMediaInstalled = true;

        function post(payload) {
            try {
                window.__oraBridge && window.__oraBridge.postMessage('mediaEvent', JSON.stringify(payload));
            } catch (error) {}
        }

        function findNextButton() {
            const selectors = [
                '.ytp-next-button',
                'button[aria-label*="Next" i]',
                'button[title*="Next" i]',
                '[data-testid="control-button-skip-forward"]'
            ];
            for (const selector of selectors) {
                const element = document.querySelector(selector);
                if (element) return element;
            }
            return null;
        }

        function findPrevButton() {
            const selectors = [
                '.ytp-prev-button',
                'button[aria-label*="Previous" i]',
                'button[title*="Previous" i]',
                '[data-testid="control-button-skip-backward"]'
            ];
            for (const selector of selectors) {
                const element = document.querySelector(selector);
                if (element) return element;
            }
            return null;
        }

        let lastCaps = null;
        function caps() {
            const next = !!findNextButton();
            const prev = !!findPrevButton();
            if (lastCaps && lastCaps.hasNext === next && lastCaps.hasPrevious === prev) {
                return;
            }
            lastCaps = { hasNext: next, hasPrevious: prev };
            post({
                type: 'caps',
                hasNext: next,
                hasPrevious: prev
            });
        }

        const stateFrom = (element) => ({
            type: 'state',
            wasPlayed: element && element.__oraWasPlayed,
            state: element && !element.paused ? 'playing' : 'paused',
            volume: element ? (element.muted ? 0 : element.volume) : undefined,
            title: document.title
        });

        function watchRemoval(element, callback) {
            const observer = new MutationObserver((mutations) => {
                for (const mutation of mutations) {
                    for (const removed of mutation.removedNodes) {
                        if (removed === element || removed.contains(element)) {
                            callback();
                            observer.disconnect();
                            return;
                        }
                    }
                }
            });

            observer.observe(document.body, { childList: true, subtree: true });
        }

        function attach(element) {
            if (!element || element.__oraAttached) return;
            element.__oraAttached = true;
            const update = () => post(stateFrom(element));
            element.addEventListener('play', () => {
                update();
                element.__oraWasPlayed = true;
            });
            element.addEventListener('pause', update);
            element.addEventListener('ended', () => post({ type: 'ended' }));
            element.addEventListener('volumechange', () =>
                post({ type: 'volume', volume: element.muted ? 0 : element.volume })
            );
            if (!element.paused) {
                element.__oraWasPlayed = true;
                update();
            }
            watchRemoval(element, () => post({ type: 'removed' }));
        }

        function scan() {
            document.querySelectorAll('video, audio').forEach(attach);
            caps();
        }

        let scanPending = false;
        function debouncedScan() {
            if (scanPending) return;
            scanPending = true;
            if (typeof requestAnimationFrame !== 'undefined') {
                requestAnimationFrame(() => {
                    scanPending = false;
                    scan();
                });
            } else {
                setTimeout(() => {
                    scanPending = false;
                    scan();
                }, 32);
            }
        }

        const observer = new MutationObserver(debouncedScan);
        observer.observe(document.documentElement, { childList: true, subtree: true });
        scan();

        window.__oraMedia = {
            active: null,
            _pick() {
                const elements = Array.from(document.querySelectorAll('video, audio'));
                const playing = elements.find((element) => !element.paused);
                this.active = playing || elements[0] || null;
                return this.active;
            },
            play() {
                try { (this._pick() || {}).play(); return true; } catch (error) { return false; }
            },
            pause() {
                try { (this._pick() || {}).pause(); return true; } catch (error) { return false; }
            },
            toggle() {
                const element = this._pick();
                if (!element) return false;
                if (element.paused) {
                    element.play();
                } else {
                    element.pause();
                }
                return true;
            },
            setVolume(value) {
                const element = this._pick();
                if (!element) return false;
                element.muted = false;
                element.volume = Math.max(0, Math.min(1, value));
                post({ type: 'volume', volume: element.volume });
                return true;
            },
            deltaVolume(delta) {
                const element = this._pick();
                if (!element) return false;
                element.muted = false;
                element.volume = Math.max(0, Math.min(1, (element.volume || 0) + delta));
                post({ type: 'volume', volume: element.volume });
                return true;
            },
            next() {
                const element = findNextButton();
                if (!element) return false;
                element.click();
                caps();
                return true;
            },
            previous() {
                const element = findPrevButton();
                if (!element) return false;
                element.click();
                caps();
                return true;
            },
            title() {
                return document.title;
            }
        };

        window.__oraTriggerPiP = function(isActive = false) {
            const video = document.querySelector('video');

            function hasAudio(target) {
                if (!target) return false;
                if (target.audioTracks && target.audioTracks.length > 0) return true;
                if (!target.muted && target.volume > 0) return true;
                return false;
            }

            if (
                video &&
                video.tagName === 'VIDEO' &&
                !document.pictureInPictureElement &&
                !video.paused &&
                !isActive &&
                hasAudio(video)
            ) {
                video.requestPictureInPicture().catch(() => {});
            } else if (document.pictureInPictureElement) {
                document.exitPictureInPicture().catch(() => {});
            }
        };

        post({ type: 'ready', title: document.title });
    })();
    """

    private static let chromeWebStoreScript = """
    (function() {
        if (!location.hostname.includes('chromewebstore.google.com') && !location.hostname.includes('chrome.google.com')) {
            return;
        }

        function extractId() {
            const match = location.pathname.match(/detail\\/[^\\/]+\\/([a-z]{32})/i);
            return match ? match[1].toLowerCase() : null;
        }

        function getExtensionTitle() {
            const h1 = document.querySelector('h1');
            return h1 ? h1.innerText.trim() : document.title;
        }

        function updateInstallButton() {
            const extId = extractId();
            const existingBtn = document.getElementById('nfbrowser-install-btn');

            if (!extId) {
                if (existingBtn) existingBtn.remove();
                return;
            }

            if (existingBtn && existingBtn.dataset.extId === extId) {
                return;
            }

            if (existingBtn) existingBtn.remove();

            const container = document.createElement('div');
            container.id = 'nfbrowser-install-btn';
            container.dataset.extId = extId;
            container.style.cssText = `
                position: fixed;
                bottom: 24px;
                right: 24px;
                z-index: 9999999;
                display: flex;
                align-items: center;
                gap: 10px;
                background: linear-gradient(135deg, #1e1e24 0%, #141418 100%);
                border: 1px solid rgba(255, 255, 255, 0.2);
                box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5), 0 0 0 1px rgba(255,255,255,0.05);
                padding: 10px 18px;
                border-radius: 999px;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                font-size: 13px;
                font-weight: 600;
                color: #ffffff;
                cursor: pointer;
                transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
            `;

            container.innerHTML = `
                <span style="font-size: 16px;">🧩</span>
                <span id="nf-install-label">Instalar no NFBrowser</span>
            `;

            container.onmouseenter = () => {
                container.style.transform = 'translateY(-2px) scale(1.03)';
                container.style.borderColor = 'rgba(255, 255, 255, 0.35)';
            };
            container.onmouseleave = () => {
                container.style.transform = 'translateY(0) scale(1)';
                container.style.borderColor = 'rgba(255, 255, 255, 0.2)';
            };

            container.onclick = () => {
                const label = document.getElementById('nf-install-label');
                if (label) label.innerText = 'Instalando...';
                container.style.pointerEvents = 'none';
                container.style.opacity = '0.7';

                try {
                    if (window.__oraBridge && typeof window.__oraBridge.postMessage === 'function') {
                        window.__oraBridge.postMessage('extensionInstaller', JSON.stringify({
                            extensionId: extId,
                            title: getExtensionTitle()
                        }));
                    }
                } catch(e) {}
            };

            document.body.appendChild(container);
        }

        setInterval(updateInstallButton, 1000);
        window.addEventListener('popstate', updateInstallButton);
        setTimeout(updateInstallButton, 1500);
    })();
    """
}
