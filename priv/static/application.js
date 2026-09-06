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

  var csrf = document.querySelector("meta[name='csrf-token']");
  var token = csrf ? csrf.getAttribute("content") : "";
  var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    params: { _csrf_token: token },
    hooks: { SqlEditor: SqlEditor }
  });
  liveSocket.connect();
  window.liveSocket = liveSocket;
})();
