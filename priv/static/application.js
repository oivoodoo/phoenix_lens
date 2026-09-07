(function () {
  if (!window.Phoenix || !window.LiveView) return;

  var TABLE_CTX = { FROM: 1, JOIN: 1, INTO: 1, UPDATE: 1, TABLE: 1 };

  function parseCatalog(raw) {
    try {
      return JSON.parse(raw || "{}");
    } catch (e) {
      return { tables: [], keywords: [] };
    }
  }

  function context(left) {
    var dotted = /([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z0-9_]*)$/.exec(left);
    if (dotted) return { prefix: dotted[2], table: dotted[1].toLowerCase(), kind: "column", dotted: true };

    var m = /[A-Za-z0-9_]*$/.exec(left);
    var prefix = m ? m[0] : "";
    var before = left.slice(0, left.length - prefix.length).trim().toUpperCase();
    var prev = /([A-Z]+)$/.exec(before);
    var word = prev ? prev[1] : "";
    return {
      prefix: prefix,
      table: null,
      kind: TABLE_CTX[word] ? "table" : "any",
      dotted: false
    };
  }

  function item(value, kind, detail, protectedCol) {
    return { value: value, kind: kind, detail: detail || kind, protected: !!protectedCol };
  }

  function candidates(catalog, ctx) {
    var tables = catalog.tables || [];
    var keywords = catalog.keywords || [];
    if (ctx.kind === "table") {
      return tables.map(function (t) { return item(t.name, "table", "table"); });
    }
    if (ctx.kind === "column") {
      var table = tables.find(function (t) { return t.name.toLowerCase() === ctx.table; });
      if (!table) return [];
      return (table.columns || []).map(function (c) {
        return item(c.name, "column", table.name + "." + c.name + (c.protected ? " · redacted" : ""), c.protected);
      });
    }
    var out = [];
    tables.forEach(function (t) {
      out.push(item(t.name, "table", "table"));
      (t.columns || []).forEach(function (c) {
        out.push(item(c.name, "column", t.name + "." + c.name + (c.protected ? " · redacted" : ""), c.protected));
      });
    });
    keywords.forEach(function (k) { out.push(item(k, "keyword", "keyword")); });
    return out;
  }

  function suggest(catalog, sql, cursor) {
    var left = sql.slice(0, cursor);
    var ctx = context(left);
    var prefix = ctx.prefix.toLowerCase();
    if (!prefix && ctx.kind === "any") return [];
    return candidates(catalog, ctx)
      .filter(function (it) { return !prefix || it.value.toLowerCase().indexOf(prefix) === 0; })
      .sort(function (a, b) {
        var da = a.value.toLowerCase();
        var db = b.value.toLowerCase();
        var ra = da === prefix ? 0 : da.indexOf(prefix) === 0 ? 1 : 2;
        var rb = db === prefix ? 0 : db.indexOf(prefix) === 0 ? 1 : 2;
        return ra - rb || da.localeCompare(db);
      })
      .slice(0, 12)
      .map(function (it) { it.dotted = ctx.dotted; return it; });
  }

  function applyToken(value, cursor, insert, dotted) {
    var left = value.slice(0, cursor);
    var right = value.slice(cursor);
    if (dotted) left = left.replace(/([A-Za-z_][A-Za-z0-9_]*\.)[A-Za-z0-9_]*$/, "$1" + insert);
    else left = left.replace(/[A-Za-z0-9_]*$/, insert);
    return { value: left + right, cursor: left.length };
  }

  var SqlEditor = {
    mounted: function () {
      var el = this.el;
      this.catalog = parseCatalog(el.dataset.catalog);
      this.index = 0;
      this.items = [];
      this.menu = document.createElement("ul");
      this.menu.className = "lens-ac";
      this.menu.hidden = true;
      el.parentNode.appendChild(this.menu);
      var self = this;
      el.addEventListener("input", function () { self.refresh(); });
      el.addEventListener("click", function () { self.refresh(); });
      el.addEventListener("keydown", function (e) { self.onKey(e); });
      el.addEventListener("blur", function () {
        setTimeout(function () { self.hide(); }, 120);
      });
      var run = el.parentNode.querySelector("[data-sql-run]");
      if (run) {
        run.addEventListener("click", function (e) {
          e.preventDefault();
          self.hide();
          self.pushEvent("run", { sql: el.value });
        });
      }
    },
    destroyed: function () {
      if (this.menu && this.menu.parentNode) this.menu.parentNode.removeChild(this.menu);
    },
    refresh: function () {
      var el = this.el;
      this.items = suggest(this.catalog, el.value, el.selectionStart || 0);
      this.index = 0;
      this.render();
    },
    render: function () {
      var items = this.items;
      if (!items.length) {
        this.hide();
        return;
      }
      var self = this;
      this.menu.innerHTML = items.map(function (it, i) {
        return (
          '<li class="' +
          (i === self.index ? "active" : "") +
          (it.protected ? " protected" : "") +
          '" data-kind="' + it.kind + '" data-i="' + i + '">' +
          '<span class="lens-ac-kind">' + it.kind + "</span>" +
          "<strong>" + it.value + "</strong>" +
          '<span class="lens-ac-detail">' + it.detail + "</span>" +
          "</li>"
        );
      }).join("");
      this.menu.hidden = false;
      Array.prototype.forEach.call(this.menu.querySelectorAll("li"), function (li) {
        li.addEventListener("mousedown", function (e) {
          e.preventDefault();
          self.pick(parseInt(li.getAttribute("data-i"), 10));
        });
      });
    },
    hide: function () {
      this.items = [];
      if (this.menu) this.menu.hidden = true;
    },
    onKey: function (e) {
      if ((e.key === "Enter" || e.key === "NumpadEnter") && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        e.stopPropagation();
        this.hide();
        this.pushEvent("run", { sql: this.el.value });
        return;
      }
      if (this.menu.hidden || !this.items.length) return;
      if (e.key === "ArrowDown") {
        e.preventDefault();
        this.index = (this.index + 1) % this.items.length;
        this.render();
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        this.index = (this.index - 1 + this.items.length) % this.items.length;
        this.render();
      } else if (e.key === "Enter" || e.key === "Tab") {
        e.preventDefault();
        this.pick(this.index);
      } else if (e.key === "Escape") {
        e.preventDefault();
        this.hide();
      }
    },
    pick: function (i) {
      var it = this.items[i];
      if (!it) return;
      var el = this.el;
      var next = applyToken(el.value, el.selectionStart || 0, it.value, it.dotted);
      el.value = next.value;
      el.setSelectionRange(next.cursor, next.cursor);
      el.dispatchEvent(new Event("input", { bubbles: true }));
      this.hide();
      el.focus();
    }
  };

  var ResultDownload = {
    mounted: function () {
      this.handleEvent("lens-download", function (payload) {
        var blob = new Blob([payload.body], { type: payload.mime || "text/plain" });
        var url = URL.createObjectURL(blob);
        var a = document.createElement("a");
        a.href = url;
        a.download = payload.filename || "lens-results";
        document.body.appendChild(a);
        a.click();
        a.remove();
        URL.revokeObjectURL(url);
      });
    }
  };

  function b64ToBuf(b64) {
    if (!b64) return new ArrayBuffer(0);
    var s = String(b64).replace(/-/g, "+").replace(/_/g, "/");
    while (s.length % 4) s += "=";
    var bin = atob(s);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.buffer;
  }

  function bufToB64url(buf) {
    var bytes = new Uint8Array(buf);
    var str = "";
    for (var i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
    return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  function credentialIds(list) {
    return (list || []).map(function (id) {
      return { type: "public-key", id: b64ToBuf(id) };
    });
  }

  var Passkey = {
    mounted: function () {
      var self = this;
      this.assertOpts = null;
      this.pushEvent("passkey_origin", { origin: window.location.origin });
      var form = this.el.querySelector("form[phx-submit='start_passkey']");
      if (form && !form.querySelector("input[name='origin']")) {
        var hidden = document.createElement("input");
        hidden.type = "hidden";
        hidden.name = "origin";
        hidden.value = window.location.origin;
        form.appendChild(hidden);
      }
      this.handleEvent("passkey-register-options", function (opts) {
        self.register(opts);
      });
      this.handleEvent("passkey-assert-options", function (opts) {
        self.assertOpts = opts;
      });
      var btn = this.el.querySelector("[data-passkey-assert]");
      if (btn) {
        btn.addEventListener("click", function () {
          if (self.assertOpts) self.assert(self.assertOpts);
          else self.pushEvent("passkey_origin", { origin: window.location.origin });
        });
      }
    },
    register: function (opts) {
      var self = this;
      if (!window.PublicKeyCredential || !navigator.credentials) {
        this.pushEvent("passkey_attestation", { error: "This browser does not support passkeys" });
        return;
      }
      navigator.credentials
        .create({
          publicKey: {
            challenge: b64ToBuf(opts.challenge),
            rp: { id: opts.rpId, name: opts.rpName || "Lens" },
            user: {
              id: b64ToBuf(opts.userId),
              name: opts.userName || "operator",
              displayName: opts.userDisplayName || "Lens operator"
            },
            pubKeyCredParams: [
              { type: "public-key", alg: -7 },
              { type: "public-key", alg: -257 }
            ],
            authenticatorSelection: {
              residentKey: "preferred",
              userVerification: "preferred"
            },
            excludeCredentials: credentialIds(opts.excludeCredentials),
            timeout: 60000,
            attestation: "none"
          }
        })
        .then(function (cred) {
          if (!cred) {
            self.pushEvent("passkey_attestation", { error: "Passkey registration was cancelled" });
            return;
          }
          self.pushEvent("passkey_attestation", {
            rawId: bufToB64url(cred.rawId),
            attestationObject: bufToB64url(cred.response.attestationObject),
            clientDataJSON: bufToB64url(cred.response.clientDataJSON)
          });
        })
        .catch(function (err) {
          self.pushEvent("passkey_attestation", {
            error: (err && err.message) || "Passkey registration failed"
          });
        });
    },
    assert: function (opts) {
      var self = this;
      if (!window.PublicKeyCredential || !navigator.credentials) {
        this.pushEvent("passkey_assert", { error: "This browser does not support passkeys" });
        return;
      }
      navigator.credentials
        .get({
          publicKey: {
            challenge: b64ToBuf(opts.challenge),
            rpId: opts.rpId,
            allowCredentials: credentialIds(opts.allowCredentials),
            userVerification: "preferred",
            timeout: 60000
          }
        })
        .then(function (cred) {
          if (!cred) {
            self.pushEvent("passkey_assert", { error: "Passkey sign-in was cancelled" });
            return;
          }
          self.pushEvent("passkey_assert", {
            rawId: bufToB64url(cred.rawId),
            authenticatorData: bufToB64url(cred.response.authenticatorData),
            signature: bufToB64url(cred.response.signature),
            clientDataJSON: bufToB64url(cred.response.clientDataJSON)
          });
        })
        .catch(function (err) {
          self.pushEvent("passkey_assert", {
            error: (err && err.message) || "Passkey sign-in failed"
          });
        });
    }
  };

  var COLS = 12;
  var MIN_W = 3;
  var MIN_H = 3;
  var ROW_H = 56;
  var GAP = 12;

  function dashMetrics(el) {
    var w = el.clientWidth || 1;
    var colW = (w - GAP * (COLS - 1)) / COLS;
    return { colW: colW, rowH: ROW_H, gap: GAP };
  }

  function clampCard(col, row, sx, sy) {
    col = Math.max(0, Math.min(col, COLS - MIN_W));
    row = Math.max(0, row);
    sx = Math.max(MIN_W, Math.min(sx, COLS - col));
    sy = Math.max(MIN_H, Math.min(sy, 40));
    return { col: col, row: row, sx: sx, sy: sy };
  }

  function readCard(el) {
    return {
      id: el.getAttribute("data-id"),
      col: parseInt(el.getAttribute("data-col"), 10) || 0,
      row: parseInt(el.getAttribute("data-row"), 10) || 0,
      sx: parseInt(el.getAttribute("data-sx"), 10) || 6,
      sy: parseInt(el.getAttribute("data-sy"), 10) || 5
    };
  }

  function applyCard(el, card) {
    el.setAttribute("data-col", card.col);
    el.setAttribute("data-row", card.row);
    el.setAttribute("data-sx", card.sx);
    el.setAttribute("data-sy", card.sy);
    el.style.gridColumn = card.col + 1 + " / span " + card.sx;
    el.style.gridRow = card.row + 1 + " / span " + card.sy;
  }

  function others(board, skipId) {
    return Array.prototype.map
      .call(board.querySelectorAll(".lens-dash-card"), function (el) {
        if (el.getAttribute("data-id") === skipId) return null;
        return readCard(el);
      })
      .filter(Boolean);
  }

  function hits(a, b) {
    return a.col < b.col + b.sx && a.col + a.sx > b.col && a.row < b.row + b.sy && a.row + a.sy > b.row;
  }

  function fit(board, card) {
    var rest = others(board, card.id);
    var next = { col: card.col, row: card.row, sx: card.sx, sy: card.sy, id: card.id };
    var guard = 0;
    while (rest.some(function (o) { return hits(next, o); }) && guard++ < 80) {
      next.row += 1;
    }
    return next;
  }

  var DashBoard = {
    mounted: function () {
      this.onDown = this.onDown.bind(this);
      this.onMove = this.onMove.bind(this);
      this.onUp = this.onUp.bind(this);
      this.el.addEventListener("pointerdown", this.onDown);
    },
    updated: function () {},
    destroyed: function () {
      this.el.removeEventListener("pointerdown", this.onDown);
      window.removeEventListener("pointermove", this.onMove);
      window.removeEventListener("pointerup", this.onUp);
    },
    editing: function () {
      return this.el.getAttribute("data-editing") === "true";
    },
    onDown: function (e) {
      if (!this.editing()) return;
      var resize = e.target.closest("[data-dash-resize]");
      var drag = e.target.closest("[data-dash-drag]");
      var cardEl = e.target.closest(".lens-dash-card");
      if (!cardEl || (!resize && !drag)) return;
      if (e.target.closest("button") && !resize) return;
      e.preventDefault();
      this.mode = resize ? "resize" : "drag";
      this.cardEl = cardEl;
      this.start = readCard(cardEl);
      this.startX = e.clientX;
      this.startY = e.clientY;
      this.metrics = dashMetrics(this.el);
      cardEl.classList.add("is-moving");
      window.addEventListener("pointermove", this.onMove);
      window.addEventListener("pointerup", this.onUp);
    },
    onMove: function (e) {
      if (!this.cardEl) return;
      var m = this.metrics;
      var dCol = Math.round((e.clientX - this.startX) / (m.colW + m.gap));
      var dRow = Math.round((e.clientY - this.startY) / (m.rowH + m.gap));
      var next;
      if (this.mode === "resize") {
        next = clampCard(this.start.col, this.start.row, this.start.sx + dCol, this.start.sy + dRow);
      } else {
        next = clampCard(this.start.col + dCol, this.start.row + dRow, this.start.sx, this.start.sy);
      }
      next.id = this.start.id;
      applyCard(this.cardEl, next);
    },
    onUp: function () {
      window.removeEventListener("pointermove", this.onMove);
      window.removeEventListener("pointerup", this.onUp);
      if (!this.cardEl) return;
      var card = fit(this.el, readCard(this.cardEl));
      applyCard(this.cardEl, card);
      this.cardEl.classList.remove("is-moving");
      this.pushEvent("place_card", {
        id: card.id,
        col: card.col,
        row: card.row,
        size_x: card.sx,
        size_y: card.sy
      });
      this.cardEl = null;
      this.mode = null;
    }
  };

  var csrf = document.querySelector("meta[name='csrf-token']");
  var token = csrf ? csrf.getAttribute("content") : "";
  var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    params: { _csrf_token: token },
    hooks: { SqlEditor: SqlEditor, ResultDownload: ResultDownload, Passkey: Passkey, DashBoard: DashBoard }
  });
  liveSocket.connect();
  window.liveSocket = liveSocket;
})();
