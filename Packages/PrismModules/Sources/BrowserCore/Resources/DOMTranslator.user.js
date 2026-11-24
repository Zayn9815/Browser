(() => {
    'use strict';

    const STATE_KEY = '__prism_dom_translator_v1';
    if (window[STATE_KEY]) return;

    const SKIP_TAGS = new Set([
        'SCRIPT', 'STYLE', 'NOSCRIPT', 'CODE', 'PRE', 'TEXTAREA', 'INPUT',
        'SELECT', 'OPTION', 'SVG', 'MATH', 'CANVAS', 'IFRAME', 'VIDEO', 'AUDIO'
    ]);

    const nodeRegistry = new Map();
    let nextId = 1;

    function isVisibleElement(el) {
        if (!el || el.nodeType !== 1) return false;
        if (SKIP_TAGS.has(el.tagName)) return false;
        if (el.isContentEditable) return false;
        try {
            const style = window.getComputedStyle(el);
            if (style.display === 'none' || style.visibility === 'hidden') return false;
        } catch (_) {}
        return true;
    }

    function collectTranslatableSegments(maxCount) {
        const limit = typeof maxCount === 'number' && maxCount > 0 ? maxCount : 240;
        const segments = [];
        if (!document.body) return JSON.stringify(segments);

        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            {
                acceptNode(node) {
                    const parent = node.parentElement;
                    if (!parent || !isVisibleElement(parent)) return NodeFilter.FILTER_REJECT;
                    const text = (node.nodeValue || '').trim();
                    if (text.length < 2) return NodeFilter.FILTER_SKIP;
                    if (/^[\d\s.,:/\-+%$€£¥•|]+$/.test(text)) return NodeFilter.FILTER_SKIP;
                    return NodeFilter.FILTER_ACCEPT;
                }
            }
        );

        let current;
        while ((current = walker.nextNode()) && segments.length < limit) {
            let assignedId = current.__prismTxId;
            if (!assignedId) {
                assignedId = 't_' + (nextId++);
                current.__prismTxId = assignedId;
                nodeRegistry.set(assignedId, {
                    node: current,
                    original: current.nodeValue
                });
            }
            const entry = nodeRegistry.get(assignedId);
            if (entry) {
                segments.push({
                    id: assignedId,
                    text: entry.original
                });
            }
        }
        return JSON.stringify(segments);
    }

    function applyTranslatedSegments(jsonString) {
        try {
            const items = JSON.parse(jsonString);
            if (!Array.isArray(items)) return 0;
            let applied = 0;
            for (const item of items) {
                if (!item || typeof item.id !== 'string' || typeof item.text !== 'string') continue;
                const entry = nodeRegistry.get(item.id);
                if (entry && entry.node && entry.node.isConnected) {
                    entry.node.nodeValue = item.text;
                    applied += 1;
                }
            }
            return applied;
        } catch (_) {
            return 0;
        }
    }

    function restoreOriginalPage() {
        let restored = 0;
        for (const [, entry] of nodeRegistry.entries()) {
            if (entry && entry.node && entry.node.isConnected) {
                entry.node.nodeValue = entry.original;
                restored += 1;
            }
        }
        return restored;
    }

    window[STATE_KEY] = true;
    window.__prismCollectTranslatableSegments = collectTranslatableSegments;
    window.__prismApplyTranslatedSegments = applyTranslatedSegments;
    window.__prismRestoreOriginalPage = restoreOriginalPage;
})();
