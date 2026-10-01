/*
  <ergo-mark>: the ergo mark, animated through the states of an evaluation.
  Geometry is the repo's logo SVG (static/brand/ergo-wordmark-white.svg), so the
  final frame is the static mark. States:
    0 [   ] nothing read   1 [ ? ] unknown   2 [ . ] subject found
    3 [.. ] gathering      4 [...] complete  5 [ therefore ] decision
  Attributes: autoplay, loop, theme="dark|light", outcome="pass|fail", size (px).
  Methods: play(), reset(), setState(n). Events: ergo:state {state}, ergo:resolved.
*/
(function () {
  if (!window.customElements || customElements.get('ergo-mark')) return;

  var BRACKET_L = 'M183.46,635.1c-14.88,0-27.03-4.71-36.45-14.13-9.42-9.42-14.13-21.57-14.13-36.45V188.74c0-14.88,4.71-27.03,14.13-36.45,9.42-9.42,21.57-14.14,36.45-14.14h84.31v53.56h-61c-8.93,0-13.39,4.96-13.39,14.88v360.06c0,9.92,4.46,14.88,13.39,14.88h61v53.56h-84.31Z';
  var BRACKET_R = 'M535.58,635.1v-53.56h61c8.93,0,13.39-4.96,13.39-14.88V206.59c0-9.92-4.46-14.88-13.39-14.88h-61v-53.56h84.31c14.88,0,27.03,4.71,36.45,14.14s14.13,21.57,14.13,36.45v395.77c0,14.88-4.71,27.03-14.13,36.45-9.42,9.42-21.57,14.13-36.45,14.13h-84.31Z';
  var VIEWBOX = '132.88 138.15 537.59 496.95';
  var PLATE = { x: 267.77, y: 252.72, s: 267.81, r: 11.8 };
  var DOT_R = 26.58;
  var CX = PLATE.x + PLATE.s / 2, CY = PLATE.y + PLATE.s / 2;
  var STEP = PLATE.s * 0.22;
  var ROW = [[CX - STEP, CY], [CX, CY], [CX + STEP, CY]];
  var THEREFORE = [[337.49, 442.22], [401.68, 331.04], [465.86, 442.22]];
  var SLIDE = 91;
  var INK = '#080F1A', PAPER = '#F7F7EF', LIME = '#D6FF4D', SIGNAL = '#FE5431';
  var TONES = [0.25, 0.5, 0.75, 1];
  var T = { contain: 0.42, ask: 0.45, d1: 0.95, d0: 1.2, d2: 1.45, move: 1.9, moveLen: 0.38, dither: 2.3, solid: 2.7 };
  var STATE_AT = [0, T.ask, T.d1, T.d0, T.d2, T.move];
  var FRAME_FOR = [0.44, 0.5, 1.0, 1.25, 1.5, 3.0];
  var SVG = 'http://www.w3.org/2000/svg';

  function bezier(x1, y1, x2, y2) {
    var cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
    var cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
    return function (x) {
      var t = x;
      for (var i = 0; i < 6; i++) {
        var f = ((ax * t + bx) * t + cx) * t - x;
        var d = (3 * ax * t + 2 * bx) * t + cx;
        if (Math.abs(f) < 1e-5 || d === 0) break;
        t -= f / d;
      }
      return ((ay * t + by) * t + cy) * t;
    };
  }
  var ease = bezier(0.16, 1, 0.3, 1);
  var clamp01 = function (v) { return v < 0 ? 0 : v > 1 ? 1 : v; };

  function cellOffset(r, c) { return ((r * 3 + c * 7) % 5) / 4; }

  function frameAt(t, fail) {
    var f = {};
    f.bx = t < T.contain ? SLIDE * (1 - ease(clamp01(t / T.contain))) : 0;
    f.ask = t >= T.ask && t < T.d1;
    var shown = [t >= T.d0, t >= T.d1, t >= T.d2];
    var k = fail ? 0 : ease(clamp01((t - T.move) / T.moveLen));
    f.dots = ROW.map(function (p, i) {
      var q = THEREFORE[i];
      return { show: shown[i] && !(fail && t >= T.move), x: p[0] + (q[0] - p[0]) * k, y: p[1] + (q[1] - p[1]) * k };
    });
    f.cross = fail && t >= T.move;
    f.decided = t >= T.dither;
    f.plate = t >= T.solid;
    f.cells = [];
    for (var r = 0; r < 5; r++) for (var c = 0; c < 5; c++) {
      var start = T.dither + cellOffset(r, c) * 0.16;
      f.cells.push(f.plate || t < start ? -1 : Math.min(3, Math.floor((t - start) / 0.08)));
    }
    return f;
  }

  function el(name, attrs, parent) {
    var n = document.createElementNS(SVG, name);
    for (var a in attrs) n.setAttribute(a, attrs[a]);
    if (parent) parent.appendChild(n);
    return n;
  }

  class ErgoMark extends HTMLElement {
    static get observedAttributes() { return ['theme', 'outcome', 'size']; }

    constructor() {
      super();
      var root = this.attachShadow({ mode: 'open' });
      var style = document.createElement('style');
      style.textContent = ':host{display:inline-block;line-height:0;vertical-align:middle}' +
        'svg{display:block;width:100%;height:auto;overflow:visible}' +
        '.sr{position:absolute;width:1px;height:1px;margin:-1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;border:0}';
      root.appendChild(style);
      var svg = el('svg', { viewBox: VIEWBOX, role: 'img', 'aria-label': 'ergo' });
      var clip = el('clipPath', { id: 'plate' }, el('defs', {}, svg));
      el('rect', { x: PLATE.x, y: PLATE.y, width: PLATE.s, height: PLATE.s, rx: PLATE.r }, clip);
      var cells = el('g', { 'clip-path': 'url(#plate)' }, svg);
      this._cells = [];
      var size = PLATE.s / 5;
      for (var r = 0; r < 5; r++) for (var c = 0; c < 5; c++) {
        this._cells.push(el('rect', { x: PLATE.x + c * size, y: PLATE.y + r * size, width: size + 0.5, height: size + 0.5 }, cells));
      }
      this._plate = el('rect', { x: PLATE.x, y: PLATE.y, width: PLATE.s, height: PLATE.s, rx: PLATE.r }, svg);
      this._left = el('path', { d: BRACKET_L }, svg);
      this._right = el('path', { d: BRACKET_R }, svg);
      this._ask = el('text', { x: CX, y: CY, 'text-anchor': 'middle', 'dominant-baseline': 'central', 'font-size': 190,
        'font-family': '"IBM Plex Mono", ui-monospace, monospace', 'fill-opacity': 0.6 }, svg);
      this._ask.textContent = '?';
      this._dots = [0, 1, 2].map(function () { return el('circle', { r: DOT_R }, svg); });
      var arm = DOT_R * 2.2;
      this._cross = el('g', { 'stroke-width': 30, 'stroke-linecap': 'round' }, svg);
      el('line', { x1: CX - arm, y1: CY - arm, x2: CX + arm, y2: CY + arm }, this._cross);
      el('line', { x1: CX - arm, y1: CY + arm, x2: CX + arm, y2: CY - arm }, this._cross);
      root.appendChild(svg);
      this._live = document.createElement('span');
      this._live.className = 'sr';
      this._live.setAttribute('aria-live', 'polite');
      root.appendChild(this._live);
      this._state = -1;
      this._raf = 0;
      this._timer = 0;
      this._render(frameAt(FRAME_FOR[5], false));
    }

    connectedCallback() {
      this._applySize();
      if (this.hasAttribute('autoplay') && !this._still()) {
        this._render(frameAt(0, this._fail()));
        this._autoplay();
      } else {
        this.setState(5);
      }
    }

    disconnectedCallback() { this._stop(); if (this._io) this._io.disconnect(); }

    attributeChangedCallback(name) {
      if (name === 'size') this._applySize();
      else if (this._last) this._render(this._last);
    }

    play() {
      this._stop();
      if (this._still()) { this.setState(5); this._emit(5); this._done(); return; }
      var fail = this._fail(), self = this, t0 = performance.now(), stateIdx = -1;
      var tick = function (now) {
        var t = (now - t0) / 1000;
        while (stateIdx < 5 && t >= STATE_AT[stateIdx + 1]) self._emit(++stateIdx);
        self._render(frameAt(t, fail));
        if (t < T.solid) { self._raf = requestAnimationFrame(tick); return; }
        self._done();
        if (self.hasAttribute('loop')) self._timer = setTimeout(function () { self.play(); }, 1500);
      };
      this._raf = requestAnimationFrame(tick);
    }

    reset() { this._stop(); this.setState(0); }

    setState(n) {
      this._stop();
      n = Math.max(0, Math.min(5, n | 0));
      this._state = n;
      this._render(frameAt(FRAME_FOR[n], this._fail()));
    }

    _still() { return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches; }
    _fail() { return this.getAttribute('outcome') === 'fail'; }

    _applySize() {
      var size = parseFloat(this.getAttribute('size'));
      this.style.width = size > 0 ? size + 'px' : '';
    }

    _autoplay() {
      var self = this;
      if (!('IntersectionObserver' in window)) { this.play(); return; }
      this._io = new IntersectionObserver(function (entries) {
        if (!entries[0].isIntersecting) return;
        self._io.disconnect();
        self.play();
      }, { threshold: 0.5 });
      this._io.observe(this);
    }

    _stop() {
      cancelAnimationFrame(this._raf);
      clearTimeout(this._timer);
    }

    _emit(n) {
      this._state = n;
      if (n === 1) this._live.textContent = 'evaluating';
      if (n === 5) this._live.textContent = this._fail() ? 'check failed' : 'conclusion reached';
      this.dispatchEvent(new CustomEvent('ergo:state', { detail: { state: n }, bubbles: true }));
    }

    _done() { this.dispatchEvent(new CustomEvent('ergo:resolved', { bubbles: true })); }

    _render(f) {
      this._last = f;
      var light = this.getAttribute('theme') === 'light';
      var fg = light ? INK : PAPER;
      var accent = this._fail() ? SIGNAL : LIME;
      this._left.setAttribute('fill', fg);
      this._right.setAttribute('fill', fg);
      this._left.setAttribute('transform', 'translate(' + (-f.bx) + ' 0)');
      this._right.setAttribute('transform', 'translate(' + f.bx + ' 0)');
      this._ask.setAttribute('fill', fg);
      this._ask.style.display = f.ask ? '' : 'none';
      var dotFill = f.decided ? INK : LIME;
      this._dots.forEach(function (d, i) {
        var p = f.dots[i];
        d.style.display = p.show ? '' : 'none';
        d.setAttribute('cx', p.x);
        d.setAttribute('cy', p.y);
        d.setAttribute('fill', dotFill);
      });
      this._cross.style.display = f.cross ? '' : 'none';
      this._cross.setAttribute('stroke', f.decided ? INK : SIGNAL);
      this._cells.forEach(function (c, i) {
        var lvl = f.cells[i];
        c.style.display = lvl < 0 ? 'none' : '';
        if (lvl >= 0) { c.setAttribute('fill', accent); c.setAttribute('fill-opacity', TONES[lvl]); }
      });
      this._plate.style.display = f.plate ? '' : 'none';
      this._plate.setAttribute('fill', accent);
    }
  }

  customElements.define('ergo-mark', ErgoMark);
})();
