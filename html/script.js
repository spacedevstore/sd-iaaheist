
(function () {
    'use strict';

    var COLORS = ['red', 'blue', 'green', 'yellow', 'purple', 'cyan', 'orange', 'pink', 'white'];
    var TOTAL = 9;

    var container, grid, timerBar, hint, resultOverlay, resultIcon;

    function initDOM() {
        container     = document.getElementById('minigame-container');
        grid          = document.getElementById('grid-container');
        timerBar      = document.getElementById('timer-bar');
        hint          = document.getElementById('instruction-text');
        resultOverlay = document.getElementById('result-overlay');
        resultIcon    = document.getElementById('result-icon');
    }

    var tiles = [];
    var data  = [];
    var targetCount = 5;
    var pick = 0;
    var timer = null;
    var timeLeft = 0;
    var timeTotal = 0;
    var timeLimitMs = 10000;
    var phase = 'idle';

    function shuffle(a) {
        for (var i = a.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var t = a[i]; a[i] = a[j]; a[j] = t;
        }
        return a;
    }

    function resName() {
        try { if (typeof GetParentResourceName === 'function') return GetParentResourceName(); } catch (e) {}
        return 'sd-iaaheist';
    }

    // ---- Build ----
    function build(targets) {
        grid.innerHTML = '';
        tiles = [];
        data  = [];
        pick  = 0;
        targetCount = targets;

        var colors = shuffle(COLORS.slice(0, TOTAL));

        var d = [];
        for (var i = 0; i < targets; i++) d.push({ color: colors[i], seq: i });
        for (var i = targets; i < TOTAL; i++) d.push({ color: colors[i], seq: -1 });
        shuffle(d);
        data = d;

        for (var i = 0; i < TOTAL; i++) {
            var info = d[i];
            var isTarget = info.seq !== -1;
            var label = isTarget ? '<span class="tile-seq">' + (info.seq + 1) + '</span>' : '';

            var el = document.createElement('div');
            el.className = 'tile tile-color-' + info.color;
            el.innerHTML =
                '<div class="tile-inner">' +
                '<div class="tile-face tile-back"></div>' +
                '<div class="tile-face tile-front">' + label + '</div>' +
                '</div>';

            (function (idx) {
                el.addEventListener('click', function () { onClick(idx); });
            })(i);

            grid.appendChild(el);
            tiles.push(el);
        }
    }

    // ---- Phases ----
    function memorize() {
        phase = 'memorize';
        hint.textContent = 'MEMORIZE';
        hint.classList.add('active');

        for (var i = 0; i < tiles.length; i++) tiles[i].classList.add('revealed');

        var ms = 2000 + targetCount * 400;
        setTimeout(function () {
            for (var i = 0; i < tiles.length; i++) tiles[i].classList.remove('revealed');
            hint.textContent = '';
            setTimeout(startPick, 450);
        }, ms);
    }

    function startPick() {
        phase = 'pick';
        pick = 0;
        hint.textContent = 'SELECT IN ORDER';

        timeLeft = timeLimitMs;
        timeTotal = timeLimitMs;
        timerBar.style.width = '100%';
        timerBar.className = 'timer-fill';

        timer = setInterval(function () {
            timeLeft -= 100;
            var pct = Math.max(0, (timeLeft / timeTotal) * 100);
            timerBar.style.width = pct + '%';
            if (pct < 20) timerBar.className = 'timer-fill danger';
            else if (pct < 40) timerBar.className = 'timer-fill warning';
            if (timeLeft <= 0) { clearInterval(timer); end(false); }
        }, 100);
    }

    // ---- Click ----
    function onClick(idx) {
        if (phase !== 'pick') return;
        var el = tiles[idx];
        var d  = data[idx];
        if (el.classList.contains('matched') || el.classList.contains('locked')) return;

        el.classList.add('revealed');

        if (d.seq === -1 || d.seq !== pick) {
            el.classList.add('wrong');
            clearInterval(timer);
            setTimeout(function () { end(false); }, 400);
        } else {
            el.classList.add('matched');
            pick++;
            if (pick >= targetCount) { clearInterval(timer); end(true); }
        }
    }

    // ---- End ----
    function end(ok) {
        phase = 'result';
        for (var i = 0; i < tiles.length; i++) tiles[i].classList.add('locked');
        hint.textContent = '';

        resultOverlay.className = 'result ' + (ok ? 'success' : 'fail');
        resultIcon.textContent = ok ? '✓' : '✗';

        var res = resName();
        setTimeout(function () {
            container.classList.add('hidden');
            resultOverlay.className = 'result hidden';
            try {
                fetch('https://' + res + '/minigameResult', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ success: ok })
                });
            } catch (e) {}
        }, 800);
    }

    // ---- NUI ----
    window.addEventListener('message', function (e) {
        var d = e.data;
        if (d.action === 'startMinigame') {
            initDOM();
            phase = 'idle';
            clearInterval(timer);

            var blocks = d.blocks || 5;
            timeLimitMs = d.time || 10000;
            if (blocks < 3) blocks = 3;
            if (blocks > 7) blocks = 7;

            resultOverlay.className = 'result hidden';
            timerBar.style.width = '100%';
            timerBar.className = 'timer-fill';
            hint.textContent = '';
            hint.classList.remove('active');

            container.classList.remove('hidden');
            build(blocks);
            setTimeout(memorize, 350);
        }
        if (d.action === 'closeMinigame') {
            if (container) { clearInterval(timer); container.classList.add('hidden'); }
        }
    });

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initDOM);
    else initDOM();
})();
